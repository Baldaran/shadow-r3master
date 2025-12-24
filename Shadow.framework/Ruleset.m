#import <Shadow/Ruleset.h>

@implementation ShadowRuleset {
    // Background sets for fast O(1) lookups
    NSSet* set_urlschemes;
    NSSet* set_whitelist;
    NSSet* set_blacklist;

    // Compound predicates for complex rules
    NSCompoundPredicate* pred_whitelist;
    NSCompoundPredicate* pred_blacklist;
    
    // Arrays for prefix matching
    NSArray* array_whitelist;
    NSArray* array_blacklist;
}

@synthesize internalDictionary;

- (instancetype)init {
    if((self = [super init])) {
        // Initializing with empty sets prevents nil-pointer checks later
        set_urlschemes = [NSSet new];
        set_whitelist = [NSSet new];
        set_blacklist = [NSSet new];
    }
    return self;
}

+ (instancetype)rulesetWithURL:(NSURL *)url {
    NSDictionary* ruleset_dict = [NSDictionary dictionaryWithContentsOfURL:url];
    if(ruleset_dict) {
        ShadowRuleset* ruleset = [self new];
        [ruleset setInternalDictionary:ruleset_dict];
        [ruleset _compile];
        return ruleset;
    }
    return nil;
}

+ (instancetype)rulesetWithPath:(NSString *)path {
    return [self rulesetWithURL:[NSURL fileURLWithPath:path isDirectory:NO]];
}

- (void)_compile {
    // We use a high-priority queue but wait for essential sets to finish 
    // to ensure the bypass is active before the first path check.
    NSOperationQueue* queue = [NSOperationQueue new];
    [queue setQualityOfService:NSOperationQualityOfServiceUserInteractive];

    // 1. URL Schemes
    NSArray* schemes = internalDictionary[@"BlacklistURLSchemes"];
    if(schemes) {
        [queue addOperationWithBlock:^{
            self->set_urlschemes = [NSSet setWithArray:schemes];
        }];
    }

    // 2. Exact Path Sets
    NSArray* wl_exact = internalDictionary[@"WhitelistExactPaths"];
    if(wl_exact) {
        [queue addOperationWithBlock:^{
            self->set_whitelist = [NSSet setWithArray:wl_exact];
        }];
    }

    NSArray* bl_exact = internalDictionary[@"BlacklistExactPaths"];
    if(bl_exact) {
        [queue addOperationWithBlock:^{
            self->set_blacklist = [NSSet setWithArray:bl_exact];
        }];
    }

    // 3. Prefix Arrays (Pre-cached for performance)
    array_whitelist = internalDictionary[@"WhitelistPaths"];
    array_blacklist = internalDictionary[@"BlacklistPaths"];

    // 4. Predicate Compilation (The heaviest task)
    NSArray* wl_preds = internalDictionary[@"WhitelistPredicates"];
    if(wl_preds) {
        [queue addOperationWithBlock:^{
            NSMutableArray* preds = [NSMutableArray new];
            for(NSString* ps in wl_preds) [preds addObject:[NSPredicate predicateWithFormat:ps]];
            self->pred_whitelist = [NSCompoundPredicate orPredicateWithSubpredicates:preds];
        }];
    }

    NSArray* bl_preds = internalDictionary[@"BlacklistPredicates"];
    if(bl_preds) {
        [queue addOperationWithBlock:^{
            NSMutableArray* preds = [NSMutableArray new];
            for(NSString* ps in bl_preds) [preds addObject:[NSPredicate predicateWithFormat:ps]];
            self->pred_blacklist = [NSCompoundPredicate orPredicateWithSubpredicates:preds];
        }];
    }

    [queue waitUntilAllOperationsAreFinished];
}

- (BOOL)isPathCompliant:(NSString *)path {
    NSDictionary* structure = internalDictionary[@"FileSystemStructure"];
    if(!structure || structure[path]) return YES;

    NSString* path_tmp = path;
    NSArray* structure_base = nil;

    // Walk up the tree to find the nearest enforcement point
    do {
        path_tmp = [path_tmp stringByDeletingLastPathComponent];
        structure_base = structure[path_tmp];
    } while(!structure_base && ![path_tmp isEqualToString:@"/"]);

    if(structure_base) {
        for(NSString* name in structure_base) {
            if([path hasPrefix:[path_tmp stringByAppendingPathComponent:name]]) return YES;
        }
        return NO;
    }
    return YES;
}

- (BOOL)isPathWhitelisted:(NSString *)path {
    // 1. Check Exact Set (Fastest)
    if([set_whitelist containsObject:path]) return YES;

    // 2. Check Prefix Array
    for(NSString* wl_path in array_whitelist) {
        if([path hasPrefix:wl_path]) return YES;
    }

    // 3. Check Predicates (Slowest)
    return [pred_whitelist evaluateWithObject:path];
}

- (BOOL)isPathBlacklisted:(NSString *)path {
    // 1. Check Exact Set (Fastest)
    if([set_blacklist containsObject:path]) return YES;

    // 2. Check Prefix Array
    for(NSString* bl_path in array_blacklist) {
        if([path hasPrefix:bl_path]) return YES;
    }

    // 3. Check Predicates (Slowest)
    return [pred_blacklist evaluateWithObject:path];
}

- (BOOL)isSchemeRestricted:(NSString *)scheme {
    if(!scheme) return NO;
    return [set_urlschemes containsObject:scheme];
}

@end