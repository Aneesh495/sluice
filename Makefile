.DEFAULT_GOAL := all
SHELL := /bin/sh
CC := xcrun clang
BUILD ?= build
SDK := $(shell xcrun --show-sdk-path)
INCLUDES := $(addprefix -I,$(wildcard Sources/*)) -ITests/Unit
CFLAGS := -std=gnu11 -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -g -O2 -mmacosx-version-min=13.0 -isysroot $(SDK) $(INCLUDES) $(EXTRA_FLAGS)
LDFLAGS := -framework Foundation -lsqlite3 $(EXTRA_FLAGS)
CORE := $(shell find Sources -name '*.m' ! -path 'Sources/CLI/*' ! -path 'Sources/App/*' | sort)
OBJECTS := $(patsubst %.m,$(BUILD)/%.o,$(CORE))
TESTS := $(wildcard Tests/Unit/*.m)
.PHONY: all test clean sanitize FORCE
FORCE:
all: $(BUILD)/sluice
$(BUILD)/%.o: %.m FORCE
	@mkdir -p $(@D)
	@python3 scripts/compile.py $@ $< $(CC) $(CFLAGS)
$(BUILD)/unit: $(OBJECTS) $(TESTS) FORCE
	$(CC) $(CFLAGS) $(TESTS) $(OBJECTS) $(LDFLAGS) -o $@
test: $(BUILD)/unit
	$(BUILD)/unit
sanitize:
	$(MAKE) BUILD=build/sanitize EXTRA_FLAGS='-fsanitize=address,undefined -fno-omit-frame-pointer -O1' test
clean:
	rm -rf build

$(BUILD)/sluice: $(OBJECTS) Sources/CLI/main.m FORCE
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) Sources/CLI/main.m $(OBJECTS) $(LDFLAGS) -o $@
.PHONY: integration
integration: $(BUILD)/sluice
	SLUICE_BINARY=$(abspath $(BUILD)/sluice) python3 Tests/Integration/test_workbench.py
APP_SOURCES := $(wildcard Sources/App/*.m)
.PHONY: app
app: $(BUILD)/Sluice.app/Contents/MacOS/Sluice
$(BUILD)/Sluice.app/Contents/MacOS/Sluice: $(OBJECTS) $(APP_SOURCES) Sources/App/Info.plist FORCE
	@mkdir -p $(@D)
	$(CC) $(CFLAGS) $(APP_SOURCES) $(OBJECTS) $(LDFLAGS) -framework AppKit -o $@
	cp Sources/App/Info.plist $(BUILD)/Sluice.app/Contents/Info.plist
