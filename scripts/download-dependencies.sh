#!/usr/bin/env bash
# Download zip dependencies and extract them into .build/.
# Expected layout of each zip: contains top-level dirs (shared/, modules/, etc.) that
# merge cleanly into .build/.
#
# Inputs:
#   MSD_DEPENDENCIES — newline-separated URLs
set -euo pipefail

mkdir -p .deps
while IFS= read -r url; do
  url=$(echo "$url" | tr -d '[:space:]')
  [[ -z "$url" ]] && continue
  fname=$(basename "$url")
  echo "Downloading $url"
  curl -sfL "$url" -o ".deps/$fname"
  unzip -oq ".deps/$fname" -d .build/
done <<< "${MSD_DEPENDENCIES:-}"
