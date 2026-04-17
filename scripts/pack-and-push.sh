#!/usr/bin/env bash
# Pack each project directory and push the resulting nupkg(s) to NuGet.org.
# Uses a glob against the resolved <Version> so the push works regardless of
# whether <PackageId> matches the directory name.
#
# Inputs:
#   MSD_NUGET_PROJECT_DIRS — space/newline separated directories
#   MSD_VERSION            — version string to match *.${MSD_VERSION}.nupkg
#   NUGET_API_KEY          — secret
set -euo pipefail

if [[ -z "${NUGET_API_KEY:-}" ]]; then
  echo "::error::NUGET_API_KEY secret is required when nuget-project-dirs is set"
  exit 1
fi

dirs=$(echo "${MSD_NUGET_PROJECT_DIRS:-}" | tr '\n' ' ' | tr -s ' ')
version="${MSD_VERSION:?MSD_VERSION required}"

for dir in $dirs; do
  echo "::group::NuGet: $dir"
  (
    cd "$dir"
    dotnet restore
    dotnet build -c Release -p:DebugType=None -p:DebugSymbols=false
    dotnet pack --configuration Release
    shopt -s nullglob
    pushed=0
    for pkg in bin/Release/*."${version}".nupkg; do
      dotnet nuget push "$pkg" --skip-duplicate \
        --api-key "$NUGET_API_KEY" \
        --source https://api.nuget.org/v3/index.json
      pushed=1
    done
    if [[ $pushed -eq 0 ]]; then
      echo "::error::no *.${version}.nupkg found in $dir/bin/Release"
      exit 1
    fi
  )
  echo "::endgroup::"
done
