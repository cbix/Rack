ifndef ARCH_LIN
ifndef RACK_DIR
$(error RACK_DIR is not defined)
endif
else
RACK_DIR ?= /usr/share/vcvrack
endif

SLUG ?= $(shell jq -r .slug plugin.json)
VERSION ?= $(shell jq -r .version plugin.json)

ifndef SLUG
$(error SLUG could not be found in manifest)
endif
ifndef VERSION
$(error VERSION could not be found in manifest)
endif

DISTRIBUTABLES += plugin.json

FLAGS += -fPIC
FLAGS += -I$(RACK_DIR)/include -I$(RACK_DIR)/dep/include

LDFLAGS += -shared
# Plugins must link to libRack because when Rack is used as a plugin of another application, its symbols are not available to subsequently loaded shared libraries.
LDFLAGS += -L$(RACK_DIR) -lRack

include $(RACK_DIR)/arch.mk

TARGET := plugin

ifdef ARCH_LIN
	TARGET := $(TARGET).so
	# This prevents static variables in the DSO (dynamic shared object) from being preserved after dlclose().
	FLAGS += -fno-gnu-unique
	# Installed includes
	FLAGS += -I/usr/include/vcvrack -I/usr/include/vcvrack/dep
	# Link shared libs
	LDFLAGS += -ldl
	XDG_DATA_HOME ?= $(HOME)/.local/share
	RACK_USER_DIR ?= $(XDG_DATA_HOME)/Rack2
endif

ifdef ARCH_MAC
	TARGET := $(TARGET).dylib
	LDFLAGS += -undefined dynamic_lookup
	RACK_USER_DIR ?= $(HOME)/Library/Application Support/Rack2
	CODESIGN ?= codesign -f -s -
endif

ifdef ARCH_WIN
	TARGET := $(TARGET).dll
	LDFLAGS += -static-libstdc++
	RACK_USER_DIR ?= $(LOCALAPPDATA)/Rack2
endif

PLUGINS_DIR := $(RACK_USER_DIR)/plugins-$(ARCH_OS)-$(ARCH_CPU)

DEP_FLAGS += -fPIC
include $(RACK_DIR)/dep.mk


all: $(TARGET)

include $(RACK_DIR)/compile.mk

clean:
	rm -rfv build $(TARGET) dist

ZSTD_COMPRESSION_LEVEL ?= 19

dist: all
	rm -rf dist
	mkdir -p dist/$(SLUG)
	@# Strip symbols from binary
	cp $(TARGET) dist/$(SLUG)/
ifdef ARCH_MAC
	$(STRIP) -S dist/$(SLUG)/$(TARGET)
	$(INSTALL_NAME_TOOL) -change libRack.dylib /tmp/Rack2/libRack.dylib dist/$(SLUG)/$(TARGET)
	$(OTOOL) -L dist/$(SLUG)/$(TARGET)
else
	$(STRIP) -s dist/$(SLUG)/$(TARGET)
endif
	@# Sign binary if CODESIGN is defined
ifdef CODESIGN
	$(CODESIGN) dist/$(SLUG)/$(TARGET)
endif
	@# Copy distributables
ifdef ARCH_MAC
	rsync -rR $(DISTRIBUTABLES) dist/$(SLUG)/
else
	cp -r --parents $(DISTRIBUTABLES) dist/$(SLUG)/
endif
	@# Create ZIP package
	cd dist && tar -c $(SLUG) | zstd -$(ZSTD_COMPRESSION_LEVEL) -o "$(SLUG)"-"$(VERSION)"-$(ARCH_NAME).vcvplugin

install: dist
	mkdir -p "$(PLUGINS_DIR)"
	cp dist/*.vcvplugin "$(PLUGINS_DIR)"/

.PHONY: clean dist
.DEFAULT_GOAL := all
