#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_root="${script_dir:h}"
app_path="${1:-${project_root}/dist/DeveloperID/PhotoTransfer.app}"
profile="${NOTARY_PROFILE:-PhotoTransferNotary}"
work_dir="$(/usr/bin/mktemp -d /tmp/PhotoTransfer-notary.XXXXXX)"
archive_path="${work_dir}/PhotoTransfer.zip"

if [[ ! -d "${app_path}" ]]; then
  echo "App not found at ${app_path}"
  exit 2
fi

/usr/bin/ditto -c -k --keepParent "${app_path}" "${archive_path}"
/usr/bin/xcrun notarytool submit "${archive_path}" --keychain-profile "${profile}" --wait
/usr/bin/xcrun stapler staple "${app_path}"
/usr/bin/xcrun stapler validate "${app_path}"
/usr/sbin/spctl --assess --type execute --verbose=4 "${app_path}"

echo "Notarized and stapled ${app_path}"
echo "Temporary submission archive: ${archive_path}"
