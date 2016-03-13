root_dir := $(shell pwd)

uboot_version := u-boot
kernel_version := uclinux
busybox_version := busybox-1.22.1

FETCH_CMD_uboot := git clone https://github.com/robutest/u-boot.git
FETCH_CMD_kernel := git clone https://github.com/robutest/uclinux.git
FETCH_CMD_busybox := wget -P downloads -c http://busybox.net/downloads/${busybox_version}.tar.bz2

FLASH_CMD := openocd \
	-f board/stm32f429discovery.cfg \
	-c "init" \
	-c "reset init" \
	-c "flash probe 0" \
	-c "flash info 0" \
	-c "flash write_image erase $(uboot_target)  0x08000000" \
	-c "flash write_image erase $(kernel_target) 0x08020000" \
	-c "flash write_image erase $(rootfs_target) 0x08120000" \
	-c "reset run" -c shutdown

uboot_dir := $(root_dir)/$(uboot_version)
kernel_dir := $(root_dir)/$(kernel_version)
busybox_dir := $(root_dir)/$(busybox_version)
rootfs_dir := $(root_dir)/rootfs

target_out := $(root_dir)/out
download_dir := $(root_dir)/downloads

TARGETS := $(uboot_target) $(kernel_target) $(rootfs_target)

target_out_uboot := $(target_out)/uboot
target_out_kernel := $(target_out)/kernel
target_out_busybox := $(target_out)/busybox
target_out_romfs := $(target_out)/romfs


uboot_target :=  $(target_out)/uboot/u-boot.bin
kernel_target := $(target_out)/kernel/arch/arm/boot/xipuImage.bin
rootfs_target := $(target_out)/romfs.bin

# toolchain configurations
CROSS_COMPILE ?= arm-uclinuxeabi-
ROOTFS_CFLAGS := "-march=armv7-m -mtune=cortex-m4 \
-mlittle-endian -mthumb \
-Os -ffast-math \
-ffunction-sections -fdata-sections \
-Wl,--gc-sections \
-fno-common \
--param max-inline-insns-single=1000 \
-Wl,-elf2flt=-s -Wl,-elf2flt=16384"

.PHONY: all prepare uboot kernel rootfs
all: prepare stamp-uboot stamp-kernel stamp-rootfs

prepare:

# downloads and temporary output directory
$(shell mkdir -p $(target_out))
$(shell mkdir -p $(download_dir))

# Check cross compiler
filesystem_path := $(shell which ${CROSS_COMPILE}gcc 2>/dev/null)
ifeq ($(strip $(filesystem_path)),)                                                                                         
$(error No uClinux toolchain found)
endif

# Check u-boot
filesystem_path := $(shell ls $(uboot_dir) 2>/dev/null)
ifeq ($(strip $(filesystem_path)),)
$(info *** Fetching u-boot source ***)
$(info $(shell ${FETCH_CMD_uboot}))
endif

# Check kernel
filesystem_path := $(shell ls $(kernel_dir) 2>/dev/null)
ifeq ($(strip $(filesystem_path)),)
$(info *** Fetching uClinux source ***)
$(info $(shell ${FETCH_CMD_kernel}))
endif

# Check busybox
filesystem_path := $(shell ls $(busybox_dir) 2>/dev/null)
ifeq ($(strip $(filesystem_path)),)
$(info *** Fetching busybox source ***)
$(info $(shell ${FETCH_CMD_busybox}))
$(info $(shell tar -jxf downloads/${busybox_version}.tar.bz2 -C $(root_dir)))
endif


###############################  kernel   ##########################################################
build-kernel: $(target_out_uboot)/tools/mkimage
	$(shell mkdir -p ${target_out_kernel})
	cp -f configs/kernel_config $(target_out)/kernel/.config
	env PATH=$(target_out_uboot)/tools:$(PATH) make -C $(kernel_dir) \
		ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) \
		O=$(target_out_kernel) oldconfig xipImage modules
	cat $(kernel_dir)/arch/arm/boot/tempfile \
	    $(target_out_kernel)/arch/arm/boot/xipImage > $(target_out_kernel)/arch/arm/boot/xipImage.bin
	$< -x -A arm -O linux -T kernel -C none \
		-a 0x08020040 -e 0x08020041 \
		-n "Linux-2.6.33-arm1" \
		-d $(target_out_kernel)/arch/arm/boot/xipImage.bin \
		$(target_out_kernel)/arch/arm/boot/xipuImage.bin


###################################### root fs        ##############################################
build-rootfs: busybox $(rootfs_target)

busybox:
	$(shell mkdir -p ${target_out_busybox})
	$(shell mkdir -p ${target_out_romfs})
	cp -f configs/busybox_config $(target_out_busybox)/.config
	make -C $(busybox_dir) \
		O=$(target_out_busybox) oldconfig
	make -C $(target_out_busybox) \
		ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) \
		CFLAGS=$(ROOTFS_CFLAGS) SKIP_STRIP=y \
		CONFIG_PREFIX=$(target_out_romfs) install

$(rootfs_target): $(rootfs_dir) $(target_out_busybox)/.config
	cp -af $(rootfs_dir)/* $(target_out_romfs)
	cp -f $(target_out_kernel)/fs/ext2/ext2.ko $(target_out_romfs)/lib/modules
	cp -f $(target_out_kernel)/fs/mbcache.ko $(target_out_romfs)/lib/modules
	cd $(target_out) && genromfs -v \
		-V "ROM Disk" \
		-f romfs.bin \
		-x placeholder \
		-d $(target_out_romfs) 2> $(target_out)/romfs.map

######################################## u boot ####################################################

build-uboot:
	$(shell mkdir -p ${target_out_uboot})
	env LANG=C make -C $(uboot_dir) \
		ARCH=arm CROSS_COMPILE=$(CROSS_COMPILE) \
		O=$(target_out_uboot) \
		stm32429-disco



# u-boot
stamp-uboot:
	$(MAKE) build-uboot
	touch $@
include mk/uboot.mak
clean-uboot:
	rm -rf $(target_out)/uboot stamp-uboot

# Linux kernel
stamp-kernel:
	$(MAKE) build-kernel
	touch $@
include mk/kernel.mak
clean-kernel:
	rm -rf $(target_out_kernel) stamp-kernel

# Root file system
stamp-rootfs:
	$(MAKE) build-rootfs
	touch $@
include mk/rootfs.mak
clean-rootfs:
	rm -rf $(target_out_busybox) $(target_out_romfs) stamp-rootfs

.PHONY += install
include mk/flash.mak
install: $(TARGETS)
	$(shell ${FLASH_CMD})

.PHONY += clean
clean: clean-uboot clean-kernel clean-rootfs
	rm -rf $(target_out)

.PHONY += distclean
distclean: clean
	rm -rf $(uboot_dir) $(kernel_dir) $(busybox_dir) $(download_dir)

.PHONY += help
help:
	@echo "Avaialble commands:"
	@echo
	@echo "build the u-boot:"
	@echo "    make build-uboot; make clean-uboot"
	@echo
	@echo "build the Linux kernel:"
	@echo "    make build-kernel; make clean-kernel"
	@echo
	@echo "build the root file system:"
	@echo "    make build-rootfs; make clean-rootfs"
	@echo
	@echo "clean the targets:"
	@echo "    make clean"
	@echo
	@echo "flash images to STM32F429 Discovery"
	@echo "    make install"
