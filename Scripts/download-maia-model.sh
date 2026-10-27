#!/usr/bin/env bash
# Licensed under the MIT License. See LICENSE and THIRD_PARTY.md.
set -euo pipefail

cd "$(dirname "$0")/.."
model_file="Resources/Models/maia3-79m.onnx"
expected_bytes=316034244
expected_sha="3454b03ae78baa64a87b345fdb1a457265d912caec531039b074f07eda0d8010"
model_url="https://media.githubusercontent.com/media/Dash1971/maia-chess-android/5f6743eed5491d2e8413fe0dfd1f8ef612d0aa84/assets/models/maia3-79m.onnx"

verified() {
    [[ -f "$1" ]] &&
        [[ "$(wc -c < "$1" | tr -d ' ')" == "$expected_bytes" ]] &&
        [[ "$(shasum -a 256 "$1" | awk '{print $1}')" == "$expected_sha" ]]
}

if verified "$model_file"; then
    printf '%s\n' 'Pinned Maia model is already verified.'
    exit 0
fi

mkdir -p Resources/Models
download_file="$(mktemp Resources/Models/.download.XXXXXX)"
trap 'rm -f "$download_file"' EXIT
curl --fail --location --retry 2 --show-error --output "$download_file" "$model_url"
if ! verified "$download_file"; then
    printf '%s\n' 'Maia model size or SHA-256 does not match the pinned export.' >&2
    exit 1
fi
mv "$download_file" "$model_file"
printf '%s\n' 'Maia model downloaded and verified.'
