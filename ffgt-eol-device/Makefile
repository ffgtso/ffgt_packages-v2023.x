include $(TOPDIR)/rules.mk

PKG_NAME:=ffgt-eol-device
PKG_VERSION:=v2025.1
PKG_RELEASE:=1

include $(TOPDIR)/../package/gluon.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/ffgt-eol-device
  TITLE:=Change autoupdater branch to "end-of-life" and add "-EOL" to nodename
  DEPENDS:=+gluon-core +libplatforminfo
endef

define Package/ffgt-eol-device/description
	Change autoupdater branch to "end-of-life" and add "-EOL" to nodename
endef

#define Package/ffgt-eol-device/install
#	$(CP) ./files/* $(1)/
#	$(INSTALL_DIR) $(1)/usr/sbin/
#	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/sbin/get_image_name $(1)/usr/sbin/
#endef

$(eval $(call BuildPackageGluon,ffgt-eol-device))
