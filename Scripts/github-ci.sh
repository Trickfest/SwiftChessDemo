#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIMULATOR_DESTINATION="${SWIFT_CHESS_DEMO_SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro,OS=latest}"
TEST_DERIVED_DATA="${SWIFT_CHESS_DEMO_TEST_DERIVED_DATA:-.build/xcode-swiftchessdemo}"
RELEASE_DERIVED_DATA="${SWIFT_CHESS_DEMO_RELEASE_DERIVED_DATA:-.build/xcode-swiftchessdemo-release}"
SOURCE_PACKAGES_DIR="${SWIFT_CHESS_DEMO_SOURCE_PACKAGES_DIR:-$TEST_DERIVED_DATA/SourcePackages}"
EXPECTED_MARKETING_VERSION="1.2.1"

cd "$ROOT_DIR"

if grep -q 'DEVELOPMENT_TEAM' SwiftChessDemo.xcodeproj/project.pbxproj ||
  grep -Eq '^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=' \
    Configurations/Signing.xcconfig; then
  printf '%s\n' \
    'The shared Xcode project must not contain an Apple Developer Team override.' >&2
  printf '%s\n' \
    'Use the ignored Configurations/Signing.local.xcconfig file instead.' >&2
  exit 1
fi
if [[ "$(grep -Ec '^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=' \
  Configurations/Signing.local.xcconfig.example)" -ne 1 ]] ||
  ! grep -Fxq 'DEVELOPMENT_TEAM = YOUR_TEAM_ID' \
    Configurations/Signing.local.xcconfig.example; then
  printf '%s\n' \
    'The tracked local signing example must contain exactly the Team ID placeholder.' >&2
  exit 1
fi
if [[ "$(grep -Ec '^[[:space:]]*SWIFT_CHESS_DEMO_BUNDLE_ID_PREFIX[[:space:]]*=' \
  Configurations/Signing.local.xcconfig.example)" -ne 1 ]] ||
  ! grep -Fxq \
    'SWIFT_CHESS_DEMO_BUNDLE_ID_PREFIX = YOUR_REVERSE_DNS_PREFIX' \
    Configurations/Signing.local.xcconfig.example; then
  printf '%s\n' \
    'The tracked local signing example must contain exactly the bundle ID placeholder.' >&2
  exit 1
fi
if ! grep -Fq '#include? "Signing.local.xcconfig"' \
  Configurations/Signing.xcconfig; then
  printf '%s\n' \
    'Configurations/Signing.xcconfig must retain its optional local include.' >&2
  exit 1
fi
if [[ "$(grep -c 'PRODUCT_BUNDLE_IDENTIFIER' \
  SwiftChessDemo.xcodeproj/project.pbxproj)" -ne 6 ]] ||
  grep 'PRODUCT_BUNDLE_IDENTIFIER' SwiftChessDemo.xcodeproj/project.pbxproj |
  grep -Fqv '$(SWIFT_CHESS_DEMO_BUNDLE_ID_PREFIX)'; then
  printf '%s\n' \
    'Shared bundle identifiers must use SWIFT_CHESS_DEMO_BUNDLE_ID_PREFIX.' >&2
  exit 1
fi

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
