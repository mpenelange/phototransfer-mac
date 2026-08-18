#!/bin/zsh
set -euo pipefail

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "Set DEVELOPMENT_TEAM to your 10-character Apple Developer Team ID."
  echo "Example: DEVELOPMENT_TEAM=ABCDE12345 zsh Scripts/archive.sh"
  exit 2
fi

script_dir="${0:A:h}"
project_root="${script_dir:h}"
archive_path="${project_root}/dist/PhotoTransfer.xcarchive"

/bin/mkdir -p "${project_root}/dist"
/usr/bin/xcodebuild \
  -project "${project_root}/PhotoTransfer.xcodeproj" \
  -scheme PhotoTransfer \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "${archive_path}" \
  DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM}" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates \
  clean archive

echo "Created ${archive_path}"
echo "Open it in Xcode Organizer to distribute and notarize."
