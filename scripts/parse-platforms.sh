#!/usr/bin/env bash
# Parse MSD_PLATFORMS (space/newline separated) into:
#   list      — JSON array, fed into strategy.matrix.platform via fromJSON
#   is-multi  — "true" when >1 platform (triggers name suffixing)
# Writes both to $GITHUB_OUTPUT.
set -euo pipefail

raw="${MSD_PLATFORMS:-linux-x64}"
items=$(echo "$raw" | tr '\n' ' ' | xargs -n1)
if [[ -z "${items// /}" ]]; then
  items="linux-x64"
fi

count=$(echo "$items" | wc -l | tr -d ' ')
if [[ "$count" -gt 1 ]]; then
  multi=true
else
  multi=false
fi

list=$(echo "$items" | jq -R . | jq -s -c .)

{
  echo "list=$list"
  echo "is-multi=$multi"
} >> "$GITHUB_OUTPUT"
echo "Platforms: $list (multi=$multi)"
