#import <Shadow/Core+Utilities.h>
#import <Shadow/Ruleset.h>
#import <RootBridge.h>
#import "../vendor/apple/dyld_priv.h"
#import "../common.h"

extern char*** _NSGetArgv();

@implementation Shadow (Utilities)

+ (NSString *)getStandardizedPath:(NSString *)path {
    if(!path || [path length] == 0) {
        return path;
    }

    // Standardize using URL logic to resolve basic separators
    NSURL* url = [NSURL fileURLWithPath:path];
    NSString* standardized_path = [url path];

    if(standardized_path) {
        path = standardized_path;
    }

    // Clean up redundant separators
    while([path containsString:@"/./"]) {
        path = [path stringByReplacingOccurrencesOfString:@"/./" withString:@"/"];
    }

    while([path containsString:@"//"]) {
        path = [path stringByReplacingOccurrencesOfString:@"//" withString:@"/"];
    }

    if([path length] > 1) {
        if([path hasSuffix:@"/"]) {
            path = [path substringToIndex:[path length] - 1];
        }

        while([path hasSuffix:@"/."]) {
            path = [path stringByDeletingLastPathComponent];
        }
    }

    // Rootless/iOS 16 Fix: Standardize /private/ prefixes
    if([path hasPrefix:@"/private/var"] || [path hasPrefix:@"/private/etc"]) {
        NSMutableArray* pathComponents = [[path pathComponents] mutableCopy];
        [pathComponents removeObjectAtIndex:1]; // Remove 'private'
        path = [NSString pathWithComponents:pathComponents];
    }

    return path;
}

+ (NSString *)getExecutablePath {
    char* executablePathC = **_NSGetArgv();
    return executablePathC ? @(executablePathC) : nil;
}

+ (NSString *)getBundleIdentifier {
    CFBundleRef mainBundle = CFBundleGetMainBundle();
    return mainBundle ? (__bridge NSString *)CFBundleGetIdentifier(mainBundle) : nil;
}

+ (NSDictionary *)generateDatabase {
    // Determine dpkg info database path for iOS 16 Rootless
    NSArray* dpkgInfoPaths = @[
        @"/var/jb/var/lib/dpkg/info",
        @"/Library/dpkg/info",
        @"/var/lib/dpkg/info"
    ];

    NSString* dpkgInfoPath = nil;
    for(NSString* path in dpkgInfoPaths) {
        if([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            dpkgInfoPath = path;
            break;
        }
    }

    if(!dpkgInfoPath) {
        return nil;
    }

    NSMutableSet* db_installed = [NSMutableSet new];
    NSMutableSet* db_exception = [NSMutableSet new];
    NSMutableSet* schemes = [NSMutableSet new];

    NSArray* db_files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL fileURLWithPath:dpkgInfoPath isDirectory:YES] includingPropertiesForKeys:@[] options:0 error:nil];

    for(NSURL* db_file in db_files) {
        if([[db_file pathExtension] isEqualToString:@"list"]) {
            NSString* content = [NSString stringWithContentsOfURL:db_file encoding:NSUTF8StringEncoding error:nil];
            if(content) {
                NSArray* lines = [content componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
                for(NSString* line in lines) {
                    NSString* path = [self getStandardizedPath:line];
                    if(!path || [path length] == 0 || [path isEqualToString:@"/"]) continue;

                    // Handle App URLs for scheme hiding
                    if([[path pathExtension] isEqualToString:@"app"]) {
                        NSBundle* appBundle = [NSBundle bundleWithPath:[RootBridge getJBPath:path]];
                        if(appBundle) {
                            NSDictionary* urltypes = [[appBundle infoDictionary] objectForKey:@"CFBundleURLTypes"];
                            if(urltypes) {
                                for(NSDictionary* type in urltypes) {
                                    NSArray* urlschemes = [type objectForKey:@"CFBundleURLSchemes"];
                                    if(urlschemes) [schemes addObjectsFromArray:urlschemes];
                                }
                            }
                        }
                    }
                    [db_installed addObject:path];
                }
            }
        }
    }

    // Critical system exclusion list
    NSArray* filter_names = @[
        @"/.",
        @"/Library/Application Support",
        @"/usr/lib",
        @"/var/mobile/Library/Caches",
        @"/System/Library/PrivateFrameworks/CoreEmoji.framework",
        @"/System/Library/PrivateFrameworks/TextInput.framework"
    ];

    [db_exception addObjectsFromArray:filter_names];
    [db_installed minusSet:db_exception];

    return @{
        @"RulesetInfo" : @{
            @"Name" : @"dpkg installed files (Rootless Optimized)",
            @"Author" : @"Shadow Service"
        },
        @"BlacklistExactPaths" : [db_installed allObjects],
        @"BlacklistURLSchemes" : [schemes allObjects]
    };
}

+ (NSArray *)filterPathArray:(NSArray *)array restricted:(BOOL)restricted options:(NSDictionary<NSString *, id> *)options {
    Shadow* shadow = [Shadow sharedInstance];
    __block BOOL _restricted = restricted;

    NSIndexSet* indexes = [array indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL* stop) {
        if([obj isKindOfClass:[NSString class]]) {
            return [shadow isPathRestricted:obj options:options] == _restricted;
        }
        if([obj isKindOfClass:[NSURL class]]) {
            return [shadow isURLRestricted:obj options:options] == _restricted;
        }
        return NO;
    }];

    return [array objectsAtIndexes:indexes];
}
@end