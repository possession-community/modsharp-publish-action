#!/usr/bin/env bash
# Create a zip from paths under .build/.
# Re-used by both main and extended artifacts.
#
# Inputs:
#   MSD_ZIP_NAME     output base name (no extension) — written to dist/<name>.zip
#   MSD_ZIP_INCLUDE  space/newline separated paths under .build to include
set -euo pipefail

name="${MSD_ZIP_NAME:?MSD_ZIP_NAME required}"
raw_includes="${MSD_ZIP_INCLUDE:?MSD_ZIP_INCLUDE required}"
includes=$(echo "$raw_includes" | tr '\n' ' ' | tr -s ' ')

mkdir -p dist
args=()
for item in $includes; do
  if [[ -e ".build/$item" ]]; then
    args+=("$item")
  else
    echo "::warning::.build/$item not found, skipping from $name zip"
  fi
done

if [[ ${#args[@]} -eq 0 ]]; then
  echo "::error::no paths to include in $name zip"
  exit 1
fi

(cd .build && zip -r "../dist/${name}.zip" "${args[@]}")
echo "Created dist/${name}.zip"
