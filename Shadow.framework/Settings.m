#import <Shadow/Settings.h>
#import <RootBridge.h>
#import "../common.h"

@implementation ShadowSettings {
    NSDictionary* _effectivePList; // Direct file fallback
}

@synthesize defaultSettings, userDefaults;

- (instancetype)init {
    if((self = [super init])) {
        // 1. Define Master Defaults
        defaultSettings = @{
            @"Global_Enabled" : @(NO),
            @"HK_Library" : @"fishhook",
            @"Hook_Filesystem" : @(YES),
            @"Hook_DynamicLibraries" : @(YES),
            @"Hook_URLScheme" : @(YES),
            @"Hook_EnvVars" : @(YES),
            @"Hook_Foundation" : @(NO),
            @"Hook_DeviceCheck" : @(YES),
            @"Hook_MachBootstrap" : @(NO),
            @"Hook_SymLookup" : @(NO),
            @"Hook_LowLevelC" : @(NO),
            @"Hook_AntiDebugging" : @(NO),
            @"Hook_DynamicLibrariesExtra" : @(NO),
            @"Hook_ObjCRuntime" : @(NO),
            @"Hook_FakeMac" : @(NO),
            @"Hook_Syscall" : @(NO),
            @"Hook_Sandbox" : @(NO),
            @"Hook_Memory" : @(NO),
            @"Hook_TweakClasses" : @(NO),
            @"Hook_HideApps" : @(NO)
        };

        // 2. Resolve Preference Path for Rootless
        NSString* prefPath = [RootBridge rootPath:@SHADOW_PREFS_PLIST];
        
        // 3. Initialize Suite. Note: SuiteName should be the domain, 
        // but we keep the suite logic and add a Direct Read fallback.
        userDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.jjolano.shadow"];
        [userDefaults registerDefaults:defaultSettings];

        // 4. Hardened Fallback: Load Plist directly if NSUserDefaults is restricted
        if (prefPath && [[NSFileManager defaultManager] isReadableFileAtPath:prefPath]) {
            _effectivePList = [NSDictionary dictionaryWithContentsOfFile:prefPath];
        }
    }
    return self;
}

+ (instancetype)sharedInstance {
    static ShadowSettings* sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [self new];
    });
    return sharedInstance;
}

- (NSDictionary<NSString *, id> *)getPreferencesForIdentifier:(NSString *)bundleIdentifier {
    NSMutableDictionary* result = [defaultSettings mutableCopy];
    
    // Attempt to get settings from Suite, then Fallback Plist
    NSDictionary* globalSettings = [userDefaults dictionaryRepresentation];
    if (![globalSettings objectForKey:@"Global_Enabled"] && _effectivePList) {
        globalSettings = _effectivePList;
    }

    NSDictionary* appSettings = bundleIdentifier ? [globalSettings objectForKey:bundleIdentifier] : nil;

    // Check if App-Specific settings should be used
    if([[appSettings objectForKey:@"App_Enabled"] boolValue]) {
        [result addEntriesFromDictionary:appSettings];
    } 
    // Otherwise, check if Global settings are enabled
    else if([[globalSettings objectForKey:@"Global_Enabled"] boolValue]) {
        [result addEntriesFromDictionary:globalSettings];
        // Ensure "App_Enabled" key exists for the engine's check
        [result setObject:@(YES) forKey:@"App_Enabled"];
    }

    return [result copy];
}
@end