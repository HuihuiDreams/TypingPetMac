#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_path="${1:-$project_dir/dist/TypingPet.app}"
output_zip="${2:-$project_dir/dist/TypingPet-macOS.zip}"
keychain_profile="${NOTARY_KEYCHAIN_PROFILE:-typingpet-notary}"

if [[ ! -d "$app_path" ]]; then
  echo "Error: app bundle not found at $app_path" >&2
  exit 1
fi

app_path="${app_path:A}"
output_zip="${output_zip:A}"

identity="$(codesign -dv --verbose=4 "$app_path" 2>&1 | sed -n 's/^Authority=\(Developer ID Application:.*\)$/\1/p' | head -n 1)"
if [[ -z "$identity" ]]; then
    echo "Error: app must be signed with a Developer ID Application certificate." >&2
    exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
submission_zip="$work_dir/TypingPet-notary.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$submission_zip"
xcrun notarytool submit "$submission_zip" --keychain-profile "$keychain_profile" --wait
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=2 "$app_path"

app_name="${app_path:t}"
destination="${app_path:h}"
readme_source="$project_dir/README.txt"

if [[ -f "$readme_source" ]]; then
    cp "$readme_source" "$destination/README.txt"
fi
rm -f "$output_zip"
(
    cd "$destination"
    if [[ -f "README.txt" ]]; then
        zip -r -y -q "$output_zip" "$app_name" "README.txt" -x "*.DS_Store*"
    else
        zip -r -y -q "$output_zip" "$app_name" -x "*.DS_Store*"
    fi
)
echo "$output_zip"
shasum -a 256 "$output_zip"
