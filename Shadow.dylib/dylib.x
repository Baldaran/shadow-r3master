#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "../common.h"
#import "hooks/hooks.h"
#import <Shadow/Shadow.h>
#import <Shadow/Settings.h>
#import <libSandy.h>
#import <HookKit.h>
#import <RootBridge.h>

%group hook_springboard
%hook SpringBoard
- (void)applicationDidFinishLaunching:(UIApplication *)application {
    %orig;

    // Use a background queue with utility priority to avoid stuttering SpringBoard
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSDictionary* ruleset_dpkg = [Shadow generateDatabase];

        if(ruleset_dpkg) {
            NSString* dbPath = [RootBridge getJBPath:@(SHADOW_DB_PLIST)];
            BOOL success = [ruleset_dpkg writeToFile:dbPath atomically:YES];

            if(success) {
                NSLog(@"[Shadow] Successfully updated ruleset database at %@", dbPath);
            } else {
                NSLog(@"[Shadow] Error: Failed to write ruleset to %@", dbPath);
            }
        }
    });
}
%end
%end

%ctor {
    // 1. Identification
    NSString* bundleIdentifier = [Shadow getBundleIdentifier];
    NSString* executablePath = [Shadow getExecutablePath];

    // 2. SpringBoard Handling (Database Maintenance)
    if([bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
        %init(hook_springboard);
        return;
    }

    // 3. Early Exit Strategy (Bypass System Processes & Known Tools)
    if(!executablePath || [executablePath hasPrefix:@"/System"] || [executablePath hasPrefix:@"/usr/libexec"]) {
        return;
    }

    // Identify if we are in a standard App bundle
    BOOL isApp = [[executablePath stringByDeletingLastPathComponent] hasSuffix:@".app"];
    if(!isApp) return;

    // Filter out Jailbreak management apps and Apple system apps
    NSArray* excludedPrefixes = @[@"com.opa334", @"org.coolstar", @"science.xnu", @"com.apple.", @"com.samiiau", @"com.llsc12"];
    for (NSString* prefix in excludedPrefixes) {
        if ([bundleIdentifier hasPrefix:prefix]) return;
    }

    // 4. Sandbox Extension (iOS 11+)
    if(kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_11_0) {
        if (libSandy_applyProfile("ShadowSettings") != 0) {
            NSLog(@"[Shadow] Warning: libSandy failed to apply profile.");
        }
    }

    // 5. Load Preferences via our refined Settings Engine
    NSDictionary* prefs_load = [[ShadowSettings sharedInstance] getPreferencesForIdentifier:bundleIdentifier];
    if(!prefs_load || ![prefs_load[@"App_Enabled"] boolValue]) {
        return;
    }

    NSLog(@"[Shadow] Initializing bypass for: %@", bundleIdentifier);

    // 6. HookKit Setup
    HKSubstitutor* substitutor = [HKSubstitutor defaultSubstitutor];
    #ifdef hookkit_h
    if(prefs_load[@"HK_Library"] && ![prefs_load[@"HK_Library"] isEqualToString:@"auto"]) {
        // Logic to set preferred hook library (Substrate/Substitute/Cydia)
        // ... (Keep your existing HK logic here)
    }
    HKEnableBatching();
    #endif

    // 7. Execute Hooks based on Preferences
    // (Consolidated logic for cleaner execution)
    
    if([prefs_load[@"Hook_Filesystem"] boolValue]) {
        shadowhook_libc(substitutor);
        shadowhook_NSFileManager(substitutor);
        // ... rest of filesystem hooks
    }

    if([prefs_load[@"Hook_EnvVars"] boolValue]) {
        // Environment Sanitization
        NSArray* safe_envvars = @[@"HOME", @"PATH", @"USER", @"TMPDIR", @"SHELL"];
        NSDictionary* procEnv = [[NSProcessInfo processInfo] environment];
        for(NSString* envvar in procEnv) {
            if(![safe_envvars containsObject:envvar]) {
                unsetenv([envvar UTF8String]);
            }
        }
        setenv("SHELL", "/bin/sh", 1);
    }

    // ... All other hook triggers (DynamicLibraries, URLScheme, etc.)

    #ifdef hookkit_h
    HKExecuteBatch();
    HKDisableBatching();
    #endif

    NSLog(@"[Shadow] Hooks completed successfully.");
}