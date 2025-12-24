include $(THEOS)/makefiles/common.mk

FRAMEWORK_NAME = Shadow

# 1. Implementation Files
# Included Backend.m as per your project structure
Shadow_FILES = Core.m Core+Utilities.m Backend.m Ruleset.m Settings.m

# 2. Framework Dependencies
Shadow_FRAMEWORKS = Foundation CoreFoundation
Shadow_EXTRA_FRAMEWORKS = RootBridge

# 3. Installation Path (Standard for iOS Frameworks)
Shadow_INSTALL_PATH = /Library/Frameworks

# 4. Compiler Flags
# Added -I. and standardized lowercase 'headers' path
Shadow_CFLAGS = -fobjc-arc -I. -Iheaders -I../ -I../vendor/RootBridge.framework/Headers

# 5. Linker Flags
# Optimized for Library Masking (CydiaSubstrate) and RPATH resolution
Shadow_LDFLAGS = -lsubstrate -F../vendor/ -install_name @rpath/Shadow.framework/Shadow

# Add multiple search paths for the dynamic linker (essential for iOS 16 Rootless)
Shadow_LDFLAGS += -rpath /Library/Frameworks \
                  -rpath /var/jb/Library/Frameworks \
                  -rpath /usr/lib \
                  -rpath /var/jb/usr/lib

# Include any global flags defined in common.mk
Shadow_LDFLAGS += $(COMMON_LDFLAGS)

include $(THEOS_MAKE_PATH)/framework.mk