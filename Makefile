BINARY_NAME=claude-status
BUILD_DIR=bin

.PHONY: build test clean install

build:
	go build -o $(BUILD_DIR)/$(BINARY_NAME) ./cmd/claude-status/

test:
	go test ./...

clean:
	rm -rf $(BUILD_DIR)

install: build
	cp $(BUILD_DIR)/$(BINARY_NAME) /usr/local/bin/

run: build
	$(BUILD_DIR)/$(BINARY_NAME)
