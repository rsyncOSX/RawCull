APP = RawCull
BUNDLE_ID = no.blogspot.$(APP)
VERSION = 1.0.5
BUILD_PATH = $(PWD)/build
APP_PATH = "$(BUILD_PATH)/$(APP).app"
ZIP_PATH = "$(BUILD_PATH)/$(APP).$(VERSION).zip"
SIGNING_IDENTITY = "93M47F4H9T"

# Default target is release build
build: clean archive sign-app notarize staple prepare-dmg open

# Debug build - skips notarization and signing
debug: clean archive-debug open-debug

# --- MAIN WORKFLOW FUNCTIONS --- #
archive: clean
	osascript -e 'display notification "Exporting application archive..." with title "Build the RawCull"'
	echo "Exporting application archive (RELEASE)..."
	xcodebuild \
		-scheme $(APP) \
		-destination 'platform=OS X,arch=x86_64' \
		-configuration Release archive \
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
		-destination 'platform=OS X,arch=x86_64' \
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
		"$(APP).$(VERSION).dmg" \
		$(APP_PATH)
	echo "✅ DMG created successfully"

# --- HELPERS --- #
clean:
	rm -rf $(BUILD_PATH)
	if [ -a $(PWD)/$(APP).$(VERSION).dmg ]; then rm $(PWD)/$(APP).$(VERSION).dmg; fi;

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

.PHONY: build debug archive archive-debug sign-app notarize staple prepare-dmg clean check history check-cert open open-debug
