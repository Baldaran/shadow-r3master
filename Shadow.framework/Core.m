#import <Shadow/Core.h>
#import <Shadow/Core+Utilities.h>
#import <Shadow/Backend.h>
#import <RootBridge.h>
#import <dlfcn.h>
#import <pwd.h>
#import <mach-o/dyld.h>
#import <substrate.h>
#import <sys/types.h>
#import "../vendor/apple/dyld_priv.h"

// --- STEALTH ENGINE GLOBALS ---
#define PT_DENY_ATTACH 31
typedef int (*ptrace_ptr_t)(int request, pid_t pid, caddr_t addr, int data);
static ptrace_ptr_t orig_ptrace = NULL;

static uint32_t (*orig_dyld_image_count)(void);
static const char* (*orig_dyld_get_image_name)(uint32_t image_index);
static const struct mach_header* (*orig_dyld_get_image_header)(uint32_t image_index);

static uint32_t masked_indices[16]; 
static uint32_t masked_count = 0;

// Anti-Debugging Hook
int hooked_ptrace(int request, pid_t pid, caddr_t addr, int data) {
    return (request == PT_DENY_ATTACH) ? 0 : orig_ptrace(request, pid, addr, data);
}

// Image Masking Logic
uint32_t hooked_dyld_image_count(void) {
    uint32_t real_count = orig_dyld_image_count();
    return (real_count > masked_count) ? (real_count - masked_count) : real_count;
}

static uint32_t translate_index(uint32_t virtual_index) {
    uint32_t actual_index = virtual_index;
    for (uint32_t i = 0; i < masked_count; i++) {
        if (actual_index >= masked_indices[i]) actual_index++;
    }
    return actual_index;
}

const char* hooked_dyld_get_image_name(uint32_t image_index) {
    return orig_dyld_get_image_name(translate_index(image_index));
}

const struct mach_header* hooked_dyld_get_image_header(uint32_t image_index) {
    return orig_dyld_get_image_header(translate_index(image_index));
}



@implementation Shadow {
    NSCache* pathCache;
}

@synthesize bundlePath, homePath, realHomePath, hasAppSandbox, rootless;

- (instancetype)init {
    if((self = [super init])) {
        // 1. Path Setup
        bundlePath = [[self class] getStandardizedPath:[[[self class] getExecutablePath] stringByDeletingLastPathComponent]];
        homePath = [[self class] getStandardizedPath:NSHomeDirectory()];
        struct passwd *pw = getpwuid(getuid());
        realHomePath = [[self class] getStandardizedPath:(pw ? @(pw->pw_dir) : homePath)];
        hasAppSandbox = [[bundlePath pathExtension] isEqualToString:@"app"];
        
        // 2. Detection Engine Setup
        rootless = ([RootBridge isJBRootless] || [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"]);
        pathCache = [NSCache new];
        [pathCache setCountLimit:1500];
        backend = [ShadowBackend new];

        // 3. Setup dyld hooks (Support multiple JB libs)
        uint32_t count = _dyld_image_count();
        masked_count = 0;
        for (uint32_t i = 0; i < count && masked_count < 16; i++) {
            const char* name = _dyld_get_image_name(i);
            if (name && (strstr(name, "Shadow.dylib") || strstr(name, "RootBridge") || strstr(name, "libsubstrate"))) {
                masked_indices[masked_count++] = i;
            }
        }

        if (masked_count > 0) {
            MSHookFunction((void *)_dyld_image_count, (void *)hooked_dyld_image_count, (void **)&orig_dyld_image_count);
            MSHookFunction((void *)_dyld_get_image_name, (void *)hooked_dyld_get_image_name, (void **)&orig_dyld_get_image_name);
            MSHookFunction((void *)_dyld_get_image_header, (void *)hooked_dyld_get_image_header, (void **)&orig_dyld_get_image_header);
        }

        // 4. Setup ptrace hook
        void* p_addr = dlsym(RTLD_DEFAULT, "ptrace");
        if (p_addr) MSHookFunction(p_addr, (void *)hooked_ptrace, (void **)&orig_ptrace);
    }
    return self;
}

+ (instancetype)sharedInstance {
    static Shadow* sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ sharedInstance = [self new]; });
    return sharedInstance;
}

// Core Restriction Logic
- (BOOL)isPathRestricted:(NSString *)path options:(NSDictionary *)options {
    if(!path || [path length] == 0 || [path isEqualToString:@"/"]) return NO;

    if(!options) {
        @synchronized(pathCache) {
            NSNumber* cached = [pathCache objectForKey:path];
            if(cached) return [cached boolValue];
        }
    }

    NSString *standardizedPath = [[self class] getStandardizedPath:[path stringByExpandingTildeInPath]];
    if([standardizedPath length] > 0 && [standardizedPath characterAtIndex:0] == '~') return NO;

    BOOL restricted = NO;
    BOOL shouldCheck = (!hasAppSandbox || (![standardizedPath hasPrefix:bundlePath] && ![standardizedPath hasPrefix:homePath]));

    if(shouldCheck) {
        // Combined iOS 16 Rootless and Backend Logic
        if(rootless && ([standardizedPath hasPrefix:@"/var/jb"] || [standardizedPath hasPrefix:@"/private/preboot/"])) {
            restricted = YES;
        } else {
            restricted = [backend isPathRestricted:standardizedPath];
        }

        // Additional /usr/lib safety check
        if(!restricted && [standardizedPath hasPrefix:@"/usr/lib"]) {
            restricted = (access([standardizedPath fileSystemRepresentation], F_OK) != 0);
        }
    }

    // Resolve Symlinks if needed
    if(!restricted && (!options[kShadowRestrictionEnableResolve] || [options[kShadowRestrictionEnableResolve] boolValue])) {
        NSString* resolved = [standardizedPath stringByStandardizingPath];
        if(![resolved isEqualToString:standardizedPath]) {
            NSMutableDictionary* opt = [options mutableCopy] ?: [NSMutableDictionary new];
            opt[kShadowRestrictionEnableResolve] = @(NO);
            restricted = [self isPathRestricted:resolved options:[opt copy]];
        }
    }

    if(!options) {
        @synchronized(pathCache) { [pathCache setObject:@(restricted) forKey:path]; }
    }
    return restricted;
}

// Utility Wrappers
- (BOOL)isAddrExternal:(const void *)addr {
    const char* img = dyld_image_path_containing_address(addr);
    return (img && strstr(img, [bundlePath fileSystemRepresentation]) == NULL);
}

- (BOOL)isAddrRestricted:(const void *)addr {
    const char* img = dyld_image_path_containing_address(addr);
    return img ? [self isPathRestricted:@(img)] : NO;
}

- (BOOL)isCPathRestricted:(const char *)path {
    return path ? [self isPathRestricted:@(path)] : NO;
}

- (BOOL)isPathRestricted:(NSString *)path {
    return [self isPathRestricted:path options:nil];
}

- (BOOL)isURLRestricted:(NSURL *)url {
    return [self isURLRestricted:url options:nil];
}

- (BOOL)isURLRestricted:(NSURL *)url options:(NSDictionary *)options {
    if(!url) return NO;
    if([url isFileURL]) {
        NSString *p = [url path];
        if([url isFileReferenceURL]) p = [[url filePathURL] path];
        return [self isPathRestricted:p options:options];
    }
    return [backend isSchemeRestricted:[url scheme]];
}

- (BOOL)isSchemeRestricted:(NSString *)scheme {
    return [backend isSchemeRestricted:scheme];
}
@end