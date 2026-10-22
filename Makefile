APP_NAME := OpenChamber Mini Status
APP := build/$(APP_NAME).app
BINARY := build/mini-status
VERSION ?= 1.0.0
export VERSION

CORE_SOURCES := $(wildcard Sources/Core/*.swift)
APP_SOURCES := $(wildcard Sources/App/*.swift)

.PHONY: build test bundle icon icon-run run snapshot install uninstall dist clean

build: $(BINARY)

$(BINARY): $(CORE_SOURCES) $(APP_SOURCES)
	@mkdir -p build
	swiftc -O -swift-version 5 $(CORE_SOURCES) $(APP_SOURCES) -o $(BINARY)

test:
	@mkdir -p build
	swiftc -swift-version 5 $(CORE_SOURCES) Tests/main.swift -o build/tests
	./build/tests

icon:
	./scripts/make-icon.sh

bundle: build
	./scripts/bundle.sh

run: bundle
	open "$(APP)"

snapshot: bundle
	"$(APP)/Contents/MacOS/mini-status" --snapshot build/hud.png

install: bundle
	./scripts/install.sh

uninstall:
	./scripts/uninstall.sh

dist: bundle
	./scripts/dist.sh

clean:
	rm -rf build dist .build
