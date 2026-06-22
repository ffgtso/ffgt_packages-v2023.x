include $(TOPDIR)/rules.mk

PKG_NAME:=gluon-pump
PKG_VERSION:=1
PKG_RELEASE:=2

include $(TOPDIR)/../package/gluon.mk

define Package/gluon-pump
  TITLE:=Enable PUMP as Mesh-option for DFS channels
  DEPENDS:=+gluon-web-admin +libiwinfo-lua
endef

$(eval $(call BuildPackageGluon,gluon-pump))
