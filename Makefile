.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS += -e

KERNEL_ABI_MINOR_VERSION = 2
KVERSION_SHORT ?= 4.9.0-8-$(KERNEL_ABI_MINOR_VERSION)
KVERSION ?= $(KVERSION_SHORT)-amd64
KERNEL_VERSION ?= 4.9.110
KERNEL_SUBVERSION ?= 3+deb9u6
kernel_procure_method ?= build

LINUX_HEADER_COMMON = linux-headers-$(KVERSION_SHORT)-common_$(KERNEL_VERSION)-$(KERNEL_SUBVERSION)_all.deb
LINUX_HEADER_AMD64 = linux-headers-$(KVERSION)_$(KERNEL_VERSION)-$(KERNEL_SUBVERSION)_amd64.deb
LINUX_IMAGE = linux-image-$(KVERSION)_$(KERNEL_VERSION)-$(KERNEL_SUBVERSION)_amd64.deb

MAIN_TARGET = $(LINUX_HEADER_COMMON)
DERIVED_TARGETS = $(LINUX_HEADER_AMD64) $(LINUX_IMAGE)

ifneq ($(kernel_procure_method), build)
# Downloading kernel


LINUX_HEADER_COMMON_URL = "https://sonicstorage.blob.core.windows.net/packages/kernel-public/linux-headers-$(KVERSION_SHORT)-common_$(KERNEL_VERSION)-$(KERNEL_SUBVERSION)_all.deb?sv=2015-04-05&sr=b&sig=LlKqKecY6MDSwFMTxpKErh7FX1Lrvse2yVt3niYnhds%3D&se=2128-02-24T04%3A47%3A48Z&sp=r"

LINUX_HEADER_AMD64_URL = "https://sonicstorage.blob.core.windows.net/packages/kernel-public/linux-headers-$(KVERSION_SHORT)-amd64_$(KERNEL_VERSION)-$(KERNEL_SUBVERSION)_amd64.deb?sv=2015-04-05&sr=b&sig=SfQLjiBPPMcRUOmBPvXq2%2F6SsW3ul9%2FlaROplXdGij0%3D&se=2128-02-24T04%3A48%3A38Z&sp=r"

LINUX_IMAGE_URL = "https://sonicstorage.blob.core.windows.net/packages/kernel-public/linux-image-$(KVERSION_SHORT)-amd64_$(KERNEL_VERSION)-$(KERNEL_SUBVERSION)_amd64.deb?sv=2015-04-05&sr=b&sig=PNKGpLjELZem0IacUMM1jU%2Ft5ujoVvUb9JzxrUhE1Wk%3D&se=2128-02-24T04%3A48%3A57Z&sp=r"

$(addprefix $(DEST)/, $(MAIN_TARGET)): $(DEST)/% :
	# Obtaining the Debian kernel packages
	rm -rf $(BUILD_DIR)
	wget --no-use-server-timestamps -O $(LINUX_HEADER_COMMON) $(LINUX_HEADER_COMMON_URL)
	wget --no-use-server-timestamps -O $(LINUX_HEADER_AMD64) $(LINUX_HEADER_AMD64_URL)
	wget --no-use-server-timestamps -O $(LINUX_IMAGE) $(LINUX_IMAGE_URL)

ifneq ($(DEST),)
	mv $(DERIVED_TARGETS) $* $(DEST)/
endif

$(addprefix $(DEST)/, $(DERIVED_TARGETS)): $(DEST)/% : $(DEST)/$(MAIN_TARGET)

else
# Building kernel

DSC_FILE = linux_$(KERNEL_VERSION)-$(KERNEL_SUBVERSION).dsc
ORIG_FILE = linux_$(KERNEL_VERSION).orig.tar.xz
DEBIAN_FILE = linux_$(KERNEL_VERSION)-$(KERNEL_SUBVERSION).debian.tar.xz
URL = http://security.debian.org/debian-security/pool/updates/main/l/linux
BUILD_DIR=linux-$(KERNEL_VERSION)

DSC_FILE_URL = "$(URL)/$(DSC_FILE)"
DEBIAN_FILE_URL = "$(URL)/$(DEBIAN_FILE)"
ORIG_FILE_URL = "$(URL)/$(ORIG_FILE)"

$(addprefix $(DEST)/, $(MAIN_TARGET)): $(DEST)/% :
	# Obtaining the Debian kernel source
	rm -rf $(BUILD_DIR)
	wget -O $(DSC_FILE) $(DSC_FILE_URL)
	wget -O $(ORIG_FILE) $(ORIG_FILE_URL)
	wget -O $(DEBIAN_FILE) $(DEBIAN_FILE_URL)

	dpkg-source -x $(DSC_FILE)

	pushd $(BUILD_DIR)
	git init
	git add -f *
	git commit -qm "check in all loose files and diffs"

	# patching anything that could affect following configuration generation.
	stg init
	stg import -s ../patch/preconfig/series

	# re-generate debian/rules.gen, requires kernel-wedge
	debian/bin/gencontrol.py

	# generate linux build file for amd64_none_amd64
	fakeroot make -f debian/rules.gen setup_amd64_none_amd64

	# Applying patches and configuration changes
	git add debian/build/build_amd64_none_amd64/.config -f
	git add debian/config.defines.dump -f
	git add debian/control -f
	git add debian/rules.gen -f
	git add debian/tests/control -f
	git commit -m "unmodified debian source"

	# Learning new git repo head (above commit) by calling stg repair.
	stg repair
	stg import -s ../patch/series

	# Building a custom kernel from Debian kernel source
	DO_DOCS=False fakeroot make -f debian/rules -j $(shell nproc) binary-indep
	fakeroot make -f debian/rules.gen -j $(shell nproc) binary-arch_amd64_none
	popd

ifneq ($(DEST),)
	mv $(DERIVED_TARGETS) $* $(DEST)/
endif

$(addprefix $(DEST)/, $(DERIVED_TARGETS)): $(DEST)/% : $(DEST)/$(MAIN_TARGET)

endif # building kernel
