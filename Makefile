.DEFAULT_GOAL := all
SHELL := /bin/sh
CC := xcrun clang
FUZZ_CC ?= $(shell if command -v brew >/dev/null 2>&1 && brew --prefix llvm >/dev/null 2>&1; then printf '%s/bin/clang' "$$(brew --prefix llvm)"; else xcrun --find clang; fi)
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
.PHONY: demo
demo: $(BUILD)/sluice
	python3 scripts/demo.py
.PHONY: fuzz
$(BUILD)/parser-fuzz: $(CORE) Tests/Fuzz/parser_fuzz.m FORCE
	@mkdir -p $(@D)
	$(FUZZ_CC) $(CFLAGS) -O1 -fsanitize=fuzzer,address,undefined $(CORE) Tests/Fuzz/parser_fuzz.m $(LDFLAGS) -o $@
fuzz: $(BUILD)/parser-fuzz
	@mkdir -p $(BUILD)/fuzz-corpus $(BUILD)/fuzz-artifacts
	cp Tests/Fuzz/seeds/* $(BUILD)/fuzz-corpus/
	$(BUILD)/parser-fuzz -seed=41501 -runs=20000 -max_len=4096 -timeout=3 -artifact_prefix=$(BUILD)/fuzz-artifacts/ $(BUILD)/fuzz-corpus
.PHONY: differential
$(BUILD)/parser-driver: $(OBJECTS) Tests/Differential/parser_driver.m FORCE
	$(CC) $(CFLAGS) Tests/Differential/parser_driver.m $(OBJECTS) $(LDFLAGS) -o $@
differential: $(BUILD)/parser-driver
	python3 Tests/Differential/test_parser.py
.PHONY: app-smoke
app-smoke: app
	python3 Tests/Integration/test_app.py
