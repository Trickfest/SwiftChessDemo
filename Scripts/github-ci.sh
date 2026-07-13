#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIMULATOR_DESTINATION="${SWIFT_CHESS_DEMO_SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro,OS=latest}"
TEST_DERIVED_DATA="${SWIFT_CHESS_DEMO_TEST_DERIVED_DATA:-.build/xcode-swiftchessdemo}"
RELEASE_DERIVED_DATA="${SWIFT_CHESS_DEMO_RELEASE_DERIVED_DATA:-.build/xcode-swiftchessdemo-release}"
SOURCE_PACKAGES_DIR="${SWIFT_CHESS_DEMO_SOURCE_PACKAGES_DIR:-$TEST_DERIVED_DATA/SourcePackages}"
EXPECTED_MARKETING_VERSION="1.2.0"

cd "$ROOT_DIR"

for dependency in ../SwiftChessTools ../StockfishEmbedded; do
  if [[ ! -d "$dependency" ]]; then
    printf 'Missing required sibling checkout: %s\n' "$dependency" >&2
    exit 1
  fi
done

printf 'Running app-hosted unit tests without simulator UI tests...\n'
xcodebuild \
  -project SwiftChessDemo.xcodeproj \
  -scheme SwiftChessDemo \
  -configuration Debug \
  -destination "$SIMULATOR_DESTINATION" \
  -derivedDataPath "$TEST_DERIVED_DATA" \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR" \
  -skip-testing:SwiftChessDemoUITests \
  test

printf 'Building the generic iOS Release configuration...\n'
xcodebuild \
  -project SwiftChessDemo.xcodeproj \
  -scheme SwiftChessDemo \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$RELEASE_DERIVED_DATA" \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build

app_info="$RELEASE_DERIVED_DATA/Build/Products/Release-iphoneos/SwiftChessDemo.app/Info.plist"
if [[ ! -f "$app_info" ]]; then
  printf 'Release build did not produce the expected Info.plist: %s\n' "$app_info" >&2
  exit 1
fi

if ! supports_multiple_scenes="$(
  plutil -extract UIApplicationSceneManifest.UIApplicationSupportsMultipleScenes \
    raw -o - "$app_info"
)"; then
  printf 'Could not read UIApplicationSupportsMultipleScenes from %s\n' "$app_info" >&2
  exit 1
fi
if [[ "$supports_multiple_scenes" != "false" ]]; then
  printf 'Expected UIApplicationSupportsMultipleScenes=false, found %s\n' \
    "$supports_multiple_scenes" >&2
  exit 1
fi

if ! marketing_version="$(
  plutil -extract CFBundleShortVersionString raw -o - "$app_info"
)"; then
  printf 'Could not read CFBundleShortVersionString from %s\n' "$app_info" >&2
  exit 1
fi
if [[ "$marketing_version" != "$EXPECTED_MARKETING_VERSION" ]]; then
  printf 'Expected marketing version %s, found %s\n' \
    "$EXPECTED_MARKETING_VERSION" "$marketing_version" >&2
  exit 1
fi

printf 'SwiftChessDemo hosted headless checks succeeded.\n'
