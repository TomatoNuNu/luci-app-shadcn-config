#
# luci-app-shadcn-config: configuration app for the luci-theme-shadcn theme
#
# Provides a settings page for the shadcn LuCI theme:
#   - login page wallpaper (built-in / uploaded / gradient / random)
#   - brand color in HEX, separately for light and dark mode
#   - day/night mode policy (follow system / force light / force dark)
#
# The theme side reads /etc/config/shadcn itself, so the matching theme
# integration (see luci-theme-shadcn-patch/) must be present for the
# settings to take effect.
#
# Licensed under the Apache License, Version 2.0.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-shadcn-config
PKG_VERSION:=1.0.9
PKG_RELEASE:=20261013

PKG_MAINTAINER:=shadcn-config contributors
PKG_LICENSE:=Apache-2.0

LUCI_TITLE:=Configuration app for the luci-theme-shadcn theme
LUCI_DESCRIPTION:=Settings page for the shadcn LuCI theme: login wallpaper, \
	HEX brand color for light/dark mode and a day/night mode policy that can \
	follow the system preference.
LUCI_DEPENDS:=+luci-base +luci-theme-shadcn
LUCI_PKGARCH:=all

define Package/luci-app-shadcn-config/conffiles
/etc/config/shadcn
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
