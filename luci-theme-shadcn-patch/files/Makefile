#
# Copyright (C) 2026 eamonxg <eamonxiong@gmail.com>
# Licensed under the Apache License, Version 2.0.
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=A modern sidebar LuCI theme for OpenWrt, built with shadcn/ui design language.
LUCI_DEPENDS:=+luci-base

PKG_VERSION:=0.6.0
# Bumped by the luci-app-shadcn-config integration patch so that packages built
# from this tree sort above the unpatched upstream release of the same version.
PKG_RELEASE:=20261013.19
PKG_LICENSE:=Apache-2.0

LUCI_MINIFY_CSS:=
CONFIG_LUCI_CSSTIDY:=

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
