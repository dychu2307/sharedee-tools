#!/usr/bin/env bash
# Builds a Developer ID signed, notarized DMG that installs on any Mac:
#
#   SHAREDEE_DEVELOPER_ID="Developer ID Application: Name (TEAMID)" scripts/release-dmg.sh
#
# Notarization uses a notarytool keychain profile, created once with:
#   xcrun notarytool store-credentials sharedee-notary --apple-id <Apple ID> --team-id <TEAMID>
# Set SHAREDEE_NOTARY_PROFILE to use another profile name, or SHAREDEE_NOTARIZE=0 to skip
# notarization (the DMG then only opens on other Macs after a Gatekeeper override).
#
# The result is written to dist/Sharedee-Tools-<version>.dmg.
set -euo pipefail

if [[ -z "${SHAREDEE_DEVELOPER_ID:-}" ]]; then
  echo "Set SHAREDEE_DEVELOPER_ID to a Developer ID Application signing identity." >&2
  echo "Find it with: security find-identity -v -p codesigning" >&2
  exit 2
fi
profile="${SHAREDEE_NOTARY_PROFILE:-sharedee-notary}"
notarize="${SHAREDEE_NOTARIZE:-1}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${root}"
version="$(scripts/version.sh)"
derived=".build/release-dmg"
app="${derived}/Build/Products/Release/Sharedee Tools.app"
staging="${derived}/dmg"
dmg="dist/Sharedee-Tools-${version}.dmg"

echo "==> Building Sharedee Tools ${version}"
rm -rf "${derived}"
xcodebuild -quiet -project SharedeCapture.xcodeproj -scheme SharedeCapture -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "${derived}" build CODE_SIGNING_ALLOWED=NO

echo "==> Signing with ${SHAREDEE_DEVELOPER_ID}"
# Sign nested code first, then the app, with the hardened runtime notarization requires.
if [[ -d "${app}/Contents/Frameworks" ]]; then
  find "${app}/Contents/Frameworks" -type f \( -name '*.dylib' -o -perm -u+x \) -print0 |
    xargs -0 -I{} codesign --force --timestamp --options runtime --sign "${SHAREDEE_DEVELOPER_ID}" {}
fi
codesign --force --timestamp --options runtime --sign "${SHAREDEE_DEVELOPER_ID}" "${app}"
codesign --verify --deep --strict --verbose=1 "${app}"

echo "==> Creating ${dmg}"
rm -rf "${staging}"
mkdir -p "${staging}" dist
cp -R "${app}" "${staging}/"
ln -s /Applications "${staging}/Applications"
rm -f "${dmg}"
hdiutil create -quiet -volname "Sharedee Tools ${version}" -srcfolder "${staging}" -fs HFS+ -format UDZO "${dmg}"
codesign --force --timestamp --sign "${SHAREDEE_DEVELOPER_ID}" "${dmg}"

if [[ "${notarize}" == "1" ]]; then
  echo "==> Notarizing (this usually takes a few minutes)"
  xcrun notarytool submit "${dmg}" --keychain-profile "${profile}" --wait
  xcrun stapler staple "${dmg}"
  spctl --assess --type open --context context:primary-signature --verbose=2 "${dmg}"
else
  echo "==> Skipping notarization (SHAREDEE_NOTARIZE=0)"
fi

echo "Done: ${root}/${dmg}"
