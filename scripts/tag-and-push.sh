#!/usr/bin/env bash
# tag-and-push.sh — commit the modified version file and push an annotated
# tag. Fails fast if the tag already exists.
#
# Note: the calling workflow must have used a PAT at checkout time if it
# expects this tag push to trigger downstream workflows — pushes authored
# via GITHUB_TOKEN do not fire other workflows.
#
# Inputs (env):
#   MSD_VERSION_FILE — path of the file to stage & commit (required)
#   MSD_NEW_VERSION  — new version string, without tag prefix (required)
#   MSD_TAG_PREFIX   — tag prefix, e.g. "v" (default: "v")
#   MSD_COMMIT_MSG   — commit message (default: "chore: release <tag>")
set -euo pipefail

f="${MSD_VERSION_FILE:?MSD_VERSION_FILE required}"
new="${MSD_NEW_VERSION:?MSD_NEW_VERSION required}"
prefix="${MSD_TAG_PREFIX:-v}"
tag="${prefix}${new}"
msg="${MSD_COMMIT_MSG:-chore: release ${tag}}"

git fetch --tags --quiet
if git rev-parse --verify "refs/tags/$tag" >/dev/null 2>&1; then
  echo "::error::tag $tag already exists"
  exit 1
fi

git config user.name  'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'

git add -- "$f"
git commit -m "$msg"
git tag -a "$tag" -m "Release $tag"

# Push commit first so the tag points at a ref reachable from the branch.
git push origin HEAD
git push origin "$tag"

echo "Released $tag."
