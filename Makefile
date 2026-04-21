# OC-Notch Release Pipeline
# Usage:
#   make publish           — interactive release (prompts for version bump type)
#   make publish V=0.3.0   — explicit version release (skips prompt)
#   make release           — build pipeline only (clean → build → sign → notarize → staple → zip)
#   make build             — build Release archive only
#   make sign              — codesign the .app with Developer ID
#   make notarize          — submit to Apple for notarization (waits for completion)
#   make staple            — staple notarization ticket to .app
#   make zip               — create distributable .zip
#   make clean             — remove build artifacts
#
# Prerequisites:
#   1. Apple Developer ID Application certificate installed in Keychain
#   2. App-specific password stored in Keychain:
#      xcrun notarytool store-credentials "OC-Notch-Notarize" \
#        --apple-id "YOUR_APPLE_ID@email.com" \
#        --team-id "literal:REDACTED_TEAM_ID" \
#        --password "YOUR_APP_SPECIFIC_PASSWORD"
#   3. gh CLI authenticated (gh auth login)

# ─── Configuration ───────────────────────────────────────────────
APP_NAME        := OC-Notch
BUNDLE_ID       := com.oc-notch.app
TEAM_ID         := literal:REDACTED_TEAM_ID
SIGN_IDENTITY   := literal:Developer ID Application: REDACTED_NAME ($(TEAM_ID))
KEYCHAIN_PROFILE := OC-Notch-Notarize

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
.PHONY: release publish _do-publish bump build sign notarize staple zip clean generate check-clean

# ─── Publish: interactive or explicit release ─────────────────────
# Interactive: make publish        (prompts for patch/minor/major)
# Explicit:    make publish V=0.3.0
publish: check-clean
ifdef V
	@$(MAKE) --no-print-directory _do-publish V=$(V)
else
	@CURRENT=$$((/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" $(PROJECT_DIR)/Sources/App/Info.plist)); \
	MAJOR=$$(echo $$CURRENT | cut -d. -f1); \
	MINOR=$$(echo $$CURRENT | cut -d. -f2); \
	PATCH=$$(echo $$CURRENT | cut -d. -f3); \
	echo ""; \
	echo "Current version: $$CURRENT"; \
	echo ""; \
	echo "  1) patch  → $$MAJOR.$$MINOR.$$((PATCH + 1))   (bug fixes)"; \
	echo "  2) minor  → $$MAJOR.$$((MINOR + 1)).0   (new features)"; \
	echo "  3) major  → $$((MAJOR + 1)).0.0   (breaking changes)"; \
	echo ""; \
	printf "Select bump type [1/2/3]: "; \
	read CHOICE; \
	case $$CHOICE in \
		1|patch)  NEW_VERSION="$$MAJOR.$$MINOR.$$((PATCH + 1))" ;; \
		2|minor)  NEW_VERSION="$$MAJOR.$$((MINOR + 1)).0" ;; \
		3|major)  NEW_VERSION="$$((MAJOR + 1)).0.0" ;; \
		*)        echo "❌ Invalid choice."; exit 1 ;; \
	esac; \
	echo ""; \
	printf "→ Will publish v$$NEW_VERSION. Continue? [Y/n] "; \
	read CONFIRM; \
	case $$CONFIRM in \
		""|y|Y|yes|Yes) ;; \
		*) echo "Aborted."; exit 1 ;; \
	esac; \
	$(MAKE) --no-print-directory _do-publish V=$$NEW_VERSION
endif

_do-publish: bump release git-tag gh-release
	@echo ""
	@echo "🚀 v$(V) published to GitHub Releases!"
	@echo "   https://github.com/Jay-Qiu/OC-notch/releases/tag/v$(V)"

check-clean:
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "❌ Working tree is dirty. Commit or stash changes first."; \
		exit 1; \
	fi

bump:
	@echo "→ Bumping version to $(V)..."
	@/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(V)" $(PROJECT_DIR)/Sources/App/Info.plist
	@NEW_BUILD=$$(( $$((/usr/libexec/PlistBuddy -c "Print CFBundleVersion" $(PROJECT_DIR)/Sources/App/Info.plist)) + 1 )); \
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
		gh release create "v$(V)" $(ZIP_PATH) \
			--title "v$(V)" \
			--generate-notes \
			--notes-start-tag "$$PREV_TAG"; \
	else \
		gh release create "v$(V)" $(ZIP_PATH) \
			--title "v$(V)" \
			--generate-notes; \
	fi

release: clean generate build sign notarize staple zip
	@echo ""
	@echo "✅ Release complete: $(ZIP_PATH)"
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
