SHELL=/bin/bash
TOOLS_DIR = $(PWD)/bin
PACKAGES = automake autoconf make qt4-qmake build-essential libpci-dev libqt4-dev python3 firejail
MAKE_DIRS	= tools/fcode-utils tools/flashrom/util/ich_descriptors_tool
QMAKE_DIRS = tools/uefitool/UEFIExtract tools/uefitool/UEFIFind
MAKE_TOOLS =  ich_descriptors_tool romheaders
QMAKE_TOOLS = UEFIExtract UEFIFind
BIN_TOOLS = tools/me-cleaner/me_cleaner.py

all :  utils

deps : sudo apt-get install $(PACKAGES)

utils :
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
	-for d in $(CMAKE_DIRS); do (cd $$d; $(MAKE) clean ); done
