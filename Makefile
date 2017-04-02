SRC_FOLDER := linux
TOOL_FOLDER := tools/compiler
KERNEL_CONFIG := kernel_config
SSH_USER := pi
SSH_HOST := donk

TOOL_REPO := https://github.com/raspberrypi/tools
SRC_REPO := https://github.com/raspberrypi/linux
SRC_TAG := raspberrypi-kernel_1.20170303-1

CROSS_MAKE := KERNEL=kernel7 $(MAKE) -C $(SRC_FOLDER) ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-
NCPUS := $(shell grep -c ^processor /proc/cpuinfo)

CC_PATH := $(abspath $(TOOL_FOLDER)/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian-x64/bin)
TOOL_CC := $(CC_PATH)/arm-linux-gnueabihf-gcc
NEW_PATH := $(CC_PATH):$(PATH)
export PATH = $(NEW_PATH)

.PHONY: tools
tools: $(TOOL_CC)

test:
	echo $(TOOL_CC)

$(TOOL_CC):
	if [ -d $@ ]; then \
		cd $@ && rm -rf * .*; \
	fi
	mkdir -p $@
	git clone --depth 1 $(TOOL_REPO) $@

$(SRC_FOLDER)/Makefile:
	if [ -d $@ ]; then \
		cd $@ && rm -rf * .git; \
	fi
	git clone $(SRC_REPO) $@ --branch $(SRC_TAG) --depth 1

$(SRC_FOLDER)/.config: $(KERNEL_CONFIG) $(SRC_FOLDER)/Makefile
	cp $< $@

save: $(SRC_FOLDER)/.config
	cp $< $(KERNEL_CONFIG)

build: _build.done
_build.done: $(SRC_FOLDER)/.config $(TOOL_CC)
	$(CROSS_MAKE) zImage modules dtbs -j$(NCPUS)
	touch _build.done

clean: $(SRC_FOLDER)
	$(CROSS_MAKE) clean

menuconfig: $(SRC_FOLDER)/.config
	$(CROSS_MAKE) menuconfig
	cp $(SRC_FOLDER)/.config $(KERNEL_CONFIG)
	touch -c $(SRC_FOLDER)/.config $(KERNEL_CONFIG)

distclean:
	$(CROSS_MAKE) distclean

MODULE_TEMP := temp.modules
HEADER_TEMP := temp.headers
BOOT_TEMP := temp.boot

install.sh: install.sh.template _build.done
	RELEASE=$$(cat $(SRC_FOLDER)/include/config/kernel.release) && \
	sed "s/%RELEASE_STRING%/$$RELEASE/g" $< > $@
	chmod 755 $@

newinstall: install.sh src.tar.gz modules.tar.gz boot.tar.gz
	TEMPDIR=$$(ssh $(SSH_USER)@$(SSH_HOST) mktemp -d) && \
	scp $^ $(SSH_USER)@$(SSH_HOST):$$TEMPDIR && \
	ssh $(SSH_USER)@$(SSH_HOST) "cd $$TEMPDIR && sudo ./install.sh" && \
	ssh $(SSH_USER)@$(SSH_HOST) "rm -rf $$TEMPDIR"

install: _build.done
	mkdir -p $(MODULE_TEMP)
	rm -rf $(MODULE_TEMP)/*
	$(CROSS_MAKE) INSTALL_MOD_PATH=$(abspath $(MODULE_TEMP)) modules_install
	RELEASE=$$(cat $(SRC_FOLDER)/include/config/kernel.release) && \
	TEMPDIR=$$(ssh $(SSH_USER)@$(SSH_HOST) mktemp -d) && \
			ssh $(SSH_USER)@$(SSH_HOST) mkdir -p $$TEMPDIR/boot && \
			ssh $(SSH_USER)@$(SSH_HOST) mkdir -p $$TEMPDIR/boot && \
			ssh $(SSH_USER)@$(SSH_HOST) mkdir -p $$TEMPDIR/boot/overlays && \
			rsync -avh --progress $(SRC_FOLDER)/arch/arm/boot/zImage $(SSH_USER)@$(SSH_HOST):$$TEMPDIR/boot/kernel-$$RELEASE.img && \
			rsync -avh --progress $(SRC_FOLDER)/arch/arm/boot/dts/*.dtb $(SSH_USER)@$(SSH_HOST):$$TEMPDIR/boot && \
			rsync -avh --progress $(SRC_FOLDER)/arch/arm/boot/dts/overlays/*.dtb* $(SSH_USER)@$(SSH_HOST):$$TEMPDIR/boot/overlays && \
			rsync -avh --progress $(SRC_FOLDER)/arch/arm/boot/dts/overlays/README $(SSH_USER)@$(SSH_HOST):$$TEMPDIR/boot/overlays && \
			rsync -avh --progress $(MODULE_TEMP)/* $(SSH_USER)@$(SSH_HOST):$$TEMPDIR && \
			ssh $(SSH_USER)@$(SSH_HOST) sudo cp -r $$TEMPDIR/* / && \
			ssh $(SSH_USER)@$(SSH_HOST) rm -rf $$TEMPDIR && \
			ssh $(SSH_USER)@$(SSH_HOST) sudo sed -ri '/^kernel[=]/d' /boot/config.txt && \
			ssh $(SSH_USER)@$(SSH_HOST) "echo 'kernel=kernel-$$RELEASE.img' | sudo tee -a /boot/config.txt"

src.tar.gz: _build.done
	RELEASE=$$(cat $(SRC_FOLDER)/include/config/kernel.release) && \
	tar \
		--exclude='$(SRC_FOLDER)/.git' \
		-zcf $@ $(SRC_FOLDER) \
		--transform="s,^$(SRC_FOLDER),/usr/src/linux-headers-$$RELEASE,S" \
		--group=0 \
		--owner=0

modules.tar.gz: _build.done
	mkdir -p $(MODULE_TEMP)
	rm -rf $(MODULE_TEMP)/*
	$(CROSS_MAKE) INSTALL_MOD_PATH=$(abspath $(MODULE_TEMP)) modules_install
	RELEASE=$$(cat $(SRC_FOLDER)/include/config/kernel.release) && \
	unlink $(MODULE_TEMP)/lib/modules/$$RELEASE/source && \
	ln -s /usr/src/linux-headers-$$RELEASE $(MODULE_TEMP)/lib/modules/$$RELEASE/source && \
	unlink $(MODULE_TEMP)/lib/modules/$$RELEASE/build && \
	ln -s /usr/src/linux-headers-$$RELEASE $(MODULE_TEMP)/lib/modules/$$RELEASE/build
	tar \
		-zcf $@ $(MODULE_TEMP) \
		--transform="s,^$(MODULE_TEMP),,S" \
		--group=0 \
		--owner=0

boot.tar.gz: _build.done
	mkdir -p $(BOOT_TEMP)
	rm -rf $(BOOT_TEMP)/*
	mkdir -p $(BOOT_TEMP)/boot/overlays
	RELEASE=$$(cat $(SRC_FOLDER)/include/config/kernel.release) && \
	cp $(SRC_FOLDER)/arch/arm/boot/zImage $(BOOT_TEMP)/boot/kernel-$$RELEASE.img
	cp $(SRC_FOLDER)/arch/arm/boot/dts/*.dtb $(BOOT_TEMP)/boot
	cp $(SRC_FOLDER)/arch/arm/boot/dts/overlays/*.dtb* $(BOOT_TEMP)/boot/overlays
	cp $(SRC_FOLDER)/arch/arm/boot/dts/overlays/README $(BOOT_TEMP)/boot/overlays
	tar \
		-zcf $@ $(BOOT_TEMP) \
		--transform="s,^$(BOOT_TEMP),,S" \
		--group=0 \
		--owner=0

lxterminal:
	nohup ssh -X $(SSH_USER)@$(SSH_HOST) lxterminal 1>/dev/null 2>&1 &
