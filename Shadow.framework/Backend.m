#import <Shadow/Core+Utilities.h>
#import <Shadow/Backend.h>
#import <Shadow/Ruleset.h>
#import <Shadow/Shadow.h>
#import <RootBridge.h>

#import "../common.h"
#import "../../hooks/hooks.h" // To access isCallerTweak()

// --- High-Speed C-Bridge Implementation ---
// This is what the libc hooks call to avoid Objective-C overhead
BOOL isCPathRestricted(const char* pathname) {
    if (!pathname || isCallerTweak()) return NO;
    
    // Efficiently convert C-string to NSString using file system representation
    NSString* path = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:pathname length:strlen(pathname)];
    
    // Call the shared backend instance
    return [[Shadow sharedInstance] isPathRestricted:path];
}

@implementation ShadowBackend {
    NSCache* cache_restricted;
    NSArray<ShadowRuleset *>* rulesets;
}

- (instancetype)init {
    if((self = [super init])) {
        cache_restricted = [NSCache new];
        // Set a cost limit to prevent memory bloat in large apps
        [cache_restricted setCountLimit:2000]; 
        rulesets = [[self class] _loadRulesets];
    }
    return self;
}

+ (NSArray<ShadowRuleset *> *)_loadRulesets {
    NSMutableArray<ShadowRuleset *>* result = [NSMutableArray new];
    
    // Rootless-aware pathing via RootBridge
    NSString* ruleset_path = [RootBridge getJBPath:@SHADOW_RULESETS];
    NSURL* ruleset_path_url = [NSURL fileURLWithPath:ruleset_path isDirectory:YES];
    
    NSArray* ruleset_urls = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:ruleset_path_url 
                                                         includingPropertiesForKeys:@[] 
                                                                            options:0 
                                                                              error:nil];
    if(ruleset_urls) {
        for(NSURL* url in ruleset_urls) {
            ShadowRuleset* ruleset = [ShadowRuleset rulesetWithURL:url];
            if(ruleset) {
                [result addObject:ruleset];
            }
        }
    }
    return [result copy];
}

- (BOOL)isPathRestricted:(NSString *)path {
    // 1. Basic Sanity Checks
    if(!path || [path length] == 0 || [path isEqualToString:@"/"] || ![path isAbsolutePath]) {
        return NO;
    }

    // 2. Cache Lookup (Crucial for performance)
    NSNumber* cached = [cache_restricted objectForKey:path];
    if(cached) {
        return [cached boolValue];
    }

    __block BOOL compliant = YES;
    __block BOOL blacklisted = NO;
    __block BOOL whitelisted = NO;

    // 3. Evaluate all loaded rulesets concurrently
    [rulesets enumerateObjectsWithOptions:NSEnumerationConcurrent usingBlock:^(ShadowRuleset* ruleset, NSUInteger idx, BOOL* stop) {
        if(![ruleset isPathCompliant:path]) {
            compliant = NO;
            *stop = YES;
        } else {
            if([ruleset isPathWhitelisted:path]) {
                whitelisted = YES;
                *stop = YES;
            } else if([ruleset isPathBlacklisted:path]) {
                blacklisted = YES;
            }
        }
    }];

    BOOL restricted = !compliant || (blacklisted && !whitelisted);

    // 4. Recursive Parent Check
    // If this folder isn't restricted, we must check if its parent is.
    // Example: if /var/jb/bin is restricted, /var/jb/bin/ls must also be restricted.
    if(!restricted) {
        NSString* parentPath = [path stringByDeletingLastPathComponent];
        if(![parentPath isEqualToString:@"/"]) {
            restricted = [self isPathRestricted:parentPath];
        }
    }

    // 5. Update Cache and Return
    [cache_restricted setObject:@(restricted) forKey:path];
    return restricted;
}

- (BOOL)isSchemeRestricted:(NSString *)scheme {
    if(!scheme || [scheme length] == 0) return NO;

    // Common non-jailbreak schemes to skip immediately
    static dispatch_once_t onceToken;
    static NSSet* exceptions;
    dispatch_once(&onceToken, ^{
        exceptions = [NSSet setWithObjects:@"file", @"http", @"https", @"maps", @"itms", nil];
    });

    if([exceptions containsObject:scheme]) return NO;

    __block BOOL restricted = NO;
    [rulesets enumerateObjectsWithOptions:NSEnumerationConcurrent usingBlock:^(ShadowRuleset* ruleset, NSUInteger idx, BOOL* stop) {
        if([ruleset isSchemeRestricted:scheme]) {
            restricted = YES;
            *stop = YES;
        }
    }];

    return restricted;
}
@end