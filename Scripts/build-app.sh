#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_root="${script_dir:h}"
derived_data="${project_root}/.build/xcode"
product="${derived_data}/Build/Products/Release/PhotoTransfer.app"
output_dir="${project_root}/dist"
output_app="${output_dir}/PhotoTransfer.app"

/usr/bin/xcodebuild \
  -project "${project_root}/PhotoTransfer.xcodeproj" \
  -scheme PhotoTransfer \
  -configuration Release \
  -destination "platform=macOS" \
  -derivedDataPath "${derived_data}" \
  CODE_SIGNING_ALLOWED=NO \
  build

/bin/mkdir -p "${output_dir}"
if [[ -e "${output_app}" ]]; then
  /bin/rm -rf "${output_app}"
fi
/usr/bin/ditto "${product}" "${output_app}"
/usr/bin/codesign --force --sign - --options runtime --timestamp=none "${output_app}"

echo "Built ${output_app}"
/usr/bin/codesign --verify --deep --strict --verbose=2 "${output_app}"
