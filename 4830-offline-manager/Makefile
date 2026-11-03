include $(TOPDIR)/rules.mk

PKG_NAME:=4830-offline-manager
PKG_VERSION:=1
PKG_RELEASE:=3
PKG_LICENSE:=BSD-2-Clause
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk

define Package/4830-offline-manager
  TITLE:=Coordinated offline SSIDs, recovery updates and watchdog for Gluon 2023.1
  DEPENDS:=+gluon-autoupdater +gluon-mesh-vpn-core +iw +batctl +libiwinfo-lua +luaposix +lua-jsonc +luabitop +libpacketmark +micrond +libuci +libjson-c
  CONFLICTS:=ffgt-ssid-changer pump-autoupdater-wifi-fallback tecff-ssid-changer gluon-ssid-changer tecff-autoupdater-wifi-fallback ffho-autoupdater-wifi-fallback ffac-autoupdater-wifi-fallback ffgt-autoupdater-wifi-fallback 4830-node-watchdog
endef

define Package/4830-offline-manager/conffiles
/etc/config/4830-offline-manager
endef

$(eval $(call BuildPackageGluon,4830-offline-manager))
