# mach-voice build.
#
# The bundle identifier and the signing identity together are what macOS attaches
# an Accessibility grant to. Changing either one makes macOS treat this as a new
# application and silently drops the grant, so both are pinned here on purpose.
# See docs/adr/0003.

APP_NAME    := MachVoice
BUNDLE      := build/$(APP_NAME).app
CONFIG      := release
BIN         := .build/$(CONFIG)/$(APP_NAME)

# Auto-detect the first codesigning identity; override with `make IDENTITY="..."`.
IDENTITY ?= $(shell security find-identity -v -p codesigning | head -1 | awk '{print $$2}')

.PHONY: all build bundle sign run clean identity

all: sign

build:
	swift build -c $(CONFIG)

bundle: build
	@rm -rf $(BUNDLE)
	@mkdir -p $(BUNDLE)/Contents/MacOS $(BUNDLE)/Contents/Resources
	@cp $(BIN) $(BUNDLE)/Contents/MacOS/$(APP_NAME)
	@cp Resources/Info.plist $(BUNDLE)/Contents/Info.plist
	@echo "APPL????" > $(BUNDLE)/Contents/PkgInfo
	@echo "bundled -> $(BUNDLE)"

sign: bundle
	@test -n "$(IDENTITY)" || (echo "no codesigning identity found; pass IDENTITY=..." && exit 1)
	@codesign --force --sign $(IDENTITY) --timestamp=none $(BUNDLE)
	@codesign --verify --verbose=2 $(BUNDLE) 2>&1 | sed 's/^/  /'
	@echo "signed with $(IDENTITY)"

# The code-signing hash, which is what TCC actually keys the grant to.
# It must stay identical across rebuilds or the Accessibility grant is lost.
identity:
	@codesign -dvvv $(BUNDLE) 2>&1 | grep -E "Identifier|CDHash|Authority=Apple Dev" | sed 's/^/  /'

run: sign
	@pkill -x $(APP_NAME) 2>/dev/null || true
	@open $(BUNDLE)
	@echo "launched; look for the mic icon in the menu bar"

clean:
	@rm -rf .build build
