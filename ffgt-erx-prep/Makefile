include $(TOPDIR)/rules.mk

PKG_NAME:=ffgt-erx-prep
PKG_VERSION:=1

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(TOPDIR)/../package/gluon.mk

define Package/ffgt-erx-prep
  SECTION:=ffgt
  CATEGORY:=FFGT
  TITLE:=Files to help migration to larger kernels
  DEPENDS:=+gluon-web-admin
  MAINTAINER:=Freifunk KreisGT <info@freifunk-kreisgt.de>
endef

$(eval $(call BuildPackageGluon,$(PKG_NAME)))
