BINARY_NAME=claude-status
BUILD_DIR=bin
VERSION=$(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
LDFLAGS=-ldflags "-s -w -X main.version=$(VERSION)"
INSTALL_DIR=$(HOME)/.local/bin

.PHONY: build test clean install uninstall run

build:
	go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME) ./cmd/claude-status/

test:
	go test ./...

clean:
	rm -rf $(BUILD_DIR)

install: build
	@mkdir -p $(INSTALL_DIR)
	@cp $(BUILD_DIR)/$(BINARY_NAME) $(INSTALL_DIR)/$(BINARY_NAME)
	@echo "Installed to $(INSTALL_DIR)/$(BINARY_NAME)"
	@if ! echo "$$PATH" | grep -q "$(INSTALL_DIR)"; then \
		SHELL_RC=""; \
		if [ -f "$(HOME)/.zshrc" ]; then SHELL_RC="$(HOME)/.zshrc"; \
		elif [ -f "$(HOME)/.bashrc" ]; then SHELL_RC="$(HOME)/.bashrc"; \
		fi; \
		if [ -n "$$SHELL_RC" ] && ! grep -q '\.local/bin' "$$SHELL_RC"; then \
			echo 'export PATH="$$HOME/.local/bin:$$PATH"' >> "$$SHELL_RC"; \
			echo "Added $(INSTALL_DIR) to PATH in $$SHELL_RC"; \
			echo "Run: source $$SHELL_RC (or open a new terminal)"; \
		fi; \
	fi
	@echo ""
	@echo "Next: run 'claude-status install' to configure Claude Code hooks"

uninstall:
	@rm -f $(INSTALL_DIR)/$(BINARY_NAME)
	@echo "Removed $(INSTALL_DIR)/$(BINARY_NAME)"

run: build
	$(BUILD_DIR)/$(BINARY_NAME)
