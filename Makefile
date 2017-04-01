WORK_FOLDER := linux
KERNEL_CONFIG := kernel_config
SSH_USER := pi
SSH_HOST := donk

TAG := raspberrypi-kernel_1.20170303-1
REPO := https://github.com/raspberrypi/linux
CROSS_MAKE := KERNEL=kernel7 $(MAKE) -C $(WORK_FOLDER) ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf-
NCPUS := $(shell grep -c ^processor /proc/cpuinfo)

defconfig: bcm2709_defconfig

test:
	echo $(MAKE_FLAGS)

$(WORK_FOLDER):
	if [ -d $@ ]; then \
		cd $@ && rm -rf * .git; \
	fi
	git clone $(REPO) $@ --branch $(TAG) --depth 1

$(WORK_FOLDER)/.config: $(KERNEL_CONFIG) $(WORK_FOLDER)
	cp -a $< $@

save: $(WORK_FOLDER)/.config
	cp $< $(KERNEL_CONFIG)

build: $(WORK_FOLDER)/.config
	$(CROSS_MAKE) zImage modules dtbs -j$(NCPUS)

clean: $(WORK_FOLDER)
	$(CROSS_MAKE) clean

menuconfig: $(WORK_FOLDER)/.config
	cd $(WORK_FOLDER) && $(CROSS_MAKE) menuconfig
	cp -a $(WORK_FOLDER)/.config $(KERNEL_CONFIG)

distclean:
	rm -rf $(WORK_FOLDER)

INSTALL_ROOT := temp

install:
	mkdir -p $(INSTALL_ROOT)
	rm -rf $(INSTALL_ROOT)/*
	$(CROSS_MAKE) INSTALL_MOD_PATH=$(abspath $(INSTALL_ROOT)) modules_install
	RELEASE=$$(cat $(WORK_FOLDER)/include/config/kernel.release) && \
	TEMPDIR=$$(ssh $(SSH_USER)@$(SSH_HOST) mktemp -d) && \
			ssh $(SSH_USER)@$(SSH_HOST) mkdir -p $$TEMPDIR/boot && \
			ssh $(SSH_USER)@$(SSH_HOST) mkdir -p $$TEMPDIR/boot && \
			ssh $(SSH_USER)@$(SSH_HOST) mkdir -p $$TEMPDIR/boot/overlays && \
			rsync -avh --progress $(WORK_FOLDER)/arch/arm/boot/zImage $(SSH_USER)@$(SSH_HOST):$$TEMPDIR/boot/kernel-$$RELEASE.img && \
			rsync -avh --progress $(WORK_FOLDER)/arch/arm/boot/dts/*.dtb $(SSH_USER)@$(SSH_HOST):$$TEMPDIR/boot && \
			rsync -avh --progress $(WORK_FOLDER)/arch/arm/boot/dts/overlays/*.dtb* $(SSH_USER)@$(SSH_HOST):$$TEMPDIR/boot/overlays && \
			rsync -avh --progress $(WORK_FOLDER)/arch/arm/boot/dts/overlays/README $(SSH_USER)@$(SSH_HOST):$$TEMPDIR/boot/overlays && \
			rsync -avh --progress $(INSTALL_ROOT)/* $(SSH_USER)@$(SSH_HOST):$$TEMPDIR && \
			ssh $(SSH_USER)@$(SSH_HOST) sudo cp -r $$TEMPDIR/* / && \
			ssh $(SSH_USER)@$(SSH_HOST) rm -rf $$TEMPDIR && \
			ssh $(SSH_USER)@$(SSH_HOST) sudo sed -ri '/^kernel[=]/d' /boot/config.txt && \
			ssh $(SSH_USER)@$(SSH_HOST) "echo 'kernel=kernel-$$RELEASE.img' | sudo tee -a /boot/config.txt"



#scp -qr $(INSTALL_ROOT)/* $(SSH_USER)@$(SSH_HOST):$$TEMPDIR
