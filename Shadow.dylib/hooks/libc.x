#import "hooks.h"
#import <Shadow/Shadow.h>
#import <HookKit.h>
#import <sys/sysctl.h>
#import <sys/mount.h>
#import <sys/utsname.h>

// Macro for cleaner HookKit registration
#define HK_HOOK(sym, repl, orig) [hooks hookSymbol:#sym library:nil replacement:(void *)repl old:(void **)&orig]

// --- Hook Implementations ---

static int (*original_access)(const char* pathname, int mode);
static int replaced_access(const char* pathname, int mode) {
    if(!isCallerTweak() && [_shadow isCPathRestricted:pathname]) {
        errno = ENOENT;
        return -1;
    }
    return original_access(pathname, mode);
}

// ... (Internal implementations for stat, lstat, etc. follow the same pattern)

static int (*original_getfsstat)(struct statfs* buf, int bufsize, int flags);
static int replaced_getfsstat(struct statfs* buf, int bufsize, int flags) {
    int result = original_getfsstat(buf, bufsize, flags);
    if(result != -1 && buf && !isCallerTweak()) {
        for(int i = 0; i < result; i++) {
            if([_shadow isCPathRestricted:buf[i].f_mntonname]) {
                // Cloak the mount point as the root directory
                strcpy(buf[i].f_mntonname, "/");
            }
            if(strcmp(buf[i].f_mntonname, "/") == 0) {
                // Fake a clean, read-only rootfs
                buf[i].f_flags |= MNT_RDONLY | MNT_ROOTFS | MNT_SNAPSHOT;
            }
        }
    }
    return result;
}

static int (*original_sysctl)(int* name, u_int namelen, void* oldp, size_t* oldlenp, void* newp, size_t newlen);
static int replaced_sysctl(int* name, u_int namelen, void* oldp, size_t* oldlenp, void* newp, size_t newlen) {
    // Anti-Process Enumeration
    if(namelen == 4 && name[0] == CTL_KERN && name[1] == KERN_PROC && name[2] == KERN_PROC_ALL) {
        if(oldlenp) *oldlenp = 0;
        return 0;
    }

    int ret = original_sysctl(name, namelen, oldp, oldlenp, newp, newlen);

    // Anti-Debugging (P_TRACED flag)
    if(ret == 0 && !isCallerTweak() && oldp && namelen >= 4 && name[0] == CTL_KERN && name[1] == KERN_PROC && name[2] == KERN_PROC_PID && name[3] == getpid()) {
        struct kinfo_proc *p = (struct kinfo_proc *)oldp;
        p->kp_proc.p_flag &= ~(P_TRACED | P_SELECT);
    }
    return ret;
}

// --- Initialization Functions ---

void shadowhook_libc(HKSubstitutor* hooks) {
    if(!hooks) return;

    HK_HOOK(access, replaced_access, original_access);
    HK_HOOK(chdir, replaced_chdir, original_chdir);
    HK_HOOK(statfs, replaced_statfs, original_statfs);
    HK_HOOK(getmntinfo, replaced_getmntinfo, original_getmntinfo);
    HK_HOOK(getfsstat, replaced_getfsstat, original_getfsstat);
    HK_HOOK(stat, replaced_stat, original_stat);
    HK_HOOK(lstat, replaced_lstat, original_lstat);
    HK_HOOK(fopen, replaced_fopen, original_fopen);
    HK_HOOK(realpath, replaced_realpath, original_realpath);
}

void shadowhook_libc_antidebugging(HKSubstitutor* hooks) {
    if(!hooks) return;

    HK_HOOK(ptrace, replaced_ptrace, original_ptrace);
    HK_HOOK(sysctl, replaced_sysctl, original_sysctl);
    // getppid doesn't need an original pointer because we always return 1
    [hooks hookSymbol:"getppid" library:nil replacement:(void *)replaced_getppid old:NULL];
}

void shadowhook_libc_lowlevel(HKSubstitutor* hooks) {
    if(!hooks) return;

    HK_HOOK(open, replaced_open, original_open);
    HK_HOOK(openat, replaced_openat, original_openat);
}