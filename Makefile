#  sudo ditto "build/RawCull.app" "/Applications/RawCull.app"
APP = RawCull
BUNDLE_ID = no.blogspot.$(APP)
VERSION := $(shell grep -m 1 'MARKETING_VERSION' RawCull.xcodeproj/project.pbxproj | awk -F' = ' '{print $$2}' | tr -d ';')
BUILD_PATH = $(PWD)/build
APP_PATH = "$(BUILD_PATH)/$(APP).app"
ZIP_PATH = "$(BUILD_PATH)/$(APP).$(VERSION).zip"
DMG_PATH = $(PWD)/$(APP).$(VERSION).dmg
DMG_SHA256_PATH = $(DMG_PATH).sha256
SIGNING_IDENTITY = "93M47F4H9T"
TEST_DESTINATION = platform=macOS
XCODE_TEST_FLAGS = -project RawCull.xcodeproj -scheme $(APP) -destination '$(TEST_DESTINATION)' -onlyUsePackageVersionsFromResolvedFile
XCODE_RELEASE_FLAGS = -project RawCull.xcodeproj -scheme $(APP) -destination 'platform=macOS,arch=arm64' -configuration Release -onlyUsePackageVersionsFromResolvedFile
SMOKE_TEST_MANIFEST = TestManifests/SmokeTests.txt
PERFORMANCE_TEST_MANIFEST = TestManifests/PerformanceTests.txt
SMOKE_ENUMERATION := $(shell mktemp -u /tmp/rawcull-smoke-enumeration.XXXXXX)
PERFORMANCE_ENUMERATION := $(shell mktemp -u /tmp/rawcull-performance-enumeration.XXXXXX)
TEST_ENUMERATION_VERIFIER = /tmp/rawcull-verify-test-enumeration
TEST_ENUMERATION_MODULE_CACHE = /tmp/rawcull-test-enumeration-module-cache
SMOKE_EXPECTED_TESTS = 173
PERFORMANCE_EXPECTED_TESTS = 2

# Default target is release build
build: release-preflight clean archive sign-app notarize staple prepare-dmg hash-dmg open

# Debug build - skips notarization and signing
debug: clean archive-debug open-debug

# Test targets
build-test-enumeration-verifier:
	xcrun swiftc -module-cache-path $(TEST_ENUMERATION_MODULE_CACHE) \
		Scripts/VerifyTestEnumeration.swift -o $(TEST_ENUMERATION_VERIFIER)

verify-smoke-manifest: build-test-enumeration-verifier
	xcodebuild test $(XCODE_TEST_FLAGS) -testPlan Smoke \
		-enumerate-tests \
		-test-enumeration-style flat \
		-test-enumeration-format json \
		-test-enumeration-output-path $(SMOKE_ENUMERATION) \
		-only-testing @$(SMOKE_TEST_MANIFEST)
	$(TEST_ENUMERATION_VERIFIER) $(SMOKE_ENUMERATION) $(SMOKE_EXPECTED_TESTS)

test-smoke: verify-smoke-manifest
	xcodebuild test $(XCODE_TEST_FLAGS) -testPlan Smoke -enableCodeCoverage NO \
		-only-testing @$(SMOKE_TEST_MANIFEST)

test-full:
	xcodebuild test $(XCODE_TEST_FLAGS) -testPlan RawCull -enableThreadSanitizer YES

verify-performance-manifest: build-test-enumeration-verifier
	xcodebuild test $(XCODE_TEST_FLAGS) -testPlan Performance \
		-enumerate-tests \
		-test-enumeration-style flat \
		-test-enumeration-format json \
		-test-enumeration-output-path $(PERFORMANCE_ENUMERATION) \
		-only-testing @$(PERFORMANCE_TEST_MANIFEST)
	$(TEST_ENUMERATION_VERIFIER) $(PERFORMANCE_ENUMERATION) $(PERFORMANCE_EXPECTED_TESTS)

test-performance: verify-performance-manifest
	xcodebuild test $(XCODE_TEST_FLAGS) -testPlan Performance \
		-only-testing @$(PERFORMANCE_TEST_MANIFEST)

# --- MAIN WORKFLOW FUNCTIONS --- #
release-preflight:
	@test -z "$$(git status --porcelain)" || (echo "Release blocked: worktree is not clean"; exit 1)
	@(git rev-parse --verify --quiet refs/tags/v2.3.4 >/dev/null || git rev-parse --verify --quiet refs/tags/2.3.4 >/dev/null) || (echo "Release blocked: immutable 2.3.4 tag is missing"; exit 1)
	@if rg --quiet '"release_status": "blocked"' ModelAssets/Notices/*/PROVENANCE.json; then \
		echo "Release blocked: model provenance audit is incomplete"; \
		exit 1; \
	fi
	@if rg --quiet 'expectedArchiveSHA256: nil|releaseReadiness: \.blocked' RawCull/Model/AIIntegration/RawCullAIModelDownloadCatalog.swift; then \
		echo "Release blocked: production model descriptors are incomplete"; \
		exit 1; \
	fi

archive: clean
	osascript -e 'display notification "Exporting application archive..." with title "Build the RawCull"'
	echo "Exporting application archive (RELEASE)..."
	xcodebuild \
		$(XCODE_RELEASE_FLAGS) archive \
		-archivePath $(BUILD_PATH)/$(APP).xcarchive
	echo "Application built, starting the export archive..."
	xcodebuild -exportArchive \
		-exportOptionsPlist "exportOptions.plist" \
		-archivePath $(BUILD_PATH)/$(APP).xcarchive \
		-exportPath $(BUILD_PATH)
	echo "Project archived successfully (RELEASE)"

archive-debug: clean
	osascript -e 'display notification "Building debug version..." with title "Build the RawCull"'
	echo "Building application (DEBUG)..."
	xcodebuild \
		-scheme $(APP) \
		-destination 'platform=OS X,arch=arm64' \
		-configuration Debug archive \
		-archivePath $(BUILD_PATH)/$(APP).xcarchive
	echo "Application built, starting the export archive..."
	xcodebuild -exportArchive \
		-exportOptionsPlist "exportOptions.plist" \
		-archivePath $(BUILD_PATH)/$(APP).xcarchive \
		-exportPath $(BUILD_PATH)
	echo "Debug build completed successfully"

sign-app:
	osascript -e 'display notification "Signing application..." with title "Build the RawCull"'
	echo "Signing application with Developer ID..."
	codesign --deep --force \
		--options runtime \
		--sign $(SIGNING_IDENTITY) \
		--timestamp \
		$(APP_PATH)
	echo "Verifying signature..."
	codesign --verify --deep --strict --verbose=2 $(APP_PATH)
	codesign -dv --verbose=4 $(APP_PATH)
	echo "Creating zip for notarization..."
	ditto -c -k --keepParent $(APP_PATH) $(ZIP_PATH)
	echo "Application signed successfully"

notarize:
	osascript -e 'display notification "Submitting app for notarization..." with title "Build the RawCull"'
	echo "Submitting app for notarization..."
	@RESULT=$$(xcrun notarytool submit --keychain-profile "RsyncUI" --wait $(ZIP_PATH) 2>&1); \
	echo "$$RESULT"; \
	if echo "$$RESULT" | grep -q "status: Accepted"; then \
		echo "✅ RawCull successfully notarized"; \
	else \
		echo "❌ Notarization failed!"; \
		SUBMISSION_ID=$$(echo "$$RESULT" | grep "id:" | head -1 | awk '{print $$2}'); \
		echo "Fetching detailed log for submission: $$SUBMISSION_ID"; \
		xcrun notarytool log "$$SUBMISSION_ID" --keychain-profile "RsyncUI"; \
		exit 1; \
	fi

staple:
	osascript -e 'display notification "Stapling the RawCull..." with title "Build the RawCull"'
	echo "Stapling notarization ticket to application..."
	xcrun stapler staple $(APP_PATH)
	echo "Verifying stapled application..."
	spctl -a -t exec -vvv $(APP_PATH)
	osascript -e 'display notification "RawCull successfully stapled" with title "Build the RawCull"'
	echo "✅ RawCull successfully stapled"

prepare-dmg:
	osascript -e 'display notification "Creating DMG..." with title "Build the RawCull"'
	echo "Creating DMG installer..."
	../create-dmg/create-dmg \
		--volname "RawCull ver $(VERSION)" \
		--background "./images/background.png" \
		--window-pos 200 120 \
		--window-size 500 320 \
		--icon-size 80 \
		--icon "RawCull.app" 125 175 \
		--hide-extension "RawCull.app" \
		--app-drop-link 375 175 \
		--no-internet-enable \
		--codesign 93M47F4H9T \
		"$(DMG_PATH)" \
		$(APP_PATH)
	echo "✅ DMG created successfully"
	@echo "Submitting DMG for notarization..."
	xcrun notarytool submit --keychain-profile "RsyncUI" --wait "$(DMG_PATH)"
	
	@echo "Stapling ticket to DMG..."
	xcrun stapler staple "$(DMG_PATH)"
	xcrun stapler validate "$(DMG_PATH)"
	hdiutil verify "$(DMG_PATH)"
	
	@echo "✅ DMG is now signed, notarized and stapled!"

hash-dmg:
	@echo "Writing final DMG SHA-256..."
	shasum -a 256 "$(DMG_PATH)" > "$(DMG_SHA256_PATH)"
	@cat "$(DMG_SHA256_PATH)"

verify-downloaded-dmg:
	@test -n "$(DOWNLOADED_DMG)" || (echo "Set DOWNLOADED_DMG to the downloaded DMG path"; exit 1)
	@test -f "$(DMG_SHA256_PATH)" || (echo "Missing $(DMG_SHA256_PATH)"; exit 1)
	@test -f "$(DOWNLOADED_DMG)" || (echo "Missing downloaded DMG: $(DOWNLOADED_DMG)"; exit 1)
	@EXPECTED=$$(awk '{print $$1}' "$(DMG_SHA256_PATH)"); \
	ACTUAL=$$(shasum -a 256 "$(DOWNLOADED_DMG)" | awk '{print $$1}'); \
	test "$$EXPECTED" = "$$ACTUAL" || (echo "Downloaded DMG SHA-256 mismatch"; exit 1); \
	echo "Downloaded DMG SHA-256 reproduced: $$ACTUAL"

# --- HELPERS --- #
clean:
	rm -rf $(BUILD_PATH)
	if [ -a "$(DMG_PATH)" ]; then rm "$(DMG_PATH)"; fi;
	if [ -a "$(DMG_SHA256_PATH)" ]; then rm "$(DMG_SHA256_PATH)"; fi;

check:
	xcrun notarytool log f62c4146-0758-4942-baac-9575190858b8 --keychain-profile "RsyncUI"

history:
	xcrun notarytool history --keychain-profile "RsyncUI"

check-cert:
	@echo "Available code signing certificates:"
	@security find-identity -v -p codesigning

open:
	osascript -e 'display notification "RawCull signed and ready for distribution" with title "Build the RawCull"'
	echo "Opening working folder..."
	open $(PWD)

open-debug:
	osascript -e 'display notification "RawCull debug build ready" with title "Build the RawCull"'
	echo "Opening working folder..."
	open $(PWD)
	echo "Debug build complete - app is at: $(APP_PATH)"

.PHONY: build debug build-test-enumeration-verifier verify-smoke-manifest test-smoke test-full verify-performance-manifest test-performance release-preflight archive archive-debug sign-app notarize staple prepare-dmg hash-dmg verify-downloaded-dmg clean check history check-cert open open-debug
