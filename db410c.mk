# This makefile expects the following variables to be set:
#
# DOWNLOAD_DIR: 	Used to store downloaded files
# TMP_DIR		Used to hold temporary files
# FIRMWARE_DEST_DIR 	Location to store downloaded firmware file
# ROOTFS_IMG		Location of rootfs image
# BOOT_IMG		Location of boot image
# IMAGE			Location of Linux kernel image
# INITRD		Location of initrd image
# DTB			Location of Device Tree Binary
#
# The skales repo is at: git://codeaurora.org/quic/kernel/skales
#
# Optional variables:
#
# DB410C_KERNEL		Directory for the kernel source
# SKALES		Location of cloned skales repository
#
# if BUILD_DEFAULT_KERNEL=1 then the following must be provided:
#
# KERNEL_CONFIG		Location of kernel config file
#
# if FIRMWARE_UNPACK_DIR is defined then the target _firmware-unpack
# will unpack the firmware to FIRMWARE_UNPACK_DIR
#
# The target _firmware will download provide instructions to
# dowload the firmware
#


ifeq ($(DOWNLOAD_DIR),)
$(error DOWNLOAD_DIR Undefined)
endif

ifeq ($(TMP_DIR),)
$(error TMP_DIR Undefined)
endif

ifeq ($(FIRMWARE_DEST_DIR),)
$(error FIRMWARE_DEST_DIR Undefined)
endif

ifeq ($(ROOTFS_IMG),)
$(error ROOTFS_IMG Undefined)
endif

ifeq ($(BOOT_IMG),)
$(error BOOT_IMG Undefined)
endif

ifeq ($(DTB),)
$(error DTB Undefined)
endif

ifeq ($(IMAGE),)
$(error IMAGE Undefined)
endif

INITRD:=$(DOWNLOAD_DIR)/initrd.img-4.0.0-linaro-lt-qcom
DB410C_KERNEL?=db410c-linux
KERNEL_VERSION?=origin/release/qcomlt-4.0
KERNEL_BRANCH:=_build_branch
SKALES?=skales

FIRMWARE_ZIP:=$(FIRMWARE_DEST_DIR)/linux-ubuntu-board-support-package-v1.zip

ifneq ($(FIRMWARE_UNPACK_DIR),)

$(FIRMWARE_UNPACK_DIR)/.unpacked: $(FIRMWARE_ZIP)
	mkdir -p $(FIRMWARE_UNPACK_DIR)
	[ -f $(DOWNLOAD_DIR)/proprietary-ubuntu-1.tgz ] || (cd $(DOWNLOAD_DIR) && unzip $(FIRMWARE_ZIP))
	[ -f $(FIRMWARE_UNPACK_DIR)/.unpacked ] || tar -C $(FIRMWARE_UNPACK_DIR) -xzpf $(DOWNLOAD_DIR)/proprietary-ubuntu-1.tgz --strip 1
	touch $@

endif

$(DOWNLOAD_DIR):
	mkdir -p $(DOWNLOAD_DIR)

$(TMP_DIR):
	mkdir -p $(TMP_DIR)

$(DOWNLOAD_DIR)/.exists: $(DOWNLOAD_DIR)
	@[ -f $@ ] || touch $@

$(TMP_DIR)/.exists: $(TMP_DIR)
	@[ -f $@ ] || touch $@

$(SKALES):
	@[ -d $@ ] || git clone git://codeaurora.org/quic/kernel/skales $(SKALES)

# Initrd image
$(INITRD): $(DOWNLOAD_DIR)/.exists
	@[ -f $@ ] || (cd $(DOWNLOAD_DIR) && wget http://builds.96boards.org/snapshots/dragonboard410c/linaro/ubuntu/latest/initrd.img-4.0.0-linaro-lt-qcom)

ifeq ($(BUILD_DEFAULT_KERNEL),1)

ifeq ($(KERNEL_CONFIG),)
$(error KERNEL_CONFIG Undefined)
endif

$(DB410C_KERNEL):
	@git clone -n git://git.linaro.org/landing-teams/working/qualcomm/kernel.git $@
	@(cd $@ && git checkout -b $(KERNEL_BRANCH) $(KERNEL_VERSION))

# Make the DB410c kernel
$(IMAGE) $(DTS): $(DB410C_KERNEL) $(KERNEL_CONFIG)
	@(cd $(DB410C_KERNEL) && git checkout $(KERNEL_BRANCH))
	@(cp $(KERNEL_CONFIG) $(DB410C_KERNEL)/.config)
	@(cd $(DB410C_KERNEL) && ARCH=arm64 make oldconfig)
	@(cd $(DB410C_KERNEL) && CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm64 make -j4 Image dtbs)
endif

# Required for dtbTool and mkbootimg
PATH:=$(SKALES):$(PATH)

# bootloader
$(DOWNLOAD_DIR)/dragonboard410c_bootloader_emmc_linux-40.zip: $(DOWNLOAD_DIR)/.exists
	@[ -f $@ ] || (cd $(DOWNLOAD_DIR) && wget http://builds.96boards.org/releases/dragonboard410c/linaro/rescue/15.06/dragonboard410c_bootloader_emmc_linux-40.zip)

$(TMP_DIR)/bootloader/flashall: $(DOWNLOAD_DIR)/dragonboard410c_bootloader_emmc_linux-40.zip 
	@mkdir -p $(TMP_DIR)/bootloader
	@cd $(TMP_DIR)/bootloader && unzip $(TOP)$<

setup-emmc: $(TMP_DIR)/bootloader/flashall 
	@cd $(TMP_DIR)/bootloader && sudo ./flashall

# Firmware for DB410C
$(FIRMWARE_ZIP): 
	@echo
	@echo "********************************************************************************************"
	@echo "* YOU NEED TO DOWNLOAD THE FIRMWARE FROM QDN"
	@echo "*"
	@echo "* Paste the following link in your browser:"
	@echo "*"
	@echo "*    https://developer.qualcomm.com/download/db410c/linux-ubuntu-board-support-package-v1.zip"
	@echo "*"
	@echo "* and after accepting the EULA, save the file to:"
	@echo "*"
	@echo "*    $@"
	@echo "*"
	@echo "* Afterward, retry running make"
	@echo "*"
	@echo "********************************************************************************************"
	@echo
	@false

$(TMP_DIR)/dt.img: $(TMP_DIR) $(DTB) $(SKALES)
	cp $(DTB) $(TMP_DIR)
	@dtbTool -o $@ -s 2048 $(TMP_DIR)

$(BOOT_IMG): $(IMAGE) $(INITRD) $(TMP_DIR)/dt.img $(SKALES)
	@mkbootimg --kernel $(IMAGE) \
          --ramdisk $(INITRD) \
          --output $(BOOT_IMG) \
          --dt $(TMP_DIR)/dt.img \
          --pagesize 2048 \
          --base 0x80000000 \
          --cmdline "root=/dev/disk/by-partlabel/rootfs rw rootwait console=tty0 console=ttyMSM0,115200n8"
	@echo "Built boot image: $@"

flash-bootimg: $(BOOT_IMG)
	sudo fastboot flash boot $<

flash-rootimg: $(ROOTFS_IMG)
	sudo fastboot flash rootfs $<

