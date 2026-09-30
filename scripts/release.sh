#!/usr/bin/env bash
# Cuts a release: adds the commits since the last tag to CHANGELOG.md, commits it, and tags
# the result `vX.Y.Z` with the version from scripts/version.sh. Pushing is left to you:
#
#   scripts/release.sh
#   git push origin main --follow-tags
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${root}"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit or stash your changes before releasing." >&2
  exit 1
fi

version="$(scripts/version.sh)"
if git rev-parse -q --verify "refs/tags/v${version}" >/dev/null; then
  echo "v${version} is already tagged; there are no new commits to release." >&2
  exit 1
fi

section() {
  local title="$1" pattern="$2" lines
  lines="$(scripts/version.sh --changes | grep -E "${pattern}" | sed -E 's/^[a-z]+(\([^)]*\))?!?: */- /' || true)"
  [[ -n "${lines}" ]] && printf '### %s\n\n%s\n\n' "${title}" "${lines}"
  return 0
}

notes="$(
  section "Breaking changes" '^[a-z]+(\([^)]*\))?!:'
  section "Features" '^feat(\([^)]*\))?:'
  section "Fixes" '^fix(\([^)]*\))?:'
  section "Other changes" '^(perf|refactor|docs|build|ci|style|test)(\([^)]*\))?:'
)"

entry="## ${version} - $(date +%Y-%m-%d)"$'\n\n'"${notes}"
{
  sed -n '1,/^## /{/^## /!p;}' CHANGELOG.md
  printf '%s\n\n' "${entry%$'\n'}"
  sed -n '/^## /,$p' CHANGELOG.md
} > CHANGELOG.md.tmp
mv CHANGELOG.md.tmp CHANGELOG.md

git add CHANGELOG.md
git commit -m "chore(release): v${version}"
git tag -a "v${version}" -m "Sharedee Tools ${version}"
echo "Tagged v${version}. Push with: git push origin main --follow-tags"
