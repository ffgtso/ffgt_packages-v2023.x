# SPDX-FileCopyrightText: 2023 kb-light, Patric Steffen, Andreas Ziegler, Florian Maurer
# SPDX-FileCopyrightText: 2026 Iak Gnireis and contributors
# SPDX-License-Identifier: BSD-2-Clause
include $(TOPDIR)/rules.mk

PKG_NAME:=pump-autoupdater-wifi-fallback
PKG_VERSION:=1
PKG_LICENSE:=BSD-2-Clause

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)
PKG_BUILD_DEPENDS := respondd

include $(TOPDIR)/../package/gluon.mk

define Package/$(PKG_NAME)
  TITLE:=PUMP-aware WiFi fallback for autoupdater recovery
  DEPENDS:=+gluon-autoupdater +gluon-site +iw +batctl-default +libgluonutil +libiwinfo-lua +luabitop +luaposix +micrond +wpa-supplicant-wolfssl
  CONFLICTS:=ffac-autoupdater-wifi-fallback
  MAINTAINER:=PUMP contributors
endef

$(eval $(call BuildPackageGluon,$(PKG_NAME)))
