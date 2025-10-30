.PHONY: all build clean test help

# Binary output directory
BIN_DIR := bin
MANIFEST_FILTER := $(BIN_DIR)/manifest-filter

all: build

## build: Build all Go binaries
build:
	@echo "Building manifest-filter..."
	@mkdir -p $(BIN_DIR)
	@cd cmd/manifest-filter && go build -o ../../$(MANIFEST_FILTER)
	@echo "✓ Build complete: $(MANIFEST_FILTER)"

## clean: Clean build artifacts and work directory
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BIN_DIR)
	@rm -rf work
	@echo "✓ Clean complete"

## deps: Download Go dependencies
deps:
	@echo "Downloading dependencies..."
	@go mod download
	@go mod tidy
	@echo "✓ Dependencies updated"

## test: Run tests
test:
	@echo "Running tests..."
	@go test -v ./...

## help: Show this help message
help:
	@echo "Available targets:"
	@sed -n 's/^##//p' ${MAKEFILE_LIST} | column -t -s ':' | sed -e 's/^/ /'
