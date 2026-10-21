# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=air6-modem
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=Rinrin <rinrin@aismir.in>

include $(INCLUDE_DIR)/package.mk

define Package/air6-modem
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=SoftBank Air 6 modem service
  DEPENDS:=@TARGET_mediatek_mt6990 +kmod-mt6990-modem +jsonfilter
  PKGARCH:=all
endef

define Package/air6-modem/description
  Runs the stock modem daemons of the SoftBank Air 6 in a chroot and adds
  the netifd protocol "air6mipc" and the ubus object "air6-modem". The
  stock files are not part of this package: the image builder copies the
  owner's own files to /usr/lib/air6-modem/. Disabled by default; the NV
  partitions it writes are shared with the stock firmware.
endef

define Package/air6-modem/conffiles
/etc/config/air6-modem
endef

define Build/Compile
endef

define Package/air6-modem/install
	$(INSTALL_DIR) $(1)/etc/config $(1)/etc/init.d $(1)/lib/netifd/proto \
		$(1)/usr/libexec/air6-modem $(1)/usr/libexec/rpcd $(1)/usr/share/rpcd/acl.d
	$(INSTALL_CONF) ./files/etc/config/air6-modem $(1)/etc/config/
	$(INSTALL_BIN) ./files/etc/init.d/air6-modem $(1)/etc/init.d/
	$(INSTALL_BIN) ./files/lib/netifd/proto/air6mipc.sh $(1)/lib/netifd/proto/
	$(INSTALL_BIN) ./files/usr/libexec/air6-modem/runtime $(1)/usr/libexec/air6-modem/
	$(INSTALL_BIN) ./files/usr/libexec/air6-modem/leds $(1)/usr/libexec/air6-modem/
	$(INSTALL_BIN) ./files/usr/libexec/air6-modem/watch $(1)/usr/libexec/air6-modem/
	$(INSTALL_BIN) ./files/usr/libexec/air6-modem/nv $(1)/usr/libexec/air6-modem/
	$(INSTALL_BIN) ./files/usr/libexec/rpcd/air6-modem $(1)/usr/libexec/rpcd/
	$(INSTALL_DATA) ./files/usr/share/rpcd/acl.d/air6-modem.json $(1)/usr/share/rpcd/acl.d/
endef

$(eval $(call BuildPackage,air6-modem))
