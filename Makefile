ARCH := $(shell uname -m)
SDK := $(shell xcrun --sdk macosx --show-sdk-path)
TARGET := $(ARCH)-apple-macos13.0
BUILD_DIR := .build/release
MODULE_CACHE := /tmp/tabswipe-module-cache

.PHONY: build test install uninstall clean

build:
	@mkdir -p $(BUILD_DIR) $(MODULE_CACHE)
	swiftc -O -whole-module-optimization \
		-emit-module -emit-module-path $(BUILD_DIR)/TabSwipeCore.swiftmodule \
		-emit-object -parse-as-library \
		-module-name TabSwipeCore \
		-module-cache-path $(MODULE_CACHE) \
		-sdk $(SDK) -target $(TARGET) \
		Sources/TabSwipeCore/*.swift \
		-o $(BUILD_DIR)/TabSwipeCore.o
	swiftc -O \
		-module-cache-path $(MODULE_CACHE) \
		-sdk $(SDK) -target $(TARGET) \
		-I $(BUILD_DIR) \
		Sources/tabswipe/*.swift $(BUILD_DIR)/TabSwipeCore.o \
		-o $(BUILD_DIR)/tabswipe
	@echo "Built $(BUILD_DIR)/tabswipe"

test: build
	@if xcodebuild -version >/dev/null 2>&1; then \
		swift test; \
	else \
		swiftc \
			-module-cache-path $(MODULE_CACHE) \
			-sdk $(SDK) -target $(TARGET) \
			-I $(BUILD_DIR) \
			Tests/StandaloneRunner.swift $(BUILD_DIR)/TabSwipeCore.o \
			-o $(BUILD_DIR)/tabswipe-tests && \
		$(BUILD_DIR)/tabswipe-tests; \
	fi

install: build
	$(BUILD_DIR)/tabswipe install

uninstall:
	@if [ -x "$(HOME)/.local/bin/tabswipe" ]; then \
		"$(HOME)/.local/bin/tabswipe" uninstall; \
	elif [ -x "$(BUILD_DIR)/tabswipe" ]; then \
		$(BUILD_DIR)/tabswipe uninstall; \
	else \
		echo "TabSwipe binary not found."; \
	fi

clean:
	rm -rf .build
