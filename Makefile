# 1. Architectures & Target
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

# 2. Build Optimization
DEBUG = 0
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

# 3. Global Linker Flags (The "Secret Sauce")
# This tells EVERY subproject where to find the Shadow framework and RootBridge
# during the build process and at runtime on the device.
export COMMON_LDFLAGS = -F$(THEOS_OBJ_DIR) -F./vendor -rpath /Library/Frameworks -rpath /var/jb/Library/Frameworks

# 4. Subprojects Order
# Shadow.framework MUST stay first so its headers/binary exist for the others.
SUBPROJECTS += Shadow.framework
SUBPROJECTS += Shadow.dylib
SUBPROJECTS += ShadowSettings.bundle
SUBPROJECTS += shdw

include $(THEOS_MAKE_PATH)/aggregate.mk