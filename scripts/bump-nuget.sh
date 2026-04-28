#!/usr/bin/env bash
# bump-nuget.sh — check NuGet for the latest version of a package and update
# <PackageReference Include="..." Version="..."/> entries in csproj files.
#
# Only handles the inline-attribute form (most common). Attribute order
# (Include-before-Version vs Version-before-Include) does not matter.
#
# Inputs (env):
#   MSD_PACKAGE_ID         — NuGet package ID (required)
#   MSD_CSPROJ_PATHS       — newline/space-separated csproj paths
#                            (optional; default: all *.csproj under repo)
#   MSD_INCLUDE_PRERELEASE — "true" to consider prerelease versions (default: false)
#
# Outputs ($GITHUB_OUTPUT):
#   current-version — version before bump (first referencing csproj wins)
#   latest-version  — latest version on NuGet
#   updated         — "true" if any file was modified
#   files-changed   — newline-separated list of modified paths (multiline output)
set -euo pipefail

pkg="${MSD_PACKAGE_ID:?MSD_PACKAGE_ID required}"
pkg_lower=$(echo "$pkg" | tr '[:upper:]' '[:lower:]')
paths_raw="${MSD_CSPROJ_PATHS:-}"
include_pre="${MSD_INCLUDE_PRERELEASE:-false}"

if [[ -z "${paths_raw// /}" ]]; then
  mapfile -t files < <(find . -type f -name '*.csproj' -not -path '*/node_modules/*' -not -path '*/bin/*' -not -path '*/obj/*' | sort)
else
  mapfile -t files < <(echo "$paths_raw" | tr '\n' ' ' | xargs -n1)
fi

if [[ "${#files[@]}" -eq 0 ]]; then
  echo "::error::no .csproj files found"
  exit 1
fi

versions_json=$(curl -fsSL "https://api.nuget.org/v3-flatcontainer/${pkg_lower}/index.json")
if [[ "$include_pre" == "true" ]]; then
  latest=$(echo "$versions_json" | jq -r '.versions | last')
else
  latest=$(echo "$versions_json" | jq -r '[.versions[] | select(test("-") | not)] | last')
fi

if [[ -z "$latest" || "$latest" == "null" ]]; then
  echo "::error::could not determine latest version for $pkg"
  exit 1
fi

echo "Latest version of $pkg on NuGet: $latest"

# Escape dots so the package ID is matched literally in regex. The shell
# eats one layer of backslashes, so four are needed to deliver a single
# literal backslash before the matched char.
pkg_esc=$(printf '%s' "$pkg" | sed 's/\./\\\\./g')

changed=()
current=""

for f in "${files[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "::warning::$f not found, skipping"
    continue
  fi

  cur=$(grep -oE "<PackageReference[^>]*Include=\"${pkg_esc}\"[^>]*Version=\"[^\"]+\"" "$f" \
        | grep -oE 'Version="[^"]+"' | sed -E 's/Version="([^"]+)"/\1/' | head -n1 || true)
  if [[ -z "$cur" ]]; then
    cur=$(grep -oE "<PackageReference[^>]*Version=\"[^\"]+\"[^>]*Include=\"${pkg_esc}\"" "$f" \
          | grep -oE 'Version="[^"]+"' | sed -E 's/Version="([^"]+)"/\1/' | head -n1 || true)
  fi
  if [[ -z "$cur" ]]; then
    continue
  fi

  if [[ -z "$current" ]]; then
    current="$cur"
  fi

  if [[ "$cur" == "$latest" ]]; then
    echo "$f: already at $latest"
    continue
  fi

  echo "$f: $cur -> $latest"

  sed -i -E \
    -e "s|(<PackageReference[^>]*Include=\"${pkg_esc}\"[^>]*Version=\")[^\"]+(\")|\1${latest}\2|g" \
    -e "s|(<PackageReference[^>]*Version=\")[^\"]+(\"[^>]*Include=\"${pkg_esc}\")|\1${latest}\2|g" \
    "$f"

  changed+=("$f")
done

updated="false"
[[ "${#changed[@]}" -gt 0 ]] && updated="true"

{
  echo "current-version=${current}"
  echo "latest-version=${latest}"
  echo "updated=${updated}"
  echo "files-changed<<MSD_EOF"
  for f in "${changed[@]}"; do echo "$f"; done
  echo "MSD_EOF"
} >> "$GITHUB_OUTPUT"

echo "updated=${updated} current=${current} latest=${latest}"
