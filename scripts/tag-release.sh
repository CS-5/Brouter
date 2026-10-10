#!/usr/bin/env bash
# Creates and pushes the next CalVer tag: vYYYY.M.N, where N counts releases within the month.
# Month is unpadded so the version stays valid as CFBundleShortVersionString.
set -euo pipefail

prefix="v$(date +%Y).$(date +%-m)"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree is dirty" >&2
  exit 1
fi

git fetch --tags --quiet origin

last=$(git tag --list "${prefix}.*" | sed "s/^${prefix}\.//" | sort -n | tail -1)
tag="${prefix}.$((${last:--1} + 1))"

read -r -p "Tag $(git rev-parse --short HEAD) as ${tag} and push? [y/N] " answer
[[ "$answer" == [yY] ]] || exit 1

git tag -a "$tag" -m "$tag"
git push origin "$tag"
