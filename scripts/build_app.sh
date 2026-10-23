#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
destination="${1:-$project_dir/dist}"
configuration="${SWIFT_BUILD_CONFIGURATION:-release}"
channel="${TYPINGPET_BUILD_CHANNEL:-development}"
version="${TYPINGPET_VERSION:-0.13.0}"
build_number="${TYPINGPET_BUILD:-19}"
update_key_dir="${TYPINGPET_UPDATE_KEY_DIR:-$HOME/.config/typingpet/update-keys}"
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
update_public_key=""
if [[ -f "$update_key_dir/$channel.pub" ]]; then
    update_public_key="$(<"$update_key_dir/$channel.pub")"
elif [[ "$channel" == production ]]; then
    echo "Missing $update_key_dir/$channel.pub. Run: swift scripts/update_keys.swift generate production" >&2
    exit 1
else
    echo "Warning: no development update key. Run: swift scripts/update_keys.swift generate development"
fi
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

# Production updates trust only this Team ID. It comes from the Developer ID identity by default.
team_id="${TYPINGPET_TEAM_ID:-}"
if [[ -z "$team_id" && "$signing_identity" == "Developer ID Application:"* ]]; then
    team_id="$(sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p' <<<"$signing_identity")"
fi
if [[ "$channel" == production && -z "$team_id" ]]; then
    echo "Warning: no Developer ID Team ID. Updates are checked by the Ed25519 signature only, and macOS asks for Input Monitoring again after each update."
fi

python3 - "$contents_dir/Info.plist" "$app_name" "$executable_name" "$bundle_id" "$display_name" "$channel" \
    "$version" "$build_number" "$team_id" "$update_public_key" <<'PYPLIST'
import plistlib, sys
path, name, executable, bundle_id, display, channel, version, build, team_id, public_key = sys.argv[1:]
info = {
    "CFBundleDevelopmentRegion": "ko",
    "CFBundleDisplayName": display,
    "CFBundleExecutable": executable,
    "CFBundleIdentifier": bundle_id,
    "CFBundleIconFile": "AppIcon",
    "CFBundleInfoDictionaryVersion": "6.0",
    "CFBundleName": name,
    "CFBundlePackageType": "APPL",
    "CFBundleShortVersionString": version,
    "CFBundleVersion": build,
    "LSMinimumSystemVersion": "13.0",
    "LSUIElement": True,
    "TypingPetBuildChannel": channel,
    "NSHumanReadableCopyright": "Personal macOS build",
}
if team_id:
    info["TypingPetTeamIdentifier"] = team_id
if public_key:
    info["TypingPetUpdatePublicKey"] = public_key
if channel == "development":
    # Lets Dev builds read an update feed from a local http server.
    info["NSAppTransportSecurity"] = {"NSAllowsLocalNetworking": True}
with open(path, "wb") as file:
    plistlib.dump(info, file)
PYPLIST

if [[ "$signing_identity" == "Developer ID Application:"* ]]; then
    codesign --force --deep --options runtime --timestamp --sign "$signing_identity" "$app_dir"
    echo "Signed for distribution with $signing_identity"
else
    codesign --force --deep --options runtime --timestamp=none --sign "$signing_identity" "$app_dir"
    echo "Warning: this build is not signed with Developer ID and cannot be notarized."
fi
echo "$app_dir"
