.PHONY: generate check test network-test build test-app

DERIVED_DATA ?= build/DerivedData

generate:
	xcodegen generate

check:
	python3 scripts/check-localizations.py
	python3 scripts/check-public-materials.py
	plutil -lint Config/PrivacyInfo.xcprivacy
	plutil -lint PaperclipKit/Sources/PaperclipKit/Resources/PrivacyInfo.xcprivacy

test:
	env -u PAPERCLIP_TEST_URL -u PAPERCLIP_TEST_TOKEN -u PAPERCLIP_TEST_MODEL_CATALOGS -u PAPERCLIP_ATTACHMENT_TEST_ORIGIN -u PAPERCLIP_NETWORK_TEST_ORIGIN swift test --package-path PaperclipKit

network-test:
	python3 scripts/verify-task-result-downloads.py
	python3 scripts/verify-network-security.py

build: generate
	xcodebuild -project Clipswain.xcodeproj -scheme Clipswain -destination 'generic/platform=iOS Simulator' -derivedDataPath "$(DERIVED_DATA)" CODE_SIGNING_ALLOWED=NO build

test-app: generate
	@test -n "$(SIMULATOR_ID)" || { echo 'Set SIMULATOR_ID to an available iOS simulator UDID.'; exit 2; }
	xcodebuild -project Clipswain.xcodeproj -scheme Clipswain -destination 'platform=iOS Simulator,id=$(SIMULATOR_ID)' -derivedDataPath "$(DERIVED_DATA)" CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:ClipswainAppTests test
