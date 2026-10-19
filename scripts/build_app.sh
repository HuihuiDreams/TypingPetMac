#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
destination="${1:-$project_dir/dist}"
configuration="${SWIFT_BUILD_CONFIGURATION:-release}"
channel="${TYPINGPET_BUILD_CHANNEL:-development}"
case "$channel" in
    development)
        app_name="TypingPet Dev"
        executable_name="TypingPetDev"
        bundle_id="ing.miel.typingpet.dev"
        display_name="TypingPet Dev"
        ;;
    production)
        app_name="TypingPet"
        executable_name="TypingPet"
        bundle_id="ing.miel.typingpet"
        display_name="Typing Pet"
        ;;
    *) echo "Unknown build channel: $channel" >&2; exit 1 ;;
esac
app_dir="$destination/$app_name.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"

cd "$project_dir"
swift build -c "$configuration"

binary_path="$(swift build -c "$configuration" --show-bin-path)/TypingPet"
rm -rf "$app_dir"
mkdir -p "$macos_dir" "$resources_dir"
cp "$binary_path" "$macos_dir/$executable_name"
cp Sources/TypingPet/Resources/*.png "$resources_dir/"
cp Sources/TypingPet/Resources/*.icns "$resources_dir/"

python3 - "$contents_dir/Info.plist" "$app_name" "$executable_name" "$bundle_id" "$display_name" "$channel" <<'PYPLIST'
import plistlib, sys
path, name, executable, bundle_id, display, channel = sys.argv[1:]
with open(path, "wb") as file:
    plistlib.dump({
        "CFBundleDevelopmentRegion": "ko",
        "CFBundleDisplayName": display,
        "CFBundleExecutable": executable,
        "CFBundleIdentifier": bundle_id,
        "CFBundleIconFile": "AppIcon",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": name,
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "0.11.2",
        "CFBundleVersion": "17",
        "LSMinimumSystemVersion": "13.0",
        "LSUIElement": True,
        "TypingPetBuildChannel": channel,
        "NSHumanReadableCopyright": "Personal macOS build",
    }, file)
PYPLIST

signing_identity="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
    signing_identity="$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
        | head -n 1)"
fi
if [[ -z "$signing_identity" ]]; then
    signing_identity="$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
        | head -n 1)"
fi
if [[ -z "$signing_identity" ]]; then
    signing_identity="-"
fi

if [[ "$signing_identity" == "Developer ID Application:"* ]]; then
    codesign --force --deep --options runtime --timestamp --sign "$signing_identity" "$app_dir"
    echo "Signed for distribution with $signing_identity"
else
    codesign --force --deep --options runtime --timestamp=none --sign "$signing_identity" "$app_dir"
    echo "Warning: this build is not signed with Developer ID and cannot be notarized."
fi
echo "$app_dir"
