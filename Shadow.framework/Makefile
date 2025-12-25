# Target architecture and SDK
TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Shadow

# 1. Source Files
# This automatically finds your dylib.x and every .x/.m file inside the hooks folder
Shadow_FILES = dylib.x $(wildcard hooks/*.x) $(wildcard hooks/*.m)

# 2. Frameworks and Libraries
# We link against our own Shadow.framework and the helper libraries
Shadow_FRAMEWORKS = UIKit CoreFoundation Foundation Security
Shadow_EXTRA_FRAMEWORKS = Shadow
Shadow_LIBRARIES = HookKit Sandy RootBridge

# 3. Compiler Flags
# -I allows the compiler to find your internal headers
# -fobjc-arc enables Automatic Reference Counting
Shadow_CFLAGS = -fobjc-arc -Iinclude -I../framework/include -I.
Shadow_LDFLAGS = -L../framework/binaries -rpath /Library/Frameworks -rpath /var/jb/Library/Frameworks

include $(THEOS_MAKE_PATH)/tweak.mk

# 4. Subprojects
# This ensures that when you type 'make', it also builds your Settings bundle and Framework
SUBPROJECTS += ../framework ../shdw
include $(THEOS_MAKE_PATH)/aggregate.mk