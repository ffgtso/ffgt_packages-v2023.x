include $(TOPDIR)/rules.mk

PKG_NAME:=gluon-l2tp-batman-server
PKG_VERSION:=1
PKG_RELEASE:=1
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/gluon-l2tp-batman-server
  SECTION:=gluon
  CATEGORY:=Gluon
  TITLE:=L2TPv3-to-batman uhttpd CGI server for Gluon
  DEPENDS:=+uhttpd +ip-full +kmod-l2tp +kmod-l2tp-eth +batctl +lua
endef

define Package/gluon-l2tp-batman-server/description
  Starts an extra uhttpd instance on the Gluon next-node/local-node
  addresses. The CGI endpoint creates a static unmanaged L2TPv3
  Ethernet pseudowire for the requesting IP and adds it to bat0.
endef

define Build/Compile
endef

define Package/gluon-l2tp-batman-server/install
	$(CP) ./files/* $(1)/
endef

define Package/gluon-l2tp-batman-server/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	[ -x /lib/gluon/upgrade/510-gluon-l2tp-batman-server ] && /lib/gluon/upgrade/510-gluon-l2tp-batman-server
	/etc/init.d/uhttpd reload 2>/dev/null || /etc/init.d/uhttpd restart 2>/dev/null || true
}
exit 0
endef

$(eval $(call BuildPackage,gluon-l2tp-batman-server))
