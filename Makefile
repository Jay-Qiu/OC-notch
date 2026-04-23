# OC-Notch Release Pipeline
# Usage:
#   make publish           — interactive release (prompts for version bump type)
#   make publish V=0.3.0   — explicit version release (skips prompt)
#   make release           — build pipeline only (clean → build → sign → notarize → staple → zip → appcast)
#   make build             — build Release archive only
#   make sign              — codesign the .app with Developer ID
#   make notarize          — submit to Apple for notarization (waits for completion)
#   make staple            — staple notarization ticket to .app
#   make zip               — create distributable .zip
#   make appcast           — sign zip with EdDSA + generate appcast.xml
#   make setup-sparkle     — download Sparkle CLI tools (one-time)
#   make clean             — remove build artifacts
#
# Prerequisites:
#   1. Apple Developer ID Application certificate installed in Keychain
#   2. Copy local.mk.example → local.mk and fill in your signing values
#   3. Store notarization credentials (see local.mk.example for command)
#   4. gh CLI authenticated (gh auth login)
#   5. Sparkle EdDSA key generated (see local.mk.example for setup)

# ─── Local config (signing identity, team ID) ───────────────────
-include local.mk

# ─── Configuration ───────────────────────────────────────────────
APP_NAME        := OC-Notch
BUNDLE_ID       := com.oc-notch.app

# Sparkle CLI tools (downloaded via `make setup-sparkle`)
SPARKLE_VERSION ?= 2.9.1
SPARKLE_BIN     ?= tmp/sparkle-tools/bin

# Validate required local config
ifndef TEAM_ID
  $(error TEAM_ID not set. Copy local.mk.example to local.mk and fill in your values)
endif
ifndef DEVELOPER_NAME
  $(error DEVELOPER_NAME not set. Copy local.mk.example to local.mk and fill in your values)
endif

SIGN_IDENTITY   := Developer ID Application: $(DEVELOPER_NAME) ($(TEAM_ID))
KEYCHAIN_PROFILE ?= OC-Notch-Notarize

SCHEME          := $(APP_NAME)
PROJECT_DIR     := OC-Notch
BUILD_DIR       := $(PROJECT_DIR)/build
ARCHIVE_PATH    := $(BUILD_DIR)/$(APP_NAME).xcarchive
APP_PATH        := $(BUILD_DIR)/release/$(APP_NAME).app

VERSION         := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" $(PROJECT_DIR)/Sources/App/Info.plist)
# Override VERSION with V when publishing (bump changes Info.plist after parse)
ifdef V
VERSION         := $(V)
endif
ZIP_NAME        := $(APP_NAME)-v$(VERSION).zip
ZIP_PATH        := $(BUILD_DIR)/release/$(ZIP_NAME)

# ─── Targets ─────────────────────────────────────────────────────
.PHONY: release publish _do-publish bump build sign notarize staple zip appcast setup-sparkle clean generate check-clean

# ─── Publish: interactive or explicit release ─────────────────────
# Interactive: make publish        (prompts for patch/minor/major)
# Explicit:    make publish V=0.3.0
publish: check-clean
ifdef V
	@$(MAKE) --no-print-directory _do-publish V=$(V)
else
	@NEW_V=$$(bash scripts/select-version.sh $(PROJECT_DIR)/Sources/App/Info.plist) && \
		$(MAKE) --no-print-directory _do-publish V=$$NEW_V
endif

REPO_URL := $(shell git remote get-url origin | sed 's/\.git$$//' | sed 's|git@github.com:|https://github.com/|')

_do-publish: bump release git-tag gh-release
	@echo ""
	@echo "🚀 v$(V) published to GitHub Releases!"
	@echo "   $(REPO_URL)/releases/tag/v$(V)"

check-clean:
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "❌ Working tree is dirty. Commit or stash changes first."; \
		exit 1; \
	fi

bump:
	@echo "→ Bumping version to $(V)..."
	@/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(V)" $(PROJECT_DIR)/Sources/App/Info.plist
	@NEW_BUILD=$$(( $$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" $(PROJECT_DIR)/Sources/App/Info.plist) + 1 )); \
		/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $$NEW_BUILD" $(PROJECT_DIR)/Sources/App/Info.plist; \
		echo "   Version: $(V) (build $$NEW_BUILD)"
	@git add $(PROJECT_DIR)/Sources/App/Info.plist
	@git commit -m "chore: bump version to $(V)"

git-tag:
	@echo "→ Creating git tag v$(V)..."
	@git tag -a "v$(V)" -m "Release v$(V)"

gh-release:
	@echo "→ Pushing tag to origin..."
	@git push origin HEAD "v$(V)"
	@echo "→ Creating GitHub Release..."
	@PREV_TAG=$$(git tag --sort=-v:refname | grep -v "v$(V)" | head -1); \
	if [ -n "$$PREV_TAG" ]; then \
		CHANGELOG=$$(git log --pretty=format:"- %s" "$$PREV_TAG..HEAD"); \
	else \
		CHANGELOG=$$(git log --pretty=format:"- %s"); \
	fi; \
	gh release create "v$(V)" $(ZIP_PATH) $(BUILD_DIR)/release/appcast.xml \
		--title "v$(V)" \
		--notes "$$CHANGELOG"

release: clean generate build sign notarize staple zip appcast
	@echo ""
	@echo "✅ Release complete: $(ZIP_PATH)"
	@echo "   Appcast:          $(BUILD_DIR)/release/appcast.xml"
	@echo "   Ready to upload to GitHub Releases."

generate:
	@echo "→ Generating Xcode project..."
	cd $(PROJECT_DIR) && xcodegen generate

build:
	@echo "→ Building $(APP_NAME) (Release)..."
	xcodebuild archive \
		-project $(PROJECT_DIR)/$(APP_NAME).xcodeproj \
		-scheme $(SCHEME) \
		-configuration Release \
		-archivePath $(ARCHIVE_PATH) \
		CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" \
		DEVELOPMENT_TEAM=$(TEAM_ID) \
		CODE_SIGN_STYLE=Manual \
		OTHER_CODE_SIGN_FLAGS="--options=runtime" \
		ENABLE_HARDENED_RUNTIME=YES \
		| xcpretty || exit 1
	@echo "→ Exporting .app from archive..."
	@mkdir -p $(BUILD_DIR)/release
	@cp -R $(ARCHIVE_PATH)/Products/Applications/$(APP_NAME).app $(APP_PATH)

sign:
	@echo "→ Signing $(APP_NAME).app with Developer ID..."
	codesign --force --deep --options runtime \
		--sign "$(SIGN_IDENTITY)" \
		--entitlements $(PROJECT_DIR)/Sources/App/OC_Notch.entitlements \
		$(APP_PATH)
	@echo "→ Verifying signature..."
	codesign --verify --verbose=2 $(APP_PATH)
	@echo "→ Checking Gatekeeper assessment..."
	spctl --assess --type exec --verbose=2 $(APP_PATH) || echo "⚠️  spctl failed (expected before notarization)"

notarize:
	@echo "→ Creating zip for notarization submission..."
	ditto -c -k --keepParent $(APP_PATH) $(BUILD_DIR)/release/notarize-upload.zip
	@echo "→ Submitting to Apple for notarization..."
	xcrun notarytool submit $(BUILD_DIR)/release/notarize-upload.zip \
		--keychain-profile "$(KEYCHAIN_PROFILE)" \
		--wait
	@rm -f $(BUILD_DIR)/release/notarize-upload.zip

staple:
	@echo "→ Stapling notarization ticket..."
	xcrun stapler staple $(APP_PATH)
	@echo "→ Verifying stapled app..."
	spctl --assess --type exec --verbose=2 $(APP_PATH)

zip:
	@echo "→ Creating distributable zip..."
	@rm -f $(ZIP_PATH)
	cd $(BUILD_DIR)/release && ditto -c -k --keepParent $(APP_NAME).app $(ZIP_NAME)
	@echo "→ $(ZIP_PATH) ($(shell du -h $(ZIP_PATH) | cut -f1))"

clean:
	@echo "→ Cleaning build artifacts..."
	rm -rf $(BUILD_DIR)

# ─── Sparkle auto-update ─────────────────────────────────────────

appcast: $(ZIP_PATH)
	@echo "→ Generating Sparkle appcast..."
	@mkdir -p $(BUILD_DIR)/appcast
	@cp $(ZIP_PATH) $(BUILD_DIR)/appcast/
	$(SPARKLE_BIN)/generate_appcast $(BUILD_DIR)/appcast \
		--download-url-prefix "$(REPO_URL)/releases/download/v$(VERSION)/"
	@cp $(BUILD_DIR)/appcast/appcast.xml $(BUILD_DIR)/release/appcast.xml
	@echo "→ Appcast generated: $(BUILD_DIR)/release/appcast.xml"

setup-sparkle:
	@echo "→ Downloading Sparkle $(SPARKLE_VERSION) CLI tools..."
	@mkdir -p tmp
	@curl -L --fail -o tmp/Sparkle-$(SPARKLE_VERSION).tar.xz \
		"https://github.com/sparkle-project/Sparkle/releases/download/$(SPARKLE_VERSION)/Sparkle-$(SPARKLE_VERSION).tar.xz"
	@mkdir -p tmp/sparkle-tools
	@tar -xf tmp/Sparkle-$(SPARKLE_VERSION).tar.xz -C tmp/sparkle-tools
	@rm -f tmp/Sparkle-$(SPARKLE_VERSION).tar.xz
	@echo "✅ Sparkle tools installed at $(SPARKLE_BIN)"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Generate EdDSA keypair:  $(SPARKLE_BIN)/generate_keys"
	@echo "     → Private key is stored in your Keychain (NEVER export it)"
	@echo "     → Copy the printed public key into Info.plist SUPublicEDKey"
	@echo "  2. Run 'make release' to build with Sparkle appcast"
