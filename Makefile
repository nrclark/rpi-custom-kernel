WORK_FOLDER := linux
KERNEL_CONFIG := kernel_config

TAG := raspberrypi-kernel_1.20170303-1
REPO := https://github.com/raspberrypi/linux
CROSS_MAKE := KERNEL=kernel7 make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-

defconfig: bcm2709_defconfig

$(WORK_FOLDER):
	if [ -d $@ ]; then \
		cd $@ && rm -rf * .git; \
	fi
	git clone $(REPO) $@ --branch $(TAG) --depth 1

$(WORK_FOLDER)/.config: $(KERNEL_CONFIG) $(WORK_FOLDER)
	cp -a $< $@

save: $(WORK_FOLDER)/.config
	cp $< $(KERNEL_CONFIG)

build: zImage modules dtbs

bcm2709_defconfig zImage modules \
dtbs clean:: $(WORK_FOLDER)
	cd $(WORK_FOLDER) && $(CROSS_MAKE) $@

menuconfig:: $(WORK_FOLDER)
	cd $(WORK_FOLDER) && $(CROSS_MAKE) $@
	cp -a $(WORK_FOLDER)/.config $(KERNEL_CONFIG)

distclean:
	rm -rf $(WORK_FOLDER)
