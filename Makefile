# Glance build entry points.
#
# With full Xcode installed, plain `swift build` / `swift test` work.
# With only Command Line Tools, Swift Testing lives in a non-default
# location; the TEST_FLAGS below point the toolchain at it.

CLT_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
CLT_TESTLIB    := /Library/Developer/CommandLineTools/Library/Developer/usr/lib

# Only add CLT flags when xcodebuild is unavailable (i.e. CLT-only machines).
ifeq ($(shell xcode-select -p 2>/dev/null | grep -c CommandLineTools),1)
TEST_FLAGS := \
	-Xswiftc -F -Xswiftc $(CLT_FRAMEWORKS) \
	-Xlinker -F -Xlinker $(CLT_FRAMEWORKS) \
	-Xlinker -rpath -Xlinker $(CLT_FRAMEWORKS) \
	-Xlinker -rpath -Xlinker $(CLT_TESTLIB)
endif

.PHONY: build release test app dmg clean

build:
	swift build

release:
	swift build -c release

test:
	swift test $(TEST_FLAGS)

# Assemble Glance.app from the release binary (see scripts/make-app.sh).
app: release
	scripts/make-app.sh

dmg: app
	scripts/make-dmg.sh

clean:
	swift package clean
	rm -rf dist
