# 1. Architectures & Target
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

# 2. Build Optimization
DEBUG = 0
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

# 3. Global Linker Flags (The "Secret Sauce")
# We use export so child Makefiles don't have to redefine these.
export COMMON_LDFLAGS = -F$(PWD) -F$(PWD)/vendor -rpath /Library/Frameworks -rpath /var/jb/Library/Frameworks

# 4. Subprojects Order
# Ensure these match your actual FOLDER names
SUBPROJECTS += Shadow.framework
SUBPROJECTS += Shadow.dylib
SUBPROJECTS += ShadowSettings.bundle
SUBPROJECTS += shdw

include $(THEOS_MAKE_PATH)/aggregate.mk