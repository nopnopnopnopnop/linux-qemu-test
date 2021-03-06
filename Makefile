ARCH=$(shell uname -m)
NET_BRIDGE ?= br0
NET_HWADDR ?= 66:66:66:66:66:66
NET_IP4 ?=
LINUX_LOCAL ?=
DEFCONFIG ?=

BUILDJOBS ?= $(shell cat /proc/cpuinfo | grep -o '^processor' | wc -l)
THIS_DIR=$(realpath .)

DL_DIR=$(THIS_DIR)/dl
BUILD_DIR=$(THIS_DIR)/build
ROOTFS_DIR=$(THIS_DIR)/rootfs
CFG_DIR=$(THIS_DIR)/config
SCRIPT_DIR=$(THIS_DIR)/scripts
SKEL_DIR=$(THIS_DIR)/skeleton

INITRD_TARGET=$(THIS_DIR)/initramfs.cpio.gz

LINUX_DL_PREFIX=https://cdn.kernel.org/pub/linux/kernel/v4.x
LINUX_DL_BASENAME=linux
LINUX_DL_VERSION=4.18
LINUX_DL_SUFFIX=tar.xz
LINUX_DL_URL=$(LINUX_DL_PREFIX)/$(LINUX_DL_BASENAME)-$(LINUX_DL_VERSION).$(LINUX_DL_SUFFIX)
LINUX_DL_FILE=$(DL_DIR)/$(LINUX_DL_BASENAME)-$(LINUX_DL_VERSION).$(LINUX_DL_SUFFIX)
LINUX_BUILD_DIR=$(BUILD_DIR)/$(LINUX_DL_BASENAME)-$(LINUX_DL_VERSION)
LINUX_TARGET=$(LINUX_BUILD_DIR)/vmlinux

MUSL_DL_PREFIX=https://www.musl-libc.org/releases
MUSL_DL_BASENAME=musl
MUSL_DL_VERSION=1.1.19
MUSL_DL_SUFFIX=tar.gz
MUSL_DL_URL=$(MUSL_DL_PREFIX)/$(MUSL_DL_BASENAME)-$(MUSL_DL_VERSION).$(MUSL_DL_SUFFIX)
MUSL_DL_FILE=$(DL_DIR)/$(MUSL_DL_BASENAME)-$(MUSL_DL_VERSION)
MUSL_BUILD_DIR=$(BUILD_DIR)/$(MUSL_DL_BASENAME)-$(MUSL_DL_VERSION)
MUSL_TARGET=$(MUSL_BUILD_DIR)/lib/libc.so

BUSYBOX_DL_PREFIX=https://busybox.net/downloads
BUSYBOX_DL_BASENAME=busybox
BUSYBOX_DL_VERSION=1.29.2
BUSYBOX_DL_SUFFIX=tar.bz2
BUSYBOX_DL_URL=$(BUSYBOX_DL_PREFIX)/$(BUSYBOX_DL_BASENAME)-$(BUSYBOX_DL_VERSION).$(BUSYBOX_DL_SUFFIX)
BUSYBOX_DL_FILE=$(DL_DIR)/$(BUSYBOX_DL_BASENAME)-$(BUSYBOX_DL_VERSION).$(BUSYBOX_DL_SUFFIX)
BUSYBOX_BUILD_DIR=$(BUILD_DIR)/$(BUSYBOX_DL_BASENAME)-$(BUSYBOX_DL_VERSION)
BUSYBOX_CFLAGS=-no-pie -I$(ROOTFS_DIR)/usr/include -specs $(ROOTFS_DIR)/lib/musl-gcc.specs -Wno-parentheses -Wno-strict-prototypes -Wno-undef
BUSYBOX_LDFLAGS=-L$(ROOTFS_DIR)/lib
BUSYBOX_TARGET=$(BUSYBOX_BUILD_DIR)/busybox

all: pre dl extract build image

$(DL_DIR):
	mkdir -p '$@'
$(BUILD_DIR):
	mkdir -p '$@'
$(ROOTFS_DIR):
	mkdir -p '$@'
$(LINUX_BUILD_DIR):
	mkdir -p '$@'
$(MUSL_BUILD_DIR):
	mkdir -p '$@'
$(BUSYBOX_BUILD_DIR):
	mkdir -p '$@'

pre: $(DL_DIR) $(BUILD_DIR) $(ROOTFS_DIR) $(LINUX_BUILD_DIR) $(MUSL_BUILD_DIR) $(BUSYBOX_BUILD_DIR)

$(LINUX_DL_FILE):
ifeq (x$(LINUX_LOCAL),x)
	wget '$(LINUX_DL_URL)' -O '$@' || (rm -f '$(LINUX_DL_FILE)' && false)
endif

$(MUSL_DL_FILE):
	wget '$(MUSL_DL_URL)' -O '$@' || (rm -f '$(MUSL_DL_FILE)' && false)

$(BUSYBOX_DL_FILE):
	wget '$(BUSYBOX_DL_URL)' -O '$@' || (rm -f '$(BUSYBOX_DL_FILE)' && false)

dl: pre $(LINUX_DL_FILE) $(MUSL_DL_FILE) $(BUSYBOX_DL_FILE)

$(LINUX_BUILD_DIR)/Makefile:
ifeq (x$(LINUX_LOCAL),x)
	tar --strip-components=1 -C '$(LINUX_BUILD_DIR)' -xvf '$(LINUX_DL_FILE)' || (rm -rf '$(LINUX_BUILD_DIR)' && false)
else
	rmdir '$(LINUX_BUILD_DIR)'
	ln -s '$(LINUX_LOCAL)' '$(LINUX_BUILD_DIR)'
endif

$(MUSL_BUILD_DIR)/Makefile:
	tar --strip-components=1 -C '$(MUSL_BUILD_DIR)' -xvzf '$(MUSL_DL_FILE)' || (rm -rf '$(MUSL_BUILD_DIR)' && false)

$(BUSYBOX_BUILD_DIR)/Makefile:
	tar --strip-components=1 -C '$(BUSYBOX_BUILD_DIR)' -xvjf '$(BUSYBOX_DL_FILE)' || (rm -rf '$(BUSYBOX_BUILD_DIR)' && false)

extract: dl $(LINUX_BUILD_DIR)/Makefile $(MUSL_BUILD_DIR)/Makefile $(BUSYBOX_BUILD_DIR)/Makefile

$(LINUX_TARGET):
	cp -v '$(CFG_DIR)/linux.config' '$(LINUX_BUILD_DIR)/.config'
ifeq (x$(DEFCONFIG),x)
	make -C '$(LINUX_BUILD_DIR)' oldconfig
else
	make -C '$(LINUX_BUILD_DIR)' x86_64_defconfig
endif
	make -C '$(LINUX_BUILD_DIR)' kvmconfig
	make -C '$(LINUX_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(ARCH)' bzImage
	make -C '$(LINUX_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(ARCH)' INSTALL_HDR_PATH='$(ROOTFS_DIR)/usr' headers_install
	make -C '$(LINUX_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(ARCH)' INSTALL_MOD_PATH='$(ROOTFS_DIR)/usr' modules
	make -C '$(LINUX_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(ARCH)' INSTALL_MOD_PATH='$(ROOTFS_DIR)/usr' modules_install

$(MUSL_TARGET):
	cd '$(MUSL_BUILD_DIR)' && (test -r ./config.mak || ./configure --prefix='$(ROOTFS_DIR)/usr')
	make -C '$(MUSL_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(ARCH)' V=1 all
	make -C '$(MUSL_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(ARCH)' install
	ln -sr '$(ROOTFS_DIR)/usr/lib' '$(ROOTFS_DIR)/lib' || true
	ln -sr '$(ROOTFS_DIR)/lib/libc.so' '$(ROOTFS_DIR)/lib/ld-musl-$(ARCH).so.1' || true

$(BUSYBOX_TARGET):
	cp -v '$(CFG_DIR)/busybox.config' '$(BUSYBOX_BUILD_DIR)/.config'
	sed -i 's,^\(CONFIG_EXTRA_CFLAGS[ ]*=\).*,\1"$(BUSYBOX_CFLAGS)",g'   '$(BUSYBOX_BUILD_DIR)/.config'
	sed -i 's,^\(CONFIG_EXTRA_LDFLAGS[ ]*=\).*,\1"$(BUSYBOX_LDFLAGS)",g' '$(BUSYBOX_BUILD_DIR)/.config'
	sed -i 's,^\(CONFIG_PREFIX[ ]*=\).*,\1"$(ROOTFS_DIR)",g'             '$(BUSYBOX_BUILD_DIR)/.config'
	make -C '$(BUSYBOX_BUILD_DIR)' oldconfig
	make -C '$(BUSYBOX_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(ARCH)' V=1 all
	make -C '$(BUSYBOX_BUILD_DIR)' -j$(BUILDJOBS) ARCH='$(ARCH)' install
	sed -i 's,^\(CONFIG_EXTRA_CFLAGS[ ]*=\).*,\1"",g'     '$(BUSYBOX_BUILD_DIR)/.config'
	sed -i 's,^\(CONFIG_EXTRA_LDFLAGS[ ]*=\).*,\1"",g'    '$(BUSYBOX_BUILD_DIR)/.config'
	sed -i 's,^\(CONFIG_PREFIX[ ]*=\).*,\1"./_install",g' '$(BUSYBOX_BUILD_DIR)/.config'

build: extract $(LINUX_TARGET) $(MUSL_TARGET) $(BUSYBOX_TARGET)

$(INITRD_TARGET):
	cp -v '$(SCRIPT_DIR)/init.rootfs' '$(ROOTFS_DIR)/init'
	cp -rfvTp '$(SKEL_DIR)' '$(ROOTFS_DIR)'
	chmod 0755 '$(ROOTFS_DIR)/init'
	cd '$(ROOTFS_DIR)' && find . -print0 | cpio --null -ov --format=newc | gzip -9 > '$(INITRD_TARGET)'

image: build $(INITRD_TARGET)

define DO_BUILD
	make
endef

force-remove:
	rm -f $(LINUX_TARGET) $(MUSL_TARGET) $(BUSYBOX_TARGET)
	rm -f '$(INITRD_TARGET)'

image-rebuild: force-remove
	rm -rf '$(ROOTFS_DIR)'
	$(DO_BUILD)

image-reinstall: force-remove
	$(DO_BUILD)

image-repack:
	rm -f '$(INITRD_TARGET)'
	$(DO_BUILD)

net:
	sudo ip tuntap add linux-qemu-test mode tap
	sudo /etc/qemu-ifup linux-qemu-test

qemu: image
	qemu-system-$(ARCH) -kernel '$(LINUX_BUILD_DIR)/arch/$(ARCH)/boot/bzImage' -initrd '$(INITRD_TARGET)' -enable-kvm -vga qxl -display sdl

qemu-console: image
	qemu-system-$(ARCH) -kernel '$(LINUX_BUILD_DIR)/arch/$(ARCH)/boot/bzImage' -initrd '$(INITRD_TARGET)' -enable-kvm -curses

qemu-serial: image
	qemu-system-$(ARCH) -kernel '$(LINUX_BUILD_DIR)/arch/$(ARCH)/boot/bzImage' -initrd '$(INITRD_TARGET)' -enable-kvm -nographic -append console=ttyS0

qemu-serial-net: image
	qemu-system-$(ARCH) -kernel '$(LINUX_BUILD_DIR)/arch/$(ARCH)/boot/bzImage' -initrd '$(INITRD_TARGET)' -enable-kvm -nographic \
		-net nic,macaddr=$(NET_HWADDR) -net tap,ifname=linux-qemu-test,br=$(NET_BRIDGE),script=no,downscript=no -append 'net $(if $(NET_IP4),ip4) console=ttyS0'

qemu-net: image
	qemu-system-$(ARCH) -kernel '$(LINUX_BUILD_DIR)/arch/$(ARCH)/boot/bzImage' -initrd '$(INITRD_TARGET)' -enable-kvm -vga qxl -display sdl \
		-net nic,macaddr=$(NET_HWADDR) -net tap,ifname=linux-qemu-test,br=$(NET_BRIDGE),script=no,downscript=no -append 'net $(if $(NET_IP4),ip4)'

define HELP_PREFIX
	@echo "\t make $1\t- $2"
endef

help:
	@echo 'Available Makefile targets are:'
	$(call HELP_PREFIX,build,build LinuxKernel/musl/BusyBox)
	$(call HELP_PREFIX,image,create initramfs cpio archive)
	$(call HELP_PREFIX,image-rebuild,force recreation of rootfs)
	$(call HELP_PREFIX,image-reinstall,force reinstallation of LinuxKernel/musl/BusyBox into rootfs)
	$(call HELP_PREFIX,image-repack,force initramfs cpio archive recreation)
	$(call HELP_PREFIX,qemu,testing your kernel/initramfs combination with QEMU)
	$(call HELP_PREFIX,qemu-console,testing your kernel/initramfs combination with [n]curses QEMU)
	$(call HELP_PREFIX,qemu-net,testing your kernel/initramfs combination with QEMU and network support through TAP)
	@echo "\t\tAdditional options: NET_BRIDGE, NET_IP4, NET_HWADDR"
