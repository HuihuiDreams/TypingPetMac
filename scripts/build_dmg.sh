#!/bin/zsh
set -euo pipefail

# Package an already released, notarized app without rebuilding or re-signing it.
# Usage: build_dmg.sh <TypingPet.app> <output.dmg>
project_dir="${0:A:h:h}"
app_path="${1:?Usage: build_dmg.sh <TypingPet.app> <output.dmg>}"
app_path="${app_path:A}"
output="${2:?Usage: build_dmg.sh <TypingPet.app> <output.dmg>}"
output="${output:A}"
[[ "$output" == *.dmg ]] || { echo 'Output must end in .dmg' >&2; exit 1; }
[[ ! -e "$output" && ! -e "$output.sha256" ]] || { echo 'Refusing to overwrite an existing DMG or checksum.' >&2; exit 1; }
info="$app_path/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info")" == ing.miel.typingpet ]] || exit 1
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")"
identity="$(codesign -dv --verbose=4 "$app_path" 2>&1 | sed -n 's/^Authority=\(Developer ID Application:.*\)$/\1/p' | head -n 1)"
[[ -n "$identity" ]] || { echo 'The app needs a Developer ID signature.' >&2; exit 1; }
codesign --verify --deep --strict "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute "$app_path"

work_dir="$(mktemp -d)"
mounted=0
cleanup() {
    if (( mounted )); then hdiutil detach "$work_dir/mounted" >/dev/null; fi
    rm -rf "$work_dir"
}
trap cleanup EXIT
mkdir -p "${output:h}"
# A 144 dpi TIFF displays at 760 × 440 points while retaining Retina detail.
sips -z 880 1520 -s format tiff -s dpiWidth 144 -s dpiHeight 144 \
    "$project_dir/packaging/dmg/background.png" --out "$work_dir/background.tiff" >/dev/null
uv run --python 3.12 --with 'dmgbuild==1.6.7' dmgbuild \
    -s "$project_dir/packaging/dmg/settings.py" -D "app=$app_path" -D "background=$work_dir/background.tiff" \
    "Typing Pet $version" "$output"
codesign --sign "$identity" --timestamp "$output"
xcrun notarytool submit "$output" --keychain-profile "${NOTARY_KEYCHAIN_PROFILE:-typingpet-notary}" \
    --wait --timeout "${NOTARY_TIMEOUT:-30m}" --output-format json > "$output.notary-result.json"
python3 - "$output.notary-result.json" <<'PY'
import json, sys
with open(sys.argv[1]) as file:
    result = json.load(file)
print(f"DMG notarization {result.get('id')}: {result.get('status')}")
if result.get('status') != 'Accepted':
    raise SystemExit('DMG notarization was not accepted; inspect the saved submission before retrying.')
PY
xcrun stapler staple "$output"
xcrun stapler validate "$output"
codesign --verify --strict "$output"
spctl --assess --type open --context context:primary-signature --verbose=2 "$output"
hdiutil verify "$output"
hdiutil attach -readonly -nobrowse -mountpoint "$work_dir/mounted" "$output"
mounted=1
[[ "$(readlink "$work_dir/mounted/Applications")" == /Applications ]]
diff -qr "$app_path" "$work_dir/mounted/TypingPet.app"
codesign --verify --deep --strict "$work_dir/mounted/TypingPet.app"
xcrun stapler validate "$work_dir/mounted/TypingPet.app"
spctl --assess --type execute --verbose=2 "$work_dir/mounted/TypingPet.app"
hdiutil detach "$work_dir/mounted"
mounted=0
(cd "${output:h}" && shasum -a 256 "${output:t}" > "${output:t}.sha256")
cat "$output.sha256"
