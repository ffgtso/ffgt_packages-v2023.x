include $(TOPDIR)/rules.mk

PKG_NAME:=wpa-supplicant-dummy
PKG_VERSION:=5

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)
PKG_BUILD_DEPENDS := respondd

include $(TOPDIR)/../package/gluon.mk

define Package/wpa-supplicant-dummy
  SECTION:=ffgt
  CATEGORY:=Customization
  TITLE:=Implements a dummy /usr/sbin/wpa_supplicant for tecff-autoupdater-wifi-fallback
  DEPENDS:=+tecff-autoupdater-wifi-fallback
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile
	$(call GluonSrcDiet,./luasrc,$(PKG_BUILD_DIR)/luadest/)
endef

define Package/wpa-supplicant-dummy/install
	$(CP) $(PKG_BUILD_DIR)/luadest/* $(1)/
endef

$(eval $(call BuildPackage,wpa-supplicant-dummy))
