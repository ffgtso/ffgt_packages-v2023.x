# SPDX-FileCopyrightText: 2023 kb-light, Patric Steffen, Andreas Ziegler, Florian Maurer
# SPDX-License-Identifier: BSD-2-Clause
include $(TOPDIR)/rules.mk

PKG_NAME:=pump-autoupdater-wifi-fallback
PKG_VERSION:=3
PKG_LICENSE:=BSD-2-Clause

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)
PKG_BUILD_DEPENDS := respondd

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  TITLE:=PUMP-aware autoupdater WiFi fallback
  DEPENDS:=+gluon-autoupdater +gluon-site +iw +libgluonutil +libiwinfo-lua +luabitop +luaposix +micrond +batctl-default +wpa-supplicant-wolfssl
  CONFLICTS:=ffac-autoupdater-wifi-fallback
  MAINTAINER:=Freifunk Aachen <kontakt@freifunk-aachen.de>
endef

$(eval $(call BuildPackageGluon,$(PKG_NAME)))
