#ifndef shadow_settings_h
#define shadow_settings_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ShadowSettings : NSObject

/**
 * Hardcoded default values for all Shadow hooks.
 * Used when no user configuration exists.
 */
@property (strong, nonatomic, readonly) NSDictionary<NSString *, id>* defaultSettings;

/**
 * The NSUserDefaults suite used for preference storage.
 * Note: May be inaccessible in certain sandboxed environments.
 */
@property (strong, nonatomic, readonly) NSUserDefaults* userDefaults;

/**
 * Singleton instance for global access.
 */
+ (instancetype)sharedInstance;

/**
 * Merges settings in order of priority:
 * 1. App-specific overrides (from bundleIdentifier key)
 * 2. Global Tweak overrides (Global_Enabled)
 * 3. Default internal settings
 *
 * @param bundleIdentifier Target app's ID (e.g., com.apple.mobilesafari)
 */
- (NSDictionary<NSString *, id> *)getPreferencesForIdentifier:(nullable NSString *)bundleIdentifier;

@end

NS_ASSUME_NONNULL_END

#endif