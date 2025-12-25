#import "hooks.h"

// --- Logos Hooks for Foundation Classes ---
// High-level ObjC detection usually happens here.
%group shadow_objc_foundation
%hook NSFileManager
- (BOOL)fileExistsAtPath:(NSString *)path {
    if (!isCallerTweak() && [_shadow isPathRestricted:path]) {
        return NO;
    }
    return %orig;
}

- (BOOL)isReadableFileAtPath:(NSString *)path {
    if (!isCallerTweak() && [_shadow isPathRestricted:path]) {
        return NO;
    }
    return %orig;
}

- (BOOL)isDeletableFileAtPath:(NSString *)path {
    if (!isCallerTweak() && [_shadow isPathRestricted:path]) {
        return NO;
    }
    return %orig;
}
%end

%hook NSString
- (BOOL)writeToFile:(NSString *)path atomically:(BOOL)useAuxiliaryFile encoding:(NSStringEncoding)enc error:(NSError **)error {
    if (!isCallerTweak() && [_shadow isPathRestricted:path]) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteNoPermissionError userInfo:nil];
        return NO;
    }
    return %orig;
}
%end
%end

// --- C-Function Hooks for ObjC Runtime ---
// Advanced detection looks at the loaded classes and images.

static const char* (*original_class_getImageName)(Class cls);
static const char* replaced_class_getImageName(Class cls) {
    const char* result = original_class_getImageName(cls);

    if(isCallerTweak() || ![_shadow isCPathRestricted:result]) {
        return result;
    }

    // If the class belongs to a tweak, claim it belongs to the main app binary instead.
    return [[Shadow getExecutablePath] fileSystemRepresentation];
}

static const char * _Nonnull * (*original_objc_copyImageNames)(unsigned int *outCount);
static const char * _Nonnull * replaced_objc_copyImageNames(unsigned int *outCount) {
    const char * _Nonnull * result = original_objc_copyImageNames(outCount);

    if(isCallerTweak() || !result || !outCount) {
        return result;
    }

    // Filtering logic: only show images up to the main executable to hide injected dylibs.
    const char* exec_name = _dyld_get_image_name(0);
    for(unsigned int i = 0; i < *outCount; i++) {
        if(strcmp(result[i], exec_name) == 0) {
            *outCount = (i + 1);
            break;
        }
    }

    return result;
}

static Class (*original_NSClassFromString)(NSString* aClassName);
static Class replaced_NSClassFromString(NSString* aClassName) {
    Class result = original_NSClassFromString(aClassName);

    // If an app asks for a class like "Shadow_Hook", we return nil if that class's address is restricted.
    if(isCallerTweak() || ![_shadow isAddrRestricted:(__bridge const void *)result]) {
        return result;
    }

    return nil;
}

// --- Initialization Entry Points ---

void shadowhook_objc(HKSubstitutor* hooks) {
    // 1. Initialize Logos Group
    %init(shadow_objc_foundation);

    // 2. Hook Runtime C-Functions using HookKit
    MSHookFunction(class_getImageName, replaced_class_getImageName, (void **) &original_class_getImageName);
    MSHookFunction(objc_copyImageNames, replaced_objc_copyImageNames, (void **) &original_objc_copyImageNames);
    
    // Note: objc_copyClassNamesForImage is omitted as it's often redundant 
    // when class_getImageName is correctly handled.
}

void shadowhook_objc_hidetweakclasses(HKSubstitutor* hooks) {
    MSHookFunction(NSClassFromString, replaced_NSClassFromString, (void **) &original_NSClassFromString);
    
    // Note: NXMapGet and NXHashGet are extremely low-level and high-frequency.
    // Only enable if specifically targeted by an anti-cheat, as they can impact performance.
}