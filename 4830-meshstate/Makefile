include $(TOPDIR)/rules.mk

PKG_NAME:=4830-meshstate
PKG_VERSION:=1
PKG_RELEASE:=1
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/4830-meshstate
  TITLE:=Fetch and verify signed mesh state
  DEPENDS:=+gluon-core +gluon-autoupdater +lua-simple-uci +micrond +uclient-fetch +ecdsautils
endef

define Package/4830-meshstate/description
  Fetches a node-specific meshstate once per hour and accepts it only when
  at least one signature can be verified with a public key of the currently
  selected Gluon autoupdater branch.
endef

$(eval $(call BuildPackageGluon,4830-meshstate))
