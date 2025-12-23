include $(TOPDIR)/rules.mk

PKG_NAME:=ffgt-config-mode-wizard

include $(TOPDIR)/../package/gluon.mk

define Package/ffgt-config-mode-wizard
  TITLE:=Set geographic location of a node
  DEPENDS:=+gluon-config-mode-core +gluon-node-info # +gluon-config-mode-geo-location-osm
endef

#define Package/ffgt-config-mode-wizard/install
#	$(Gluon/Build/Install)
#
#	$(INSTALL_DIR) $(1)/lib/gluon/config-mode/view/ $(1)/lib/gluon/config-mode/www/static/
#	$(LN) /lib/gluon/web/i18n $(1)/lib/gluon/config-mode/
#	$(LN) /lib/gluon/web/view/{error,model} $(1)/lib/gluon/config-mode/view/
#	$(LN) /lib/gluon/web/www/static/gluon-web-model.js $(1)/lib/gluon/config-mode/www/static/
#endef

$(eval $(call BuildPackageGluon,ffgt-config-mode-wizard))
