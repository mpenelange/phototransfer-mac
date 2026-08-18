#!/bin/zsh
set -euo pipefail

if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
  echo "Set DEVELOPMENT_TEAM to your 10-character Apple Developer Team ID."
  exit 2
fi

script_dir="${0:A:h}"
project_root="${script_dir:h}"
archive_path="${project_root}/dist/PhotoTransfer.xcarchive"
export_path="${project_root}/dist/DeveloperID"
options_source="${project_root}/Configuration/ExportOptions-DeveloperID.plist"
options_file="${project_root}/.build/ExportOptions-DeveloperID.plist"

if [[ ! -d "${archive_path}" ]]; then
  echo "Archive not found. Run DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM} zsh Scripts/archive.sh first."
  exit 2
fi

/bin/mkdir -p "${project_root}/.build" "${export_path}"
/bin/cp "${options_source}" "${options_file}"
/usr/bin/plutil -replace teamID -string "${DEVELOPMENT_TEAM}" "${options_file}"

/usr/bin/xcodebuild \
  -exportArchive \
  -archivePath "${archive_path}" \
  -exportPath "${export_path}" \
  -exportOptionsPlist "${options_file}" \
  -allowProvisioningUpdates

echo "Exported Developer ID signed app to ${export_path}/PhotoTransfer.app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "${export_path}/PhotoTransfer.app"
