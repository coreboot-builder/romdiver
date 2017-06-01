SHELL=/bin/bash
TOOLS_DIR = $(PWD)/bin
UBUNTU_PACKAGES = automake autoconf make qt4-qmake build-essential libpci-dev libqt4-dev python3
FEDORA_PACKAGES = qt-devel automake autoconf make python3 pciutils-devel
MAKE_DIRS	= tools/fcode-utils tools/flashrom/util/ich_descriptors_tool tools/bios_extract
QMAKE_DIRS = tools/uefitool/UEFIExtract tools/uefitool/UEFIFind
MAKE_TOOLS =  ich_descriptors_tool romheaders bios_extract
QMAKE_TOOLS = UEFIExtract
BIN_TOOLS = tools/me-cleaner/me_cleaner.py tools/bios_extract/phoenix_extract.py

OS := $(shell gawk -F= '/^NAME/{print $2}' /etc/os-release)

all: deps submodules utils

submodules:
	git submodule update --checkout --init;

deps:
	if [ "$(OS)" = "NAME=Ubuntu" ]; then \
		sudo apt-get --yes --force-yes install $(UBUNTU_PACKAGES); \
	elif [ "$(OS)" = "NAME=Fedora" ]; then \
		sudo dnf install -y @development-tools; \
		sudo dnf install -y $(FEDORA_PACKAGES); \
	fi

utils:
	mkdir $(TOOLS_DIR) || true
	-for d in $(MAKE_DIRS); do ( \
		cd $$d; $(MAKE); \
		for t in $(MAKE_TOOLS); do ( \
			find . -name $$t -type f -exec cp {} $(TOOLS_DIR)/$${t,,} \; \
		); done \
	); done
	-for d in $(QMAKE_DIRS); do ( \
		cd $$d; qmake . && $(MAKE); \
		for t in $(QMAKE_TOOLS); do ( \
			find . -name $$t -type f -exec cp {} $(TOOLS_DIR)/$${t,,} \; \
		); done \
	); done
	-for t in $(BIN_TOOLS); do ( \
		if [ -f $$t ] ; then \
			cp $$t $(TOOLS_DIR)/${$(basename $$t),,}; \
		fi \
	); done

clean :
	rm -rf $(TOOLS_DIR)
	-for d in $(MAKE_DIRS); do (cd $$d; $(MAKE) clean ); done
	-for d in $(QMAKE_DIRS); do (cd $$d; $(MAKE) distclean ); done
