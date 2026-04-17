#!/usr/bin/env bash
# Validate that each csproj under MSD_NUGET_PROJECT_DIRS has an explicit <PackageId>.
# Fails if any csproj is missing it — prevents publishing packages with auto-derived ids
# that could silently change when the csproj is renamed.
#
# Inputs:
#   MSD_NUGET_PROJECT_DIRS — space/newline separated project directories
set -euo pipefail

dirs=$(echo "${MSD_NUGET_PROJECT_DIRS:-}" | tr '\n' ' ' | tr -s ' ')
if [[ -z "${dirs// /}" ]]; then
  echo "No nuget-project-dirs configured, skipping validation."
  exit 0
fi

failed=0
for dir in $dirs; do
  if [[ ! -d "$dir" ]]; then
    echo "::error::nuget-project-dirs: directory '$dir' not found"
    failed=1
    continue
  fi

  shopt -s nullglob
  csproj_files=("$dir"/*.csproj)
  shopt -u nullglob

  if [[ ${#csproj_files[@]} -eq 0 ]]; then
    echo "::error::$dir: no .csproj file found"
    failed=1
    continue
  fi

  for csproj in "${csproj_files[@]}"; do
    if grep -Eq '<PackageId[>[:space:]]' "$csproj"; then
      pkg_id=$(sed -n 's|.*<PackageId>\([^<]*\)</PackageId>.*|\1|p' "$csproj" | head -1)
      echo "$csproj: PackageId=$pkg_id"
    else
      echo "::error file=$csproj::<PackageId> is not explicitly set. Add <PackageId>YourPackageName</PackageId> to the csproj."
      failed=1
    fi
  done
done

[[ $failed -eq 0 ]]
