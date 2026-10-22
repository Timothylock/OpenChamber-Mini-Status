APP_NAME := OpenChamber Mini Status
APP := build/$(APP_NAME).app
BINARY := build/mini-status
VERSION ?= 1.0.0
export VERSION

CORE_SOURCES := $(wildcard Sources/Core/*.swift)
APP_SOURCES := $(wildcard Sources/App/*.swift)
SOURCES := $(CORE_SOURCES) $(APP_SOURCES)
# One release for Apple silicon and Intel. swiftc has no -arch flag, so build each
# slice for its target and join them.
ARCHS := arm64 x86_64
TARGET_MIN := apple-macosx13.0

.PHONY: build test bundle icon icon-run run snapshot docs install uninstall dist clean

build: $(BINARY)

$(BINARY): $(SOURCES)
	@mkdir -p build
	@set -e; \
	for arch in $(ARCHS); do \
		echo "swiftc $$arch"; \
		swiftc -O -swift-version 5 -target $$arch-$(TARGET_MIN) $(SOURCES) -o build/mini-status-$$arch; \
	done
	lipo -create $(foreach arch,$(ARCHS),build/mini-status-$(arch)) -output $(BINARY)

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

docs: bundle
	"$(APP)/Contents/MacOS/mini-status" --snapshot-demo docs/screenshot.png
	"$(APP)/Contents/MacOS/mini-status" --snapshot-settings docs/settings.png

install: bundle
	./scripts/install.sh

uninstall:
	./scripts/uninstall.sh

dist: bundle
	./scripts/dist.sh

clean:
	rm -rf build dist .build
