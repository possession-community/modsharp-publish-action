#!/usr/bin/env bash
# Download zip dependencies and extract them into .build/.
# Expected layout of each zip: contains top-level dirs (shared/, modules/, etc.) that
# merge cleanly into .build/.
#
# Each URL line may contain `{platform}`, which is substituted with the value of
# MSD_PLATFORM. This lets multi-platform callers point at platform-specific
# release artifacts (e.g. .../Foo-{platform}.zip resolves to .../Foo-linux-x64.zip).
#
# Inputs:
#   MSD_DEPENDENCIES — newline-separated URLs
#   MSD_PLATFORM     — platform label substituted for `{platform}` in each URL
set -euo pipefail

platform="${MSD_PLATFORM:-}"

mkdir -p .deps
while IFS= read -r url; do
  url=$(echo "$url" | tr -d '[:space:]')
  [[ -z "$url" ]] && continue
  url="${url//\{platform\}/$platform}"
  fname=$(basename "$url")
  echo "Downloading $url"
  curl -sfL "$url" -o ".deps/$fname"
  unzip -oq ".deps/$fname" -d .build/
done <<< "${MSD_DEPENDENCIES:-}"
