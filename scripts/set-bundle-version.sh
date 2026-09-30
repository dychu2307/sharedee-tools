#!/usr/bin/env bash
# Xcode build phase: writes the git-derived version and build number into the built Info.plist.
# See scripts/version.sh for how the version is computed.
set -euo pipefail

plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
version="$("${SRCROOT}/scripts/version.sh")"
build="$("${SRCROOT}/scripts/version.sh" --build)"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${version}" "${plist}"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${build}" "${plist}"
echo "Sharedee Tools ${version} (${build})"
