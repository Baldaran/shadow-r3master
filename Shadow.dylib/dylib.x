#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "../common.h"
#import "hooks/hooks.h"
#import <Shadow/Shadow.h>
#import <Shadow/Settings.h>
#import <libSandy.h>
#import <HookKit.h>
#import <RootBridge.h>

// Global instance for hooks to use
Shadow* _shadow = nil;

%group hook_springboard
%hook SpringBoard
- (void)applicationDidFinishLaunching:(UIApplication *)application {
    %orig;

    // Background database refresh (Maintenance)
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_UTILITY, 0), ^{
        NSDictionary* ruleset_dpkg = [Shadow generateDatabase];
        if(ruleset_dpkg) {
            NSString* dbPath = [RootBridge getJBPath:@(SHADOW_DB_PLIST)];
            [ruleset_dpkg writeToFile:dbPath atomically:YES];
            NSLog(@"[Shadow] Global ruleset database updated.");
        }
    });
}
%end
%end

%ctor {
    // 1. Setup Identity
    NSString* bundleIdentifier = [Shadow getBundleIdentifier];
    NSString* executablePath = [Shadow getExecutablePath];

    // 2. SpringBoard Maintenance Mode
    if([bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
        %init(hook_springboard);
        return;
    }

    // 3. Smart Filter: Ignore system daemons and self
    if(!executablePath || [executablePath hasPrefix:@"/System"] || [executablePath hasPrefix:@"/usr/libexec"]) return;
    
    // Ensure we are in an actual .app container
    if(![executablePath containsString:@".app/"]) return;

    // Fast-exit for excluded identifiers
    static NSSet* excludedIdentifiers;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        excludedIdentifiers = [NSSet setWithObjects:@"com.apple.mobilesafari", @"com.samiiau.shadow", @"com.opa334.Dopamine", nil];
    });
    
    if([excludedIdentifiers containsObject:bundleIdentifier] || [bundleIdentifier hasPrefix:@"com.apple."]) return;

    // 4. Load Preferences & Sandbox
    NSDictionary* prefs = [[ShadowSettings sharedInstance] getPreferencesForIdentifier:bundleIdentifier];
    if(![prefs[@"App_Enabled"] boolValue]) return;

    // Initialize the Shadow Instance
    _shadow = [Shadow sharedInstance];

    // Apply libSandy profile to read settings in restricted sandboxes
    if(kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_11_0) {
        libSandy_applyProfile("ShadowSettings");
    }

    NSLog(@"[Shadow] Injecting into: %@", bundleIdentifier);

    // 5. Initialize HookKit
    HKSubstitutor* substitutor = [HKSubstitutor defaultSubstitutor];
    
    // Enable Batching for extreme speed (reduces system call overhead)
    HKEnableBatching();

    // 6. Core Hooks Execution
    // Every hook group we defined in hooks.h is triggered here based on user settings
    
    if([prefs[@"Hook_Filesystem"] boolValue]) {
        shadowhook_libc(substitutor);
        shadowhook_libc_lowlevel(substitutor);
        shadowhook_NSFileManager(substitutor);
        shadowhook_NSFileHandle(substitutor);
    }

    if([prefs[@"Hook_ObjC"] boolValue]) {
        shadowhook_objc(substitutor);
        if([prefs[@"Hook_TweakClasses"] boolValue]) {
            shadowhook_objc_hidetweakclasses(substitutor);
        }
    }

    if([prefs[@"Hook_DynamicLibraries"] boolValue]) {
        shadowhook_dyld(substitutor);
        shadowhook_dyld_extra(substitutor);
    }

    if([prefs[@"Hook_FakeMac"] boolValue]) {
        shadowhook_NSProcessInfo_fakemac(substitutor);
    }

    if([prefs[@"Hook_AntiDebugging"] boolValue]) {
        shadowhook_libc_antidebugging(substitutor);
    }

    if([prefs[@"Hook_EnvVars"] boolValue]) {
        shadowhook_libc_envvar(substitutor);
        // Sanitize environment immediately
        unsetenv("DYLD_INSERT_LIBRARIES");
        setenv("SHELL", "/bin/sh", 1);
    }

    // 7. Commit & Clean up
    HKExecuteBatch();
    HKDisableBatching();

    NSLog(@"[Shadow] All bypass hooks committed.");
}