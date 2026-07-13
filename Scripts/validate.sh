#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIMULATOR_DESTINATION="${SWIFT_CHESS_DEMO_SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro,OS=latest}"
TEST_DERIVED_DATA="${SWIFT_CHESS_DEMO_TEST_DERIVED_DATA:-.build/xcode-swiftchessdemo}"
SOURCE_PACKAGES_DIR="${SWIFT_CHESS_DEMO_SOURCE_PACKAGES_DIR:-$TEST_DERIVED_DATA/SourcePackages}"

cd "$ROOT_DIR"

# Keep the hosted unit-test and Release-build checks in the local gate too.
"$ROOT_DIR/Scripts/github-ci.sh"

printf 'Running the local-only simulator UI test suite...\n'
xcodebuild \
  -project SwiftChessDemo.xcodeproj \
  -scheme SwiftChessDemo \
  -configuration Debug \
  -destination "$SIMULATOR_DESTINATION" \
  -derivedDataPath "$TEST_DERIVED_DATA" \
  -clonedSourcePackagesDirPath "$SOURCE_PACKAGES_DIR" \
  -only-testing:SwiftChessDemoUITests \
  test

printf 'SwiftChessDemo local validation succeeded.\n'
