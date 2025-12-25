# Target architecture and SDK
TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

FRAMEWORK_NAME = Shadow

# 1. Implementation Files (The Core Engine)
Shadow_FILES = Core.m Core+Utilities.m Backend.m Ruleset.m Settings.m

# 2. Dependencies
# We use Foundation for logic and RootBridge for filesystem abstraction
Shadow_FRAMEWORKS = Foundation CoreFoundation
Shadow_EXTRA_FRAMEWORKS = RootBridge

# 3. Installation Path
# This is the standard location for iOS frameworks
Shadow_INSTALL_PATH = /Library/Frameworks

# 4. Compiler Flags
# -I. ensures internal headers are found during the build
Shadow_CFLAGS = -fobjc-arc -I. -Iinclude -I../

# 5. Linker Flags (The "Gold Standard" Config)
# -install_name @rpath allows the dylib to find the framework in multiple locations
Shadow_LDFLAGS = -install_name @rpath/Shadow.framework/Shadow

# Add search paths for the dynamic linker (Crucial for iOS 15+ Rootless)
Shadow_LDFLAGS += -rpath /Library/Frameworks \
                  -rpath /var/jb/Library/Frameworks \
                  -rpath /usr/lib \
                  -rpath /var/jb/usr/lib

include $(THEOS_MAKE_PATH)/framework.mk