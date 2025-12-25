#ifndef SHADOW_HOOKS_H
#define SHADOW_HOOKS_H

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// --- System Headers ---
#import <stdio.h>
#import <sys/stat.h>
#import <sys/statvfs.h>
#import <sys/mount.h>
#import <sys/syscall.h>
#import <sys/utsname.h>
#import <sys/syslimits.h>
#import <sys/time.h>
#import <errno.h>
#import <fcntl.h>
#import <mach-o/dyld.h>
#import <mach-o/dyld_images.h>
#import <mach-o/nlist.h>
#import <dlfcn.h>
#import <dirent.h>
#import <sys/sysctl.h>
#import <mach/mach.h>
#import <mach/task_info.h>
#import <mach/mach_traps.h>
#import <mach/host_special_ports.h>
#import <mach/task_special_ports.h>
#import <sandbox.h>
#import <bootstrap.h>
#import <spawn.h>
#import <objc/runtime.h>

// --- Project Headers ---
#import "../../common.h"
#import <Shadow/Shadow.h>

// --- Hooking Engines ---
#import <substrate.h>
#import <HookKit.h>

// 1. Senior HookKit Mapping
// This allows your 888-line libc.x to use MSHookFunction while actually calling HookKit.
#ifdef hookkit_h
    #undef MSHookFunction
    #define MSHookFunction(a,b,c) [hooks hookFunction:(void *)a withReplacement:(void *)b outOldPtr:(void **)c]
    #define MSHookMessageEx       HKHookMessage
    #define MSGetImageByName      HKOpenImage
    #define MSFindSymbol          HKFindSymbol
    #define MSCloseImage          HKCloseImage
#endif

// 2. Private Apple Symbols (Ensure these files exist in your vendor path)
#import "../../vendor/apple/dyld_priv.h"
#import "../../vendor/apple/codesign.h"
#import "../../vendor/apple/ptrace.h"

// 3. Global Instance Reference
// This ensures that 'Shadow.dylib' and all 'hooks/*.x' files use the SAME object.
extern Shadow* _shadow;

// 4. PAC-Safe Caller Check (Your Original Optimized Logic)
#ifndef isCallerTweak
#define isCallerTweak() [[Shadow sharedInstance] isAddrExternal:__builtin_extract_return_addr(__builtin_return_address(0))]
#endif

// 5. Hook Group Declarations (The Namespace)
extern void shadowhook_DeviceCheck(HKSubstitutor* hooks);
extern void shadowhook_dyld(HKSubstitutor* hooks);
extern void shadowhook_libc(HKSubstitutor* hooks);
extern void shadowhook_mach(HKSubstitutor* hooks);
extern void shadowhook_NSArray(HKSubstitutor* hooks);
extern void shadowhook_NSBundle(HKSubstitutor* hooks);
extern void shadowhook_NSData(HKSubstitutor* hooks);
extern void shadowhook_NSDictionary(HKSubstitutor* hooks);
extern void shadowhook_NSFileHandle(HKSubstitutor* hooks);
extern void shadowhook_NSFileManager(HKSubstitutor* hooks);
extern void shadowhook_NSFileVersion(HKSubstitutor* hooks);
extern void shadowhook_NSFileWrapper(HKSubstitutor* hooks);
extern void shadowhook_NSProcessInfo(HKSubstitutor* hooks);
extern void shadowhook_NSString(HKSubstitutor* hooks);
extern void shadowhook_NSURL(HKSubstitutor* hooks);
extern void shadowhook_objc(HKSubstitutor* hooks);
extern void shadowhook_sandbox(HKSubstitutor* hooks);
extern void shadowhook_syscall(HKSubstitutor* hooks);
extern void shadowhook_UIApplication(HKSubstitutor* hooks);
extern void shadowhook_UIImage(HKSubstitutor* hooks);
extern void shadowhook_libc_envvar(HKSubstitutor* hooks);
extern void shadowhook_libc_lowlevel(HKSubstitutor* hooks);
extern void shadowhook_libc_antidebugging(HKSubstitutor* hooks);
extern void shadowhook_dyld_extra(HKSubstitutor* hooks);
extern void shadowhook_dyld_symlookup(HKSubstitutor* hooks);
extern void shadowhook_dyld_symaddrlookup(HKSubstitutor* hooks);
extern void shadowhook_NSProcessInfo_fakemac(HKSubstitutor* hooks);
extern void shadowhook_mem(HKSubstitutor* hooks);
extern void shadowhook_objc_hidetweakclasses(HKSubstitutor* hooks);
extern void shadowhook_LSApplicationWorkspace(HKSubstitutor* hooks);
extern void shadowhook_NSThread(HKSubstitutor* hooks);

#endif /* SHADOW_HOOKS_H */