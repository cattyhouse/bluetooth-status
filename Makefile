SHELL := /bin/sh

SWIFT := $(shell xcrun --find swiftc)
SDK := $(shell xcrun --sdk macosx --show-sdk-path)
TARGET_ARCH ?= $(shell uname -m)
TARGET := $(TARGET_ARCH)-apple-macosx13.0
BUILD_DIR := build
APP := $(BUILD_DIR)/BluetoothStatus.app
BIN := $(APP)/Contents/MacOS/BluetoothStatus
TEST_BIN := $(BUILD_DIR)/status-logic-tests
LAUNCH_AGENT_LABEL := com.justin.bluetoothstatus
LAUNCH_AGENT_DOMAIN := gui/$(shell id -u)

SOURCES := \
	Sources/BluetoothReader.swift \
	Sources/AppDelegate.swift \
	Sources/StatusLogic.swift \
	Sources/RefreshCoordinator.swift \
	Sources/main.swift

TEST_SOURCES := \
	Sources/StatusLogic.swift \
	Sources/RefreshCoordinator.swift \
	Tests/StatusLogicTests.swift

SWIFT_FLAGS := -swift-version 5 -O -warnings-as-errors -sdk "$(SDK)" -target $(TARGET)

.PHONY: all test dump run install install-login-item uninstall uninstall-login-item login-item-status clean

all: $(BIN)

$(BIN): $(SOURCES) Info.plist
	@rm -rf "$(APP)"
	@mkdir -p "$(APP)/Contents/MacOS"
	@cp Info.plist "$(APP)/Contents/Info.plist"
	$(SWIFT) $(SWIFT_FLAGS) -framework AppKit -framework Foundation -framework IOBluetooth $(SOURCES) -o "$(BIN)"

test: $(TEST_BIN)
	@sh -n scripts/install.sh
	@sh -n scripts/uninstall.sh
	@sh -n Tests/install-rollback-test.sh
	@"$(TEST_BIN)"
	@sh Tests/install-rollback-test.sh

$(TEST_BIN): $(TEST_SOURCES)
	@mkdir -p "$(BUILD_DIR)"
	$(SWIFT) $(SWIFT_FLAGS) -parse-as-library -framework Foundation $(TEST_SOURCES) -o "$(TEST_BIN)"

dump: $(BIN)
	@"$(BIN)" --dump

run: $(BIN)
	@open "$(APP)"

install: all
	@sh scripts/install.sh

# Compatibility alias: installing the login item now also installs the app.
install-login-item: install

uninstall-login-item:
	@sh scripts/uninstall.sh

uninstall:
	@sh scripts/uninstall.sh --remove-app

login-item-status:
	@launchctl print "$(LAUNCH_AGENT_DOMAIN)/$(LAUNCH_AGENT_LABEL)"

clean:
	@rm -rf "$(BUILD_DIR)"
