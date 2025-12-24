# Define architectures: Only 64-bit is needed for iOS 16
ARCHS = arm64 arm64e

# Set Target: iphone:clang:latest:14.0 is the sweet spot for rootless compatibility
TARGET = iphone:clang:latest:14.0

# Enable Rootless Scheme (CRITICAL for iOS 16 palera1n)
THEOS_PACKAGE_SCHEME = rootless

# Optimization: Only build a final package for release
DEBUG = 0
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

# Global flags to ensure all subprojects link correctly
# -lsubstrate is required for the Library Masking hooks
# -lRootBridge is required for rootless path redirection
export COMMON_LDFLAGS = -lsubstrate -lRootBridge

# List of sub-components to build
SUBPROJECTS += Shadow.framework
SUBPROJECTS += Shadow.dylib
SUBPROJECTS += ShadowSettings.bundle
SUBPROJECTS += shdw

# Include the aggregate rules to build all subprojects
include $(THEOS_MAKE_PATH)/aggregate.mk