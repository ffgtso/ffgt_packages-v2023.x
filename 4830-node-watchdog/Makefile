include $(TOPDIR)/rules.mk

PKG_NAME:=4830-node-watchdog
PKG_VERSION:=1
PKG_RELEASE:=1

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/4830-node-watchdog
  SECTION:=gluon
  CATEGORY:=Gluon
  TITLE:=Node watchdog
  DEPENDS:=+gluon-core +micrond
endef

define Build/Prepare
        mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/4830-node-watchdog/install
        $(CP) ./files/* $(1)/
endef

$(eval $(call BuildPackage,4830-node-watchdog))

