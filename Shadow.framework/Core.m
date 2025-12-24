#import <Shadow/Core.h>
#import <Shadow/Core+Utilities.h>
#import <Shadow/Backend.h>
#import <RootBridge.h>
#import <dlfcn.h>
#import <pwd.h>
#import <mach-o/dyld.h>
#import <substrate.h> // Ensure you have libsubstrate/CydiaSubstrate
#import "../vendor/apple/dyld_priv.h"

// --- [NEW] LIBRARY MASKING ENGINE GLOBALS ---
static uint32_t (*orig_dyld_image_count)(void);
static const char* (*orig_dyld_get_image_name)(uint32_t image_index);
static const struct mach_header* (*orig_dyld_get_image_header)(uint32_t image_index);
static uint32_t shadow_index = -1;

// Hooked functions to "skip" Shadow in the list
uint32_t hooked_dyld_image_count(void) {
    uint32_t count = orig_dyld_image_count();
    return (shadow_index != -1) ? (count - 1) : count;
}

const char* hooked_dyld_get_image_name(uint32_t image_index) {
    if (shadow_index != -1 && image_index >= shadow_index) {
        return orig_dyld_get_image_name(image_index + 1);
    }
    return orig_dyld_get_image_name(image_index);
}

const struct mach_header* hooked_dyld_get_image_header(uint32_t image_index) {
    if (shadow_index != -1 && image_index >= shadow_index) {
        return orig_dyld_get_image_header(image_index + 1);
    }
    return orig_dyld_get_image_header(image_index);
}

@implementation Shadow {
    NSCache* pathCache;
}

@synthesize bundlePath, homePath, realHomePath, hasAppSandbox, rootless;

- (instancetype)init {
    if((self = [super init])) {
        // 1. Path Setup
        bundlePath = [[[self class] getExecutablePath] stringByDeletingLastPathComponent];
        homePath = NSHomeDirectory();
        realHomePath = @(getpwuid(getuid())->pw_dir);
        bundlePath = [[self class] getStandardizedPath:bundlePath];
        homePath = [[self class] getStandardizedPath:homePath];
        realHomePath = [[self class] getStandardizedPath:realHomePath];
        hasAppSandbox = [[bundlePath pathExtension] isEqualToString:@"app"];
        
        // 2. Rootless Detection
        rootless = [RootBridge isJBRootless];
        if(!rootless) {
            rootless = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"];
        }

        // 3. Initialize Performance Cache
        pathCache = [NSCache new];
        [pathCache setCountLimit:1500];

        backend = [ShadowBackend new];

        // 4. [NEW] Initialize Library Masking
        uint32_t count = _dyld_image_count();
        for (uint32_t i = 0; i < count; i++) {
            const char* name = _dyld_get_image_name(i);
            if (name && (strstr(name, "Shadow.dylib") || strstr(name, "RootBridge"))) {
                shadow_index = i;
                break;
            }
        }

        if (shadow_index != -1) {
            MSHookFunction((void *)_dyld_image_count, (void *)hooked_dyld_image_count, (void **)&orig_dyld_image_count);
            MSHookFunction((void *)_dyld_get_image_name, (void *)hooked_dyld_get_image_name, (void **)&orig_dyld_get_image_name);
            MSHookFunction((void *)_dyld_get_image_header, (void *)hooked_dyld_get_image_header, (void **)&orig_dyld_get_image_header);
        }
    }
    return self;
}

+ (instancetype)sharedInstance {
    static Shadow* sharedInstance = nil;
    static dispatch_once_t onceToken = 0;
    dispatch_once(&onceToken, ^{
        sharedInstance = [self new];
    });
    return sharedInstance;
}

- (BOOL)isAddrExternal:(const void *)addr {
    if(!addr) return NO;
    const char* image_path = dyld_image_path_containing_address(addr);
    if(image_path) {
        if(strstr(image_path, [bundlePath fileSystemRepresentation]) != NULL) {
            return NO;
        }
        return YES;
    }
    return NO;
}

- (BOOL)isAddrRestricted:(const void *)addr {
    if(addr) {
        const char* image_path = dyld_image_path_containing_address(addr);
        return [self isCPathRestricted:image_path];
    }
    return NO;
}

- (BOOL)isCPathRestricted:(const char *)path {
    if(path) {
        return [self isPathRestricted:[NSString stringWithUTF8String:path]];
    }
    return NO;
}

- (BOOL)isPathRestricted:(NSString *)path {
    return [self isPathRestricted:path options:nil];
}

- (BOOL)isPathRestricted:(NSString *)path options:(NSDictionary<NSString *, id> *)options {
    if(!path || [path length] == 0 || [path isEqualToString:@"/"]) {
        return NO;
    }

    if(!options) {
        NSNumber* cached = [pathCache objectForKey:path];
        if(cached) return [cached boolValue];
    }

    path = [path stringByExpandingTildeInPath];
    if([path characterAtIndex:0] == '~') return NO;

    if(![path isAbsolutePath]) {
        NSString* cwd = [options objectForKey:kShadowRestrictionWorkingDir];
        if(!cwd || ![cwd isAbsolutePath]) {
            cwd = [[NSFileManager defaultManager] currentDirectoryPath];
        }
        path = [cwd stringByAppendingPathComponent:path];
    }

    path = [[self class] getStandardizedPath:path];
    BOOL shouldCheckPath = (!hasAppSandbox || (![path hasPrefix:bundlePath] && ![path hasPrefix:homePath]));
    BOOL restricted = NO;

    if(shouldCheckPath) {
        NSString* file_ext = [options objectForKey:kShadowRestrictionFileExtension];
        if(file_ext && ![[path pathExtension] isEqualToString:file_ext]) {
            path = [path stringByAppendingFormat:@".%@", file_ext];
        }

        if(rootless) {
            if([path hasPrefix:@"/var/jb"] || [path hasPrefix:@"/private/preboot/"]) {
                restricted = YES;
            } else if(![path hasPrefix:@"/var"] && ![path hasPrefix:@"/private/preboot"] && ![path hasPrefix:@"/usr/lib"]) {
                restricted = NO;
            } else if([backend isPathRestricted:path]) {
                restricted = YES;
            }
        } else if([backend isPathRestricted:path]) {
            restricted = YES;
        }

        if(!restricted && [path hasPrefix:@"/usr/lib"]) {
            int errno_old = errno;
            if(access([path fileSystemRepresentation], F_OK) != 0) {
                errno = errno_old;
                restricted = NO;
            }
        }
    }

    if(!restricted && (![options objectForKey:kShadowRestrictionEnableResolve] || [[options objectForKey:kShadowRestrictionEnableResolve] boolValue])) {
        NSString* resolved_path = [path stringByStandardizingPath];
        if(![resolved_path isEqualToString:path]) {
            NSMutableDictionary* opt = [NSMutableDictionary dictionaryWithDictionary:options];
            [opt setObject:@(NO) forKey:kShadowRestrictionEnableResolve];
            restricted = [self isPathRestricted:resolved_path options:[opt copy]];
        }
    }

    if(!options) {
        [pathCache setObject:@(restricted) forKey:path];
    }

    return restricted;
}

- (BOOL)isURLRestricted:(NSURL *)url {
    return [self isURLRestricted:url options:nil];
}

- (BOOL)isURLRestricted:(NSURL *)url options:(NSDictionary<NSString *, id> *)options {
    if(!url) return NO;
    if([url isFileURL]) {
        NSString *path = [url path];
        if([url isFileReferenceURL]) {
            NSURL *surl = [url filePathURL];
            if(surl) path = [surl path];
        }
        return [self isPathRestricted:path options:options];
    }
    return [self isSchemeRestricted:[url scheme]];
}

- (BOOL)isSchemeRestricted:(NSString *)scheme {
    return [backend isSchemeRestricted:scheme];
}
@end