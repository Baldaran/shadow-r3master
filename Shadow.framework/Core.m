#import <Shadow/Core.h>
#import <Shadow/Core+Utilities.h>
#import <Shadow/Backend.h>
#import <RootBridge.h>
#import <dlfcn.h>
#import <pwd.h>
#import "../vendor/apple/dyld_priv.h"

@implementation Shadow {
    // Advanced Memory Cache for high-speed lookups
    NSCache* pathCache;
}

@synthesize bundlePath, homePath, realHomePath, hasAppSandbox, rootless;

- (instancetype)init {
    if((self = [super init])) {
        bundlePath = [[[self class] getExecutablePath] stringByDeletingLastPathComponent];
        homePath = NSHomeDirectory();
        realHomePath = @(getpwuid(getuid())->pw_dir);

        bundlePath = [[self class] getStandardizedPath:bundlePath];
        homePath = [[self class] getStandardizedPath:homePath];
        realHomePath = [[self class] getStandardizedPath:realHomePath];

        hasAppSandbox = [[bundlePath pathExtension] isEqualToString:@"app"];
        
        // Rootless Detection
        rootless = [RootBridge isJBRootless];
        if(!rootless) {
            rootless = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"];
        }

        // Initialize Performance Cache
        pathCache = [NSCache new];
        [pathCache setCountLimit:1500]; // Optimal balance for iOS 16 RAM management

        backend = [ShadowBackend new];
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

    // Performance Shortcut: Check Memory Cache first
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

        // Special handling for dynamic library paths
        if(!restricted && [path hasPrefix:@"/usr/lib"]) {
            int errno_old = errno;
            if(access([path fileSystemRepresentation], F_OK) != 0) {
                errno = errno_old;
                restricted = NO;
            }
        }
    }

    // Recursive Resolve
    if(!restricted && (![options objectForKey:kShadowRestrictionEnableResolve] || [[options objectForKey:kShadowRestrictionEnableResolve] boolValue])) {
        NSString* resolved_path = [path stringByStandardizingPath];
        if(![resolved_path isEqualToString:path]) {
            NSMutableDictionary* opt = [NSMutableDictionary dictionaryWithDictionary:options];
            [opt setObject:@(NO) forKey:kShadowRestrictionEnableResolve];
            restricted = [self isPathRestricted:resolved_path options:[opt copy]];
        }
    }

    // Save result to Cache for next time
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