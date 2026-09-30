#!/usr/bin/env bash
# Prints the app version derived from git, following Semantic Versioning and Conventional Commits.
#
#   scripts/version.sh            -> 1.2.0
#   scripts/version.sh --build    -> 42   (number of commits, always increasing)
#   scripts/version.sh --changes  -> commit subjects since the last release tag
#
# The version starts from the latest `vX.Y.Z` tag and is bumped by the commits made since:
#   feat!: / fix!: / "BREAKING CHANGE" in the body  -> major
#   feat:                                           -> minor
#   anything else (fix:, perf:, docs:, ...)         -> patch
# With no commits since the tag, the tag's own version is printed. Without git history (for
# example a source archive) it falls back to MARKETING_VERSION in project.yml.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="${1:---version}"

fallback_version() {
  sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*//p' "${root}/project.yml" | head -1
}

if ! git -C "${root}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  case "${mode}" in
    --build) echo 1 ;;
    --changes) ;;
    *) fallback_version ;;
  esac
  exit 0
fi

if [[ "${mode}" == "--build" ]]; then
  git -C "${root}" rev-list --count HEAD
  exit 0
fi

tag="$(git -C "${root}" describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' 2>/dev/null || true)"
if [[ -n "${tag}" ]]; then
  range="${tag}..HEAD"
  base="${tag#v}"
else
  range="HEAD"
  base="0.0.0"
fi

if [[ "${mode}" == "--changes" ]]; then
  git -C "${root}" log --no-merges --format='%s' "${range}"
  exit 0
fi

IFS=. read -r major minor patch <<<"${base}"
bump=""
while IFS= read -r -d $'\x1e' commit; do
  [[ -z "${commit//[[:space:]]/}" ]] && continue
  subject="$(printf '%s\n' "${commit}" | sed -n '/[^[:space:]]/{p;q;}')"
  if [[ "${subject}" =~ ^[a-z]+(\([^\)]*\))?!: ]] || grep -Eq '^[[:space:]]*BREAKING[ -]CHANGE' <<<"${commit}"; then
    bump="major"
    break
  elif [[ "${subject}" =~ ^feat(\([^\)]*\))?: ]]; then
    bump="minor"
  elif [[ -z "${bump}" ]]; then
    bump="patch"
  fi
done < <(git -C "${root}" log --no-merges --format='%B%x1e' "${range}")

case "${bump}" in
  major) echo "$((major + 1)).0.0" ;;
  minor) echo "${major}.$((minor + 1)).0" ;;
  patch) echo "${major}.${minor}.$((patch + 1))" ;;
  *) echo "${major}.${minor}.${patch}" ;;
esac
