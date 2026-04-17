#!/usr/bin/env bash
# Extract <Version> from a props/xml file and emit it to GITHUB_OUTPUT as "version".
#
# Inputs:
#   MSD_PROPS_FILE — path to config.props (or similar) with //Project/PropertyGroup/Version
set -euo pipefail

f="${MSD_PROPS_FILE:?MSD_PROPS_FILE required}"

if ! command -v xmllint >/dev/null 2>&1; then
  sudo apt-get install -y --no-install-recommends libxml2-utils >/dev/null
fi

version=$(xmllint --xpath 'string(//Project/PropertyGroup/Version)' "$f" | tr -d '[:space:]')
if [[ -z "$version" ]]; then
  echo "::error::<Version> not found in $f"
  exit 1
fi

echo "version=$version" >> "$GITHUB_OUTPUT"
echo "Detected version: $version"
