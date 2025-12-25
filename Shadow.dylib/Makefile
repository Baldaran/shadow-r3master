TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Shadow

# 1. Source Files
# Includes the entry point and all modular hook files
Shadow_FILES = dylib.x $(wildcard hooks/*.x) $(wildcard hooks/*.m)

# 2. Dependencies
# Sandy is a library (.dylib), while the others are Frameworks (.framework)
Shadow_LIBRARIES = sandy
Shadow_FRAMEWORKS = UIKit Foundation Security
Shadow_EXTRA_FRAMEWORKS = Shadow HookKit RootBridge

# 3. Compiler Flags
# -I../framework/include allows dylib.x to see Shadow.h
Shadow_CFLAGS = -fobjc-arc -I. -I../framework/include -I../vendor

# 4. Linker Flags
# We point to where the framework binaries actually sit after compilation
Shadow_LDFLAGS = -F../framework/obj -F../vendor -rpath /Library/Frameworks -rpath /var/jb/Library/Frameworks

include $(THEOS_MAKE_PATH)/tweak.mk