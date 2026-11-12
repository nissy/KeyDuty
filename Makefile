MAKEFLAGS += --no-print-directory
export VERSION BUILD_NUMBER

PROJECT_NAME := KeyDuty
APP_NAME := $(PROJECT_NAME)
PROJECT := $(PROJECT_NAME).xcodeproj
SCHEME := $(PROJECT_NAME)
BUILD_DIR := build
SOURCE_PACKAGES_DIR := $(BUILD_DIR)/SourcePackages
SPARKLE_BIN := $(SOURCE_PACKAGES_DIR)/artifacts/sparkle/Sparkle/bin
DEV_DERIVED_DATA_DIR := $(BUILD_DIR)/DevDerivedData
RELEASE_DERIVED_DATA_DIR := $(BUILD_DIR)/DerivedData
TEST_DERIVED_DATA_DIR := $(BUILD_DIR)/TestDerivedData
SIGNED_DERIVED_DATA_DIR := $(BUILD_DIR)/SignedDerivedData
TEST_RESULT_BUNDLE := $(BUILD_DIR)/TestResults.xcresult
SIGNED_APP := $(SIGNED_DERIVED_DATA_DIR)/Build/Products/Release/$(APP_NAME).app
PROD_BUILD_DIR := $(BUILD_DIR)/release
ARCHIVE_PATH := $(PROD_BUILD_DIR)/$(APP_NAME).xcarchive
EXPORT_PATH := $(PROD_BUILD_DIR)/export
DMG_PATH := $(PROD_BUILD_DIR)/$(APP_NAME).dmg
DESTINATION := platform=macOS,arch=arm64
DEVELOPMENT_TEAM ?= R7LKF73J2W
DEVELOPER_ID_APPLICATION ?= Developer ID Application
PRODUCT_BUNDLE_IDENTIFIER ?= com.nissy.KeyDuty
TEST_BUNDLE_IDENTIFIER ?= com.nissy.KeyDutyTests
APPLE_ID ?=
APPLE_PASSWORD ?=

RED := \033[0;31m
GREEN := \033[0;32m
YELLOW := \033[1;33m
BLUE := \033[0;34m
NC := \033[0m

.PHONY: help version show-version check-version bump-version bump-build test-version
.PHONY: generate lint lint-fix test test-specific build-dev build build-signed
.PHONY: verify-signature stop run archive package dmg release
.PHONY: notarize notarize-status notarize-staple update-assets clean clean-release

.DEFAULT_GOAL := help

help: ## 利用可能なターゲットを表示
	@echo "$(BLUE)$(APP_NAME) Makefile$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)

version: show-version ## バージョンとビルド番号を表示

show-version: ## バージョン設定の内容を表示
	@./Scripts/update_version.sh --show

check-version: ## バージョン設定の整合性を確認
	@./Scripts/update_version.sh --check

bump-version: ## バージョン更新（VERSION=x.y.z、BUILD_NUMBERは任意）
	@if [ -z "$$VERSION" ]; then \
		echo "Usage: make bump-version VERSION=x.y.z [BUILD_NUMBER=n]" >&2; \
		exit 1; \
	fi
	@if [ -n "$$BUILD_NUMBER" ]; then \
		./Scripts/update_version.sh "$$VERSION" "$$BUILD_NUMBER"; \
	else \
		./Scripts/update_version.sh "$$VERSION"; \
	fi
	@$(MAKE) generate

bump-build: ## ビルド番号だけを1増やす
	@./Scripts/update_version.sh --build-only
	@$(MAKE) generate

test-version: ## バージョン更新の動作を検証
	@./Scripts/test_version.sh

generate: check-version ## project.ymlからXcodeプロジェクトを生成
	@if command -v xcodegen >/dev/null 2>&1; then \
		xcodegen generate; \
	else \
		echo "$(RED)Error: XcodeGenが見つかりません$(NC)"; \
		echo "$(YELLOW)brew install xcodegen でインストールしてください$(NC)"; \
		exit 1; \
	fi

lint: ## SwiftLintを実行
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --strict --no-cache; \
	else \
		echo "$(RED)Error: SwiftLintが見つかりません$(NC)"; \
		echo "$(YELLOW)brew install swiftlint でインストールしてください$(NC)"; \
		exit 1; \
	fi

lint-fix: ## SwiftLintで自動修正
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint --fix --no-cache; \
	else \
		echo "$(RED)Error: SwiftLintが見つかりません$(NC)"; \
		echo "$(YELLOW)brew install swiftlint でインストールしてください$(NC)"; \
		exit 1; \
	fi

test: generate ## 全テストを実行
	@rm -rf "$(TEST_RESULT_BUNDLE)"
	@mkdir -p "$(TEST_DERIVED_DATA_DIR)"
	xcodebuild test \
		-project $(PROJECT) \
		-clonedSourcePackagesDirPath "$(SOURCE_PACKAGES_DIR)" \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		-resultBundlePath "$(TEST_RESULT_BUNDLE)" \
		-derivedDataPath "$(TEST_DERIVED_DATA_DIR)" \
		CODE_SIGN_IDENTITY='' \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO

test-specific: generate ## 指定テストを実行（TEST=ClassName）
	@if [ -z "$(TEST)" ]; then \
		echo "$(RED)Error: TEST=ClassNameを指定してください$(NC)"; \
		exit 1; \
	fi
	@rm -rf "$(TEST_RESULT_BUNDLE)"
	@mkdir -p "$(TEST_DERIVED_DATA_DIR)"
	xcodebuild test \
		-project $(PROJECT) \
		-clonedSourcePackagesDirPath "$(SOURCE_PACKAGES_DIR)" \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		-resultBundlePath "$(TEST_RESULT_BUNDLE)" \
		-derivedDataPath "$(TEST_DERIVED_DATA_DIR)" \
		CODE_SIGN_IDENTITY='' \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO \
		-only-testing:KeyDutyTests/$(TEST)

build-dev: generate ## 署名なしDebug版をビルド
	@mkdir -p "$(DEV_DERIVED_DATA_DIR)"
	xcodebuild build \
		-project $(PROJECT) \
		-clonedSourcePackagesDirPath "$(SOURCE_PACKAGES_DIR)" \
		-scheme $(SCHEME) \
		-configuration Debug \
		-destination '$(DESTINATION)' \
		-derivedDataPath "$(DEV_DERIVED_DATA_DIR)" \
		CODE_SIGN_IDENTITY='' \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO

build: generate ## 署名なしRelease版をビルド
	@mkdir -p "$(RELEASE_DERIVED_DATA_DIR)"
	xcodebuild build \
		-project $(PROJECT) \
		-clonedSourcePackagesDirPath "$(SOURCE_PACKAGES_DIR)" \
		-scheme $(SCHEME) \
		-configuration Release \
		-destination '$(DESTINATION)' \
		-derivedDataPath "$(RELEASE_DERIVED_DATA_DIR)" \
		CODE_SIGN_IDENTITY='' \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO

build-signed: generate ## Developer ID署名付きRelease版をビルド
	@mkdir -p "$(SIGNED_DERIVED_DATA_DIR)"
	xcodebuild build \
		-project $(PROJECT) \
		-clonedSourcePackagesDirPath "$(SOURCE_PACKAGES_DIR)" \
		-scheme $(SCHEME) \
		-configuration Release \
		-destination 'generic/platform=macOS' \
		-derivedDataPath "$(SIGNED_DERIVED_DATA_DIR)" \
		CODE_SIGN_STYLE=Manual \
		CODE_SIGN_IDENTITY='$(DEVELOPER_ID_APPLICATION)' \
		DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM) \
		CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
		OTHER_CODE_SIGN_FLAGS='--timestamp=none'

verify-signature: ## 署名済みRelease版の署名を検証
	@if [ ! -d "$(SIGNED_APP)" ]; then \
		echo "$(RED)Error: 署名済みアプリが見つかりません: $(SIGNED_APP)$(NC)"; \
		exit 1; \
	fi
	codesign --verify --deep --strict --verbose=2 "$(SIGNED_APP)"
	codesign --display --verbose=2 "$(SIGNED_APP)"

archive: generate ## Developer ID署名付きxcarchiveを作成
	@mkdir -p "$(PROD_BUILD_DIR)"
	xcodebuild archive \
		-project $(PROJECT) \
		-clonedSourcePackagesDirPath "$(SOURCE_PACKAGES_DIR)" \
		-scheme $(SCHEME) \
		-configuration Release \
		-archivePath "$(ARCHIVE_PATH)" \
		-destination 'generic/platform=macOS' \
		-allowProvisioningUpdates \
		DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM) \
		PRODUCT_BUNDLE_IDENTIFIER='$(PRODUCT_BUNDLE_IDENTIFIER)' \
		TEST_BUNDLE_IDENTIFIER='$(TEST_BUNDLE_IDENTIFIER)' \
		CODE_SIGN_STYLE=Manual \
		CODE_SIGN_IDENTITY='$(DEVELOPER_ID_APPLICATION)' \
		CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
		OTHER_CODE_SIGN_FLAGS='--timestamp --options=runtime'

package: archive ## xcarchiveから配布用appを書き出し
	@mkdir -p "$(EXPORT_PATH)"
	@printf '%s\n' \
'<?xml version="1.0" encoding="UTF-8"?>' \
'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
'<plist version="1.0">' \
'<dict>' \
'    <key>method</key>' \
'    <string>developer-id</string>' \
'    <key>teamID</key>' \
'    <string>$(DEVELOPMENT_TEAM)</string>' \
'    <key>signingCertificate</key>' \
'    <string>Developer ID Application</string>' \
'    <key>signingStyle</key>' \
'    <string>manual</string>' \
'    <key>hardened-runtime</key>' \
'    <true/>' \
'</dict>' \
'</plist>' \
		> "$(EXPORT_PATH)/exportOptions.plist"
	xcodebuild -exportArchive \
		-archivePath "$(ARCHIVE_PATH)" \
		-exportPath "$(EXPORT_PATH)" \
		-exportOptionsPlist "$(EXPORT_PATH)/exportOptions.plist" \
		-allowProvisioningUpdates
	@rm -rf "$(PROD_BUILD_DIR)/$(APP_NAME).app"
	@cp -R "$(EXPORT_PATH)/$(APP_NAME).app" "$(PROD_BUILD_DIR)/$(APP_NAME).app"
	@codesign --verify --deep --strict --verbose=2 "$(PROD_BUILD_DIR)/$(APP_NAME).app"
	@echo "$(GREEN)Production app ready: $(PROD_BUILD_DIR)/$(APP_NAME).app$(NC)"

dmg: package ## 配布用DMGを作成して署名
	@rm -rf "$(PROD_BUILD_DIR)/dmg_temp"
	@rm -f "$(DMG_PATH)"
	@mkdir -p "$(PROD_BUILD_DIR)/dmg_temp"
	@cp -R "$(PROD_BUILD_DIR)/$(APP_NAME).app" "$(PROD_BUILD_DIR)/dmg_temp/"
	@ln -s /Applications "$(PROD_BUILD_DIR)/dmg_temp/Applications"
	hdiutil create -volname "$(APP_NAME)" -srcfolder "$(PROD_BUILD_DIR)/dmg_temp" \
		-ov -format UDZO "$(DMG_PATH)"
	@rm -rf "$(PROD_BUILD_DIR)/dmg_temp"
	codesign --force --sign "$(DEVELOPER_ID_APPLICATION)" "$(DMG_PATH)" -v
	@echo "$(GREEN)DMG ready: $(DMG_PATH)$(NC)"

stop: ## 実行中のKeyDutyを終了
	@pids="$$(pgrep -f '/$(APP_NAME)[.]app/Contents/MacOS/$(APP_NAME)$$' || true)"; \
	if [ -z "$$pids" ]; then exit 0; fi; \
	echo "$(YELLOW)Stopping existing $(APP_NAME) processes...$(NC)"; \
	kill $$pids; \
	attempts=0; \
	while [ "$$attempts" -lt 50 ]; do \
		running=""; \
		for pid in $$pids; do \
			if kill -0 "$$pid" 2>/dev/null; then running=1; fi; \
		done; \
		if [ -z "$$running" ]; then exit 0; fi; \
		sleep 0.1; \
		attempts=$$((attempts + 1)); \
	done; \
	echo "$(RED)Error: $(APP_NAME)を終了できませんでした$(NC)" >&2; \
	exit 1

run: stop ## 署名済みRelease版をビルドして起動
	@$(MAKE) build-signed
	@$(MAKE) verify-signature
	@open "$(abspath $(SIGNED_APP))"

release: stop ## lint、test、配布用DMGを作成
	@$(MAKE) clean
	@$(MAKE) lint
	@$(MAKE) test
	@$(MAKE) dmg
	@echo "$(GREEN)Release build complete: $(DMG_PATH)$(NC)"

notarize: ## DMGをAppleへnotarization申請
	@if [ -z "$(APPLE_ID)" ] || [ -z "$(APPLE_PASSWORD)" ]; then \
		echo "$(RED)Error: APPLE_IDとAPPLE_PASSWORDを設定してください$(NC)"; \
		exit 1; \
	fi
	@if [ ! -f "$(DMG_PATH)" ]; then \
		echo "$(RED)Error: DMGが見つかりません。先にmake releaseを実行してください$(NC)"; \
		exit 1; \
	fi
	@SUBMISSION_ID=$$(xcrun notarytool submit "$(DMG_PATH)" \
		--apple-id "$(APPLE_ID)" \
		--password "$(APPLE_PASSWORD)" \
		--team-id "$(DEVELOPMENT_TEAM)" \
		--output-format json | /usr/bin/plutil -extract id raw -o - -); \
	if [ -z "$$SUBMISSION_ID" ]; then \
		echo "$(RED)Error: notarization申請に失敗しました$(NC)"; \
		exit 1; \
	fi; \
	echo "$(GREEN)Submission ID: $$SUBMISSION_ID$(NC)"; \
	echo "$$SUBMISSION_ID" > "$(PROD_BUILD_DIR)/notarization-id.txt"

notarize-status: ## notarization状態を確認（SUBMISSION_ID指定可）
	@if [ -z "$(APPLE_ID)" ] || [ -z "$(APPLE_PASSWORD)" ]; then \
		echo "$(RED)Error: APPLE_IDとAPPLE_PASSWORDを設定してください$(NC)"; \
		exit 1; \
	fi
	@submission_id="$(SUBMISSION_ID)"; \
	if [ -z "$$submission_id" ] && [ -f "$(PROD_BUILD_DIR)/notarization-id.txt" ]; then \
		submission_id=$$(cat "$(PROD_BUILD_DIR)/notarization-id.txt"); \
	fi; \
	if [ -z "$$submission_id" ]; then \
		echo "$(RED)Error: SUBMISSION_IDがありません$(NC)"; \
		exit 1; \
	fi; \
	xcrun notarytool info "$$submission_id" \
		--apple-id "$(APPLE_ID)" \
		--password "$(APPLE_PASSWORD)" \
		--team-id "$(DEVELOPMENT_TEAM)"

notarize-staple: ## notarizationチケットをDMGへ付加
	@if [ ! -f "$(DMG_PATH)" ]; then \
		echo "$(RED)Error: DMGが見つかりません: $(DMG_PATH)$(NC)"; \
		exit 1; \
	fi
	xcrun stapler staple "$(DMG_PATH)"
	spctl -a -t open --context context:primary-signature -v "$(DMG_PATH)"
	@echo "$(GREEN)Notarized DMG ready: $(DMG_PATH)$(NC)"

update-assets: ## 公証済みDMGと署名付きappcastをGitHub Releases向けに用意
	@./Scripts/prepare_update_assets.sh "$(DMG_PATH)" "$(SPARKLE_BIN)" "$(PROD_BUILD_DIR)/github"

clean: ## Xcodeプロジェクトと全ビルド成果物を削除
	@echo "$(BLUE)Cleaning generated and build artifacts...$(NC)"
	@for path in "$(PROJECT)" "$(BUILD_DIR)" "DerivedData"; do \
		for attempt in 1 2 3 4 5; do \
			[ -e "$$path" ] || break; \
			chmod -R u+w "$$path" >/dev/null 2>&1 || true; \
			if rm -rf "$$path" >/dev/null 2>&1; then break; fi; \
			if [ "$$attempt" = "5" ]; then \
				echo "$(RED)Error: $$pathを削除できませんでした$(NC)"; \
				exit 1; \
			fi; \
			sleep 1; \
		done; \
	done
	@echo "$(GREEN)Clean complete$(NC)"

clean-release: ## 署名済みビルドと配布成果物を削除
	@for path in "$(SIGNED_DERIVED_DATA_DIR)" "$(PROD_BUILD_DIR)"; do \
		for attempt in 1 2 3 4 5; do \
			[ -e "$$path" ] || break; \
			chmod -R u+w "$$path" >/dev/null 2>&1 || true; \
			if rm -rf "$$path" >/dev/null 2>&1; then break; fi; \
			if [ "$$attempt" = "5" ]; then \
				echo "$(RED)Error: $$pathを削除できませんでした$(NC)"; \
				exit 1; \
			fi; \
			sleep 1; \
		done; \
	done
	@echo "$(GREEN)Release clean complete$(NC)"
