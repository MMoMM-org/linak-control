# Makefile — linak-control
# Builds, tests, and installs LinakControl (menu bar app) and deskctl (CLI).
# Targets operate on the Swift Package at LinakControl/.

SWIFT_PKG_DIR := LinakControl
BUILD_DIR     := $(SWIFT_PKG_DIR)/.build
RELEASE_DIR   := $(BUILD_DIR)/release

APP_BINARY    := LinakControl
CLI_BINARY    := deskctl

INSTALL_BIN   ?= /usr/local/bin
INSTALL_APP   ?= /Applications

.PHONY: help build build-debug test install clean lint

help: ## Show available targets
	@printf "Usage: make <target>\n\n"
	@printf "Targets:\n"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { printf "  %-14s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

build: ## Build both targets in release mode
	cd $(SWIFT_PKG_DIR) && swift build -c release

build-debug: ## Build both targets in debug mode
	cd $(SWIFT_PKG_DIR) && swift build

test: ## Run the test suite
	cd $(SWIFT_PKG_DIR) && swift test

install: build ## Install app and CLI binaries (set INSTALL_BIN / INSTALL_APP to override)
	@printf "Installing $(CLI_BINARY) to $(INSTALL_BIN)/$(CLI_BINARY)\n"
	install -m 755 $(RELEASE_DIR)/$(CLI_BINARY) $(INSTALL_BIN)/$(CLI_BINARY)
	@printf "Installing $(APP_BINARY) to $(INSTALL_BIN)/$(APP_BINARY)\n"
	install -m 755 $(RELEASE_DIR)/$(APP_BINARY) $(INSTALL_BIN)/$(APP_BINARY)
	@printf "Done. Run '$(CLI_BINARY) --help' to verify.\n"

clean: ## Remove build artifacts
	cd $(SWIFT_PKG_DIR) && swift package clean

lint: ## Run SwiftLint if available
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint $(SWIFT_PKG_DIR)/Sources; \
	else \
		printf "swiftlint not found — skipping lint\n"; \
	fi
