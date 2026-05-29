APP = RawCull
BUNDLE_ID = no.blogspot.$(APP)
VERSION := $(shell grep -m 1 'MARKETING_VERSION' RawCull.xcodeproj/project.pbxproj | awk -F' = ' '{print $$2}' | tr -d ';')
BUILD_PATH = $(PWD)/build
APP_PATH = "$(BUILD_PATH)/$(APP).app"
ZIP_PATH = "$(BUILD_PATH)/$(APP).$(VERSION).zip"
SIGNING_IDENTITY = "93M47F4H9T"
TEST_DESTINATION = platform=macOS
XCODE_TEST_FLAGS = -project RawCull.xcodeproj -scheme $(APP) -destination '$(TEST_DESTINATION)' -onlyUsePackageVersionsFromResolvedFile
SMOKE_ONLY_TESTING = \
	'-only-testing:RawCullTests/SimilarityDistanceOrderingTests/`rankSimilar returns nearest image first`()' \
	'-only-testing:RawCullTests/SimilarityDistanceOrderingTests/`anchor is excluded from distances`()' \
	'-only-testing:RawCullTests/SimilarityEmptyStateTests/`rankSimilar with unknown anchor clears state`()' \
	'-only-testing:RawCullTests/SimilarityEmptyStateTests/`indexFiles with empty array leaves model unchanged`()' \
	'-only-testing:RawCullTests/SimilarityEmptyStateTests/`initial sortBySimilarity is false`()' \
	'-only-testing:RawCullTests/SimilaritySubjectMismatchTests/`subject mismatch increases distance`()' \
	'-only-testing:RawCullTests/SimilarityCancellationTests/`cancelIndexing resets progress state`()' \
	'-only-testing:RawCullTests/SimilarityCancellationTests/`reset clears all similarity state`()' \
	'-only-testing:RawCullTests/SharpnessScoringTests/`max score small set uses maximum not minimum`()' \
	'-only-testing:RawCullTests/SharpnessScoringTests/`max score large set uses P 90`()' \
	'-only-testing:RawCullTests/SharpnessScoringTests/`sharpness label maps threshold boundaries`()' \
	'-only-testing:RawCullTests/SharpnessScoringTests/`sharpness label clamps and handles invalid denominator`()' \
	'-only-testing:RawCullTests/FocusNumericHelperTests/`robust tail score empty returns nil`()' \
	'-only-testing:RawCullTests/FocusNumericHelperTests/`robust tail score uniform returns zero`()' \
	'-only-testing:RawCullTests/FocusNumericHelperTests/`robust tail score dense edges scores higher than sparse`()' \
	'-only-testing:RawCullTests/FocusNumericHelperTests/`robust tail score dense edges full density factor`()' \
	'-only-testing:RawCullTests/FocusNumericHelperTests/`robust tail score sparse edges scores low`()' \
	'-only-testing:RawCullTests/FocusNumericHelperTests/`robust tail score is scale proportional`()' \
	'-only-testing:RawCullTests/FocusNumericHelperTests/`micro contrast empty returns zero`()' \
	'-only-testing:RawCullTests/FocusNumericHelperTests/`micro contrast uniform returns zero`()' \
	'-only-testing:RawCullTests/FocusNumericHelperTests/`micro contrast ignores non finite`()' \
	'-only-testing:RawCullTests/FocusNumericHelperTests/`micro contrast alternating known variance`()' \
	'-only-testing:RawCullTests/FocusNumericHelperTests/`adaptive AF threshold keeps low contrast local detail reachable`()' \
	'-only-testing:RawCullTests/FocusNumericHelperTests/`adaptive saliency threshold rises for broad high contrast edges`()' \
	'-only-testing:RawCullTests/FocusNumericHelperTests/`adaptive AF threshold is capped so strong body edges do not hide AF detail`()' \
	'-only-testing:RawCullTests/FocusNumericHelperTests/`focus evidence selection prefers AF when strongest`()' \
	'-only-testing:RawCullTests/FocusNumericHelperTests/`focus evidence selection prefers AF center when eye patch is strongest`()' \
	'-only-testing:RawCullTests/FocusNumericHelperTests/`focus evidence selection uses AF neighborhood when center is weak`()' \
	'-only-testing:RawCullTests/FocusNumericHelperTests/`focus evidence selection keeps wildlife AF when nearly strongest`()' \
	'-only-testing:RawCullTests/FocusNumericHelperTests/`focus evidence selection uses saliency when AF is absent`()' \
	'-only-testing:RawCullTests/FocusNumericHelperTests/`focus evidence selection keeps saliency when AF local scores are weak`()' \
	'-only-testing:RawCullTests/FocusNumericHelperTests/`focus evidence selection falls back to global without subject evidence`()' \
	'-only-testing:RawCullTests/FocusNumericHelperTests/`visibility relaxation lowers threshold to meet minimum coverage`()' \
	'-only-testing:RawCullTests/FocusNumericHelperTests/`visibility relaxation is not applied when coverage already meets target`()' \
	'-only-testing:RawCullTests/FocusNumericHelperTests/`AF local rect stays constrained around focus point`()' \
	'-only-testing:RawCullTests/ApertureHintTests/`nil aperture maps to mid`()' \
	'-only-testing:RawCullTests/ApertureHintTests/`wide boundary is inclusive at 5 point 6`()' \
	'-only-testing:RawCullTests/ApertureHintTests/`landscape boundary is inclusive at f 8`()' \
	'-only-testing:RawCullTests/ApertureHintTests/`landscape has widest gate window and lowest threshold`()' \
	'-only-testing:RawCullTests/ApertureHintTests/`only landscape overrides salient weight and damps blur`()' \
	'-only-testing:RawCullTests/ApertureHintTests/`blur gate span is positive for every hint`()' \
	'-only-testing:RawCullTests/ISOScalingTests/`below 800 is flat at 1 point 0`()' \
	'-only-testing:RawCullTests/ISOScalingTests/`mid range ramps to 1 point 6 at 3200`()' \
	'-only-testing:RawCullTests/ISOScalingTests/`high range caps at 2 point 2`()' \
	'-only-testing:RawCullTests/ISOScalingTests/`monotonically non decreasing across range`()' \
	'-only-testing:RawCullTests/ISOScalingTests/`high ISO is less aggressive than old sqrt formula`()' \
	'-only-testing:RawCullTests/ComparisonCandidateInspectorTests/`exif footer omits missing fields and preserves display order`()' \
	'-only-testing:RawCullTests/ComparisonCandidateInspectorTests/`candidate context resolves selected rank saliency scores and focus points`()' \
	'-only-testing:RawCullTests/ComparisonCandidateInspectorTests/`finalist focus uses recommended finalists without mutating source ids`()' \
	'-only-testing:RawCullTests/ComparisonCandidateInspectorTests/`finalist focus falls back to ranked candidates when recommendation ids are missing`()' \
	'-only-testing:RawCullTests/ComparisonCandidateInspectorTests/`finalist focus falls back to file ids when candidates are missing`()'
PERFORMANCE_ONLY_TESTING = \
	'-only-testing:RawCullTests/DataRaceDetectionTests/`Extreme concurrent load reveals no data races`()'

# Default target is release build
build: clean archive sign-app notarize staple prepare-dmg open

# Debug build - skips notarization and signing
debug: clean archive-debug open-debug

# Test targets
test-smoke:
	xcodebuild test $(XCODE_TEST_FLAGS) -testPlan Smoke $(SMOKE_ONLY_TESTING)

test-full:
	xcodebuild test $(XCODE_TEST_FLAGS) -testPlan RawCull -enableThreadSanitizer YES

test-performance:
	xcodebuild test $(XCODE_TEST_FLAGS) -testPlan Performance $(PERFORMANCE_ONLY_TESTING)

# --- MAIN WORKFLOW FUNCTIONS --- #
archive: clean
	osascript -e 'display notification "Exporting application archive..." with title "Build the RawCull"'
	echo "Exporting application archive (RELEASE)..."
	xcodebuild \
		-scheme $(APP) \
		-destination 'platform=OS X,arch=arm64' \
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
		"$(APP).$(VERSION).dmg" \
		$(APP_PATH)
	echo "✅ DMG created successfully"
	@echo "Submitting DMG for notarization..."
	xcrun notarytool submit --keychain-profile "RsyncUI" --wait "$(APP).$(VERSION).dmg"
	
	@echo "Stapling ticket to DMG..."
	xcrun stapler staple "$(APP).$(VERSION).dmg"
	
	@echo "✅ DMG is now signed, notarized and stapled!"

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

.PHONY: build debug test-smoke test-full test-performance archive archive-debug sign-app notarize staple prepare-dmg clean check history check-cert open open-debug
