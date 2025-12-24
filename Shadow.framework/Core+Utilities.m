#import <Shadow/Core+Utilities.h>
#import <Shadow/Ruleset.h>
#import <RootBridge.h>
#import "../vendor/apple/dyld_priv.h"
#import "../common.h"

extern char*** _NSGetArgv();

@implementation Shadow (Utilities)

+ (NSString *)getStandardizedPath:(NSString *)path {
    if(!path || [path length] == 0) return path;

    // 1. Resolve basic structure via URL
    // Use fileURLWithPath:isDirectory: to avoid a disk-hit check
    NSURL* url = [NSURL fileURLWithPath:path isDirectory:NO];
    NSString* standardized = [url path];
    if(!standardized) standardized = path;

    // 2. High-Performance Separator Cleaning
    // Instead of loops, we use stringByStandardizingPath which handles "/./" and "//" natively in C
    standardized = [standardized stringByStandardizingPath];

    // 3. iOS 16 /private/ Handling (Safe Implementation)
    if([standardized hasPrefix:@"/private/var"] || [standardized hasPrefix:@"/private/etc"]) {
        NSArray* components = [standardized pathComponents];
        if([components count] > 2 && [components[1] isEqualToString:@"private"]) {
            NSMutableArray* mutableComponents = [components mutableCopy];
            [mutableComponents removeObjectAtIndex:1];
            standardized = [NSString pathWithComponents:mutableComponents];
        }
    }

    // 4. Trailing Slash Removal
    if([standardized length] > 1 && [standardized hasSuffix:@"/"]) {
        standardized = [standardized substringToIndex:[standardized length] - 1];
    }

    return standardized;
}

+ (NSString *)getExecutablePath {
    char*** argv = _NSGetArgv();
    if (argv && *argv && **argv) {
        return @(**argv);
    }
    return nil;
}

+ (NSString *)getBundleIdentifier {
    return [[NSBundle mainBundle] bundleIdentifier];
}

+ (NSDictionary *)generateDatabase {
    // Rootless-aware dpkg info search
    NSArray* dpkgInfoPaths = @[
        @"/var/jb/var/lib/dpkg/info",
        @"/Library/dpkg/info",
        @"/var/lib/dpkg/info",
        @"/var/jb/Library/dpkg/info" // Added for certain rootless environments
    ];

    NSString* dpkgInfoPath = nil;
    NSFileManager* fm = [NSFileManager defaultManager];
    
    for(NSString* path in dpkgInfoPaths) {
        if([fm fileExistsAtPath:path]) {
            dpkgInfoPath = path;
            break;
        }
    }

    if(!dpkgInfoPath) return nil;

    NSMutableSet* db_installed = [NSMutableSet new];
    NSMutableSet* schemes = [NSMutableSet new];

    NSArray* db_files = [fm contentsOfDirectoryAtURL:[NSURL fileURLWithPath:dpkgInfoPath isDirectory:YES] 
                         includingPropertiesForKeys:nil 
                         options:NSDirectoryEnumerationSkipsHiddenFiles 
                         error:nil];

    for(NSURL* db_file in db_files) {
        if([[db_file pathExtension] isEqualToString:@"list"]) {
            // Memory efficient reading
            NSError* err = nil;
            NSString* content = [NSString stringWithContentsOfURL:db_file encoding:NSUTF8StringEncoding error:&err];
            if(!content || err) continue;

            [content enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
                NSString* standardizedLine = [self getStandardizedPath:line];
                if(standardizedLine && [standardizedLine length] > 1 && ![standardizedLine isEqualToString:@"/"]) {
                    
                    // Scheme Hiding Logic
                    if([standardizedLine hasSuffix:@".app"]) {
                        NSString* jbAppPath = [RootBridge getJBPath:standardizedLine];
                        NSBundle* appBundle = [NSBundle bundleWithPath:jbAppPath];
                        NSDictionary* info = [appBundle infoDictionary];
                        for(NSDictionary* type in info[@"CFBundleURLTypes"]) {
                            for(NSString* scheme in type[@"CFBundleURLSchemes"]) {
                                [schemes addObject:scheme];
                            }
                        }
                    }
                    [db_installed addObject:standardizedLine];
                }
            }];
        }
    }

    // Critical system exclusion list (Do not hide these or system apps will crash)
    NSArray* system_exceptions = @[
        @"/",
        @"/Library/Application Support",
        @"/usr/lib",
        @"/var/mobile/Library/Caches",
        @"/System/Library/PrivateFrameworks"
    ];

    [db_installed minusSet:[NSSet setWithArray:system_exceptions]];

    return @{
        @"RulesetInfo" : @{
            @"Name" : @"dpkg installed files (Shadow Refined)",
            @"Author" : @"Shadow Service"
        },
        @"BlacklistExactPaths" : [db_installed allObjects],
        @"BlacklistURLSchemes" : [schemes allObjects]
    };
}

+ (NSArray *)filterPathArray:(NSArray *)array restricted:(BOOL)restricted options:(NSDictionary *)options {
    Shadow* shadow = [Shadow sharedInstance];
    NSPredicate* predicate = [NSPredicate predicateWithBlock:^BOOL(id obj, NSDictionary* bindings) {
        if([obj isKindOfClass:[NSString class]]) {
            return [shadow isPathRestricted:obj options:options] == restricted;
        }
        if([obj isKindOfClass:[NSURL class]]) {
            return [shadow isURLRestricted:obj options:options] == restricted;
        }
        return NO;
    }];

    return [array filteredArrayUsingPredicate:predicate];
}

@end