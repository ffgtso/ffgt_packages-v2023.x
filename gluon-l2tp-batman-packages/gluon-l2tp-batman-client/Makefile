include $(TOPDIR)/rules.mk

PKG_NAME:=gluon-l2tp-batman-client
PKG_VERSION:=1
PKG_RELEASE:=1
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/gluon-l2tp-batman-client
  SECTION:=gluon
  CATEGORY:=Gluon
  TITLE:=L2TPv3-to-batman client for Gluon
  DEPENDS:=+ip-full +kmod-l2tp +kmod-l2tp-eth +batctl +uclient-fetch
endef

define Package/gluon-l2tp-batman-client/description
  Calls a gluon-l2tp-batman-server CGI endpoint, receives the static
  unmanaged L2TPv3 parameters, creates the local Ethernet pseudowire
  with ip l2tp and adds it to bat0.
endef

define Build/Compile
endef

define Package/gluon-l2tp-batman-client/install
	$(CP) ./files/* $(1)/
endef

$(eval $(call BuildPackage,gluon-l2tp-batman-client))
