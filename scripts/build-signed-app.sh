#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${SHAREDEE_SIGNING_IDENTITY:-}" ]]; then
  echo "Set SHAREDEE_SIGNING_IDENTITY to a stable Apple Development or Developer ID certificate." >&2
  echo "Find available identities with: security find-identity -v -p codesigning" >&2
  exit 2
fi

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
derived_data="${SHAREDEE_DERIVED_DATA_PATH:-${project_dir}/.build/DerivedData}"
source_app="${derived_data}/Build/Products/Release/Sharedee Tools.app"
output_app="${project_dir}/Sharedee Tools.app"

xcodebuild -quiet \
  -project "${project_dir}/SharedeCapture.xcodeproj" \
  -scheme SharedeCapture \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "${derived_data}" \
  build CODE_SIGNING_ALLOWED=NO

codesign --force --deep --options runtime --sign "${SHAREDEE_SIGNING_IDENTITY}" "${source_app}"
codesign --verify --deep --strict "${source_app}"
rsync -a --delete "${source_app}/" "${output_app}/"
codesign --verify --deep --strict "${output_app}"

lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "${lsregister}" ]]; then
  "${lsregister}" -u "${source_app}" 2>/dev/null || true
  "${lsregister}" -f "${output_app}"
fi

echo "Built and signed ${output_app}"
codesign --display -r - "${output_app}"
