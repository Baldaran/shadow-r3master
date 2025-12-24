# 1. Architectures & Target
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

# 2. Build Optimization
DEBUG = 0
FINALPACKAGE = 1

include $(THEOS)/makefiles/common.mk

# 3. Subprojects Order (Framework MUST be first)
# We build the framework first so the dylib and bundle can link to it.
SUBPROJECTS += Shadow.framework
SUBPROJECTS += Shadow.dylib
SUBPROJECTS += ShadowSettings.bundle
SUBPROJECTS += shdw

include $(THEOS_MAKE_PATH)/aggregate.mk