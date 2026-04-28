#!/usr/bin/env bash
# bump-version.sh — read <Version> from a props file, increment it per
# MSD_BUMP_TYPE, and write the new value back in place.
#
# Inputs (env):
#   MSD_VERSION_FILE — path to props/xml file (required)
#   MSD_BUMP_TYPE    — patch | minor | major (required)
#
# Outputs ($GITHUB_OUTPUT):
#   current-version — version before bump
#   new-version     — version after bump
set -euo pipefail

f="${MSD_VERSION_FILE:?MSD_VERSION_FILE required}"
bump="${MSD_BUMP_TYPE:?MSD_BUMP_TYPE required}"

if ! command -v xmllint >/dev/null 2>&1; then
  sudo apt-get install -y --no-install-recommends libxml2-utils >/dev/null
fi

current=$(xmllint --xpath 'string(//Project/PropertyGroup/Version)' "$f" | tr -d '[:space:]')
if [[ -z "$current" ]]; then
  echo "::error::<Version> not found in $f"
  exit 1
fi

IFS='.' read -r major minor patch <<< "$current"
if [[ -z "${major:-}" || -z "${minor:-}" || -z "${patch:-}" ]]; then
  echo "::error::version '$current' is not in MAJOR.MINOR.PATCH form"
  exit 1
fi

# Strip prerelease / build metadata from the patch segment (e.g. 1.2.3-rc1).
patch_num="${patch%%-*}"
patch_num="${patch_num%%+*}"

case "$bump" in
  patch) new="${major}.${minor}.$((patch_num + 1))" ;;
  minor) new="${major}.$((minor + 1)).0" ;;
  major) new="$((major + 1)).0.0" ;;
  *) echo "::error::MSD_BUMP_TYPE must be patch|minor|major (got: $bump)"; exit 1 ;;
esac

# Escape regex metachars in the current value so it's matched literally.
# The shell eats one layer of backslashes, so `\\\\&` in single quotes
# reaches sed as `\\&` which outputs `\` followed by the matched char.
cur_esc=$(printf '%s' "$current" | sed 's/[].[\*^$()+?{}|/]/\\\\&/g')

# Replace only the first <Version>...</Version> under root PropertyGroup.
sed -i -E "0,/(<Version>)${cur_esc}(<\/Version>)/s//\1${new}\2/" "$f"

after=$(xmllint --xpath 'string(//Project/PropertyGroup/Version)' "$f" | tr -d '[:space:]')
if [[ "$after" != "$new" ]]; then
  echo "::error::version update failed (got '$after', expected '$new')"
  exit 1
fi

{
  echo "current-version=${current}"
  echo "new-version=${new}"
} >> "$GITHUB_OUTPUT"

echo "Bumped $f: $current -> $new"
