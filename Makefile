SRC_FOLDER := linux
TOOL_FOLDER := tools/compiler
KERNEL_CONFIG := kernel-4.10.8_config
SSH_USER := pi
SSH_HOST := donk

TOOL_REPO := https://github.com/raspberrypi/tools
SRC_REPO := https://github.com/raspberrypi/linux

# At the time of this writing, the most recently-released stable kernel is tagged
# 'raspberrypi-kernel_1.20170303-1' in the Pi's kernel repo. SRC_TAG can be given a
# branch name, commit SHA, or a particular tag.

SRC_TAG := rpi-4.10.y

CROSS_MAKE := KERNEL=kernel7 $(MAKE) -C $(SRC_FOLDER) ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-
NCPUS := $(shell grep -c ^processor /proc/cpuinfo)

CC_PATH := $(abspath $(TOOL_FOLDER)/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian-x64/bin)
TOOL_CC := $(CC_PATH)/arm-linux-gnueabihf-gcc
NEW_PATH := $(CC_PATH):$(PATH)
export PATH = $(NEW_PATH)

MODULE_TEMP := temp.modules
HEADER_TEMP := temp.headers
BOOT_TEMP := temp.boot

.PHONY: tools
tools: $(TOOL_CC)

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
	git clone $(SRC_REPO) $(dir $@) --branch $(SRC_TAG) --depth 1

$(SRC_FOLDER)/.config: $(KERNEL_CONFIG) $(SRC_FOLDER)/Makefile
	cp $< $@

.PHONY: save
save: $(SRC_FOLDER)/.config
	cp $< $(KERNEL_CONFIG)

.PHONY: build
build: _build.done
_build.done: $(SRC_FOLDER)/.config $(TOOL_CC)
	$(CROSS_MAKE) zImage modules dtbs -j$(NCPUS)
	touch _build.done

clean:
	if [ -e $(SRC_FOLDER)/Makefile ]; then \
		$(CROSS_MAKE) clean; \
	fi
	rm -f install.sh src.tar.gz modules.tar.gz boot.tar.gz
	rm -f _build.done fileset.txt
	rm -rf $(MODULE_TEMP)
	rm -rf $(HEADER_TEMP)
	rm -rf $(BOOT_TEMP)

defconfig:
	$(CROSS_MAKE) bcm2709_defconfig
	cp $(SRC_FOLDER)/.config $(KERNEL_CONFIG)

xconfig menuconfig nconfig oldconfig: $(SRC_FOLDER)/.config
	$(CROSS_MAKE) $@
	cp $(SRC_FOLDER)/.config $(KERNEL_CONFIG)
	touch -c $(SRC_FOLDER)/.config $(KERNEL_CONFIG)

distclean: clean
	if [ -e $(SRC_FOLDER)/Makefile ]; then \
		$(CROSS_MAKE) distclean; \
	fi

install.sh: install.sh.template _build.done
	RELEASE=$$(cat $(SRC_FOLDER)/include/config/kernel.release) && \
	sed "s/%RELEASE_STRING%/$$RELEASE/g" $< > $@
	chmod 755 $@

prep: install.sh src.tar.gz modules.tar.gz boot.tar.gz

install: install.sh src.tar.gz modules.tar.gz boot.tar.gz
	TEMPDIR=$$(ssh $(SSH_USER)@$(SSH_HOST) mktemp -d) && \
	scp $^ $(SSH_USER)@$(SSH_HOST):$$TEMPDIR && \
	ssh $(SSH_USER)@$(SSH_HOST) "cd $$TEMPDIR && sudo ./install.sh" && \
	ssh $(SSH_USER)@$(SSH_HOST) "rm -rf $$TEMPDIR"

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

fileset.txt: _build.done
	rm -f fileset.txt*
	find $(SRC_FOLDER) -type f | grep -Pv "[.]git" | grep -Pv "[.]tmp_versions" > fileset.txt.1
	cat fileset.txt.1 | tr '\n' '\00' | xargs -0 -n8 -P4 file > fileset.txt.2
	grep "ELF" fileset.txt.2 > fileset.txt.elf.3
	grep -v "ELF" fileset.txt.2 > fileset.txt.noelf.3
	grep "/scripts/" fileset.txt.elf.3 | grep -v "x86" > fileset.txt.4
	cat fileset.txt.noelf.3 >> fileset.txt.4
	cat fileset.txt.4 | sed -r 's@^$(SRC_FOLDER)/@@g' | sed -r 's/[:].*//g' > $@
	rm -f fileset.txt.*

src.tar.gz: fileset.txt
	RELEASE=$$(cat $(SRC_FOLDER)/include/config/kernel.release) && \
	cd $(SRC_FOLDER) && \
	tar zcf $(abspath $@) \
		-T $(abspath $<) \
		--transform="s,^,/usr/src/linux-headers-$$RELEASE/,S" \
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

reboot:
	ssh $(SSH_USER)@$(SSH_HOST) sudo reboot || true
