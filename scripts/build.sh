#!/usr/bin/env bash
# ModSharp plugin build — port of build.bat to bash.
# Publishes shared projects to .build/shared/<name>, main projects to .build/modules/<name>,
# copies gamedata, strips ModSharp-provided DLLs, renames appsettings.json.
#
# Inputs via env:
#   MSD_PLATFORM              runtime (-r), e.g. linux-x64
#   MSD_TFM                   target framework moniker (-f)
#   MSD_PROJECTS              main module projects
#   MSD_SHARED_P1             base shared projects
#   MSD_SHARED_P2             shared projects depending on phase 1
#   MSD_SHARED_BUILD_ONLY     shared projects built but not cleaned
#   MSD_DLLS_TO_REMOVE        extra DLL names to strip (space/newline sep)
#   MSD_DLLS_TO_REMOVE_FILE   path to a file listing extra DLLs
#   MSD_BUILTIN_DLLS_FILE     path to the built-in defaults list (optional)
#   MSD_SHARED_DLLS_TO_REMOVE shared DLLs to strip from module outputs
#   MSD_SHARED_DLLS_TO_REMOVE_FILE  path to a file listing shared DLLs
#   MSD_CUSTOM_DIRS           directories to copy into each module output
set -euo pipefail

normalize() { echo "$1" | tr '\n' ' ' | tr -s ' '; }
read_list_file() {
  local f=$1
  [[ -z "$f" || ! -f "$f" ]] && return
  sed 's/#.*$//' "$f"
}

PLATFORM="${MSD_PLATFORM}"
TFM="${MSD_TFM}"
PROJECTS=$(normalize "${MSD_PROJECTS:-}")
SHARED_P1=$(normalize "${MSD_SHARED_P1:-}")
SHARED_P2=$(normalize "${MSD_SHARED_P2:-}")
SHARED_BUILD_ONLY=$(normalize "${MSD_SHARED_BUILD_ONLY:-}")
DLLS_TO_REMOVE=$(normalize "$(read_list_file "${MSD_BUILTIN_DLLS_FILE:-}") ${MSD_DLLS_TO_REMOVE:-} $(read_list_file "${MSD_DLLS_TO_REMOVE_FILE:-}")")
SHARED_DLLS_TO_REMOVE=$(normalize "${MSD_SHARED_DLLS_TO_REMOVE:-} $(read_list_file "${MSD_SHARED_DLLS_TO_REMOVE_FILE:-}")")
CUSTOM_DIRS=$(normalize "${MSD_CUSTOM_DIRS:-}")

rm -rf .build/gamedata .build/modules .build/shared

publish_proj() {
  local proj=$1 outdir=$2
  dotnet publish "$proj/$proj.csproj" -f "$TFM" -r "$PLATFORM" \
    --disable-build-servers --no-self-contained -c Release \
    -p:DebugType=None -p:DebugSymbols=false \
    --output "$outdir"
}

build_shared() {
  local proj=$1 phase=$2
  [[ -f "$proj/$proj.csproj" ]] || { echo "::warning::$proj/$proj.csproj not found, skipping"; return; }
  echo "::group::Shared ($phase): $proj"
  publish_proj "$proj" ".build/shared/$proj"
  for dll in $DLLS_TO_REMOVE; do rm -f ".build/shared/$proj/$dll"; done
  echo "::endgroup::"
}

build_shared_build_only() {
  local proj=$1
  [[ -f "$proj/$proj.csproj" ]] || return
  echo "::group::Shared (build-only): $proj"
  publish_proj "$proj" ".build/shared/$proj"
  echo "::endgroup::"
}

build_main() {
  local proj=$1
  [[ -f "$proj/$proj.csproj" ]] || { echo "::warning::$proj/$proj.csproj not found, skipping"; return; }
  local outdir=".build/modules/$proj"
  echo "::group::Main: $proj"
  publish_proj "$proj" "$outdir"
  rm -f "$outdir/$proj.pdb"
  for dll in $DLLS_TO_REMOVE; do rm -f "$outdir/$dll"; done
  for dll in $SHARED_DLLS_TO_REMOVE; do rm -f "$outdir/$dll"; done
  if [[ -f "$outdir/appsettings.json" ]]; then
    mv "$outdir/appsettings.json" "$outdir/appsettings.example.json"
  fi
  for cdir in $CUSTOM_DIRS; do
    if [[ -d "$cdir" ]]; then
      mkdir -p "$outdir/$cdir"
      cp -r "$cdir/." "$outdir/$cdir/"
    fi
  done
  echo "::endgroup::"
}

for p in $SHARED_P1; do build_shared "$p" "phase1"; done
for p in $SHARED_P2; do build_shared "$p" "phase2"; done
for p in $SHARED_BUILD_ONLY; do build_shared_build_only "$p"; done
for p in $PROJECTS; do build_main "$p"; done

if [[ -d gamedata ]]; then
  mkdir -p .build/gamedata
  cp -r gamedata/. .build/gamedata/
fi
