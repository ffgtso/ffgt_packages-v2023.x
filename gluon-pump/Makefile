include $(TOPDIR)/rules.mk

PKG_NAME:=gluon-pump
PKG_VERSION:=0.1.18
PKG_RELEASE:=1

PKG_MAINTAINER:=Freifunk <firmware@freifunk.net>
PKG_LICENSE:=MIT

include $(TOPDIR)/../package/gluon.mk

define Package/gluon-pump
  TITLE:=PUMP wireless batman-adv transport
  DEPENDS:=+gluon-core +gluon-web-admin +gluon-mesh-batman-adv +gluon-wireless-encryption-wpa3 +wpa-supplicant-wolfssl +libiwinfo-lua
endef

define Package/gluon-pump/description
  Premium Ultra Mesh Plus: encrypted AP/STA infrastructure WLAN used as a
  batman-adv transport interface via Gluon's gluon_mesh protocol.
endef

$(eval $(call BuildPackageGluon,gluon-pump))
