INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Shadow

# 1. Source Files
# Automatically includes all .x files in the hooks folder plus dylib.x
Shadow_FILES = $(wildcard hooks/*.x) dylib.x

# 2. Dependencies
Shadow_LIBRARIES = sandy
Shadow_FRAMEWORKS = Foundation
# Shadow is our custom framework; HookKit and RootBridge are external dependencies
Shadow_EXTRA_FRAMEWORKS = Shadow HookKit RootBridge
Shadow_PRIVATE_FRAMEWORKS = MobileCoreServices

# 3. Compiler Flags
# Fixed header paths to ensure 'headers' (lowercase) is found
Shadow_CFLAGS = -fobjc-arc \
                -I../Shadow.framework/headers \
                -I../vendor/HookKit.framework/Headers \
                -I../vendor/RootBridge.framework/Headers

# 4. Linker Flags
# We use $(COMMON_LDFLAGS) inherited from the Main Makefile to handle RPATHs
Shadow_LDFLAGS = $(COMMON_LDFLAGS) \
                 -F../ \
                 -F../vendor \
                 -weak_framework CydiaSubstrate

include $(THEOS_MAKE_PATH)/tweak.mk