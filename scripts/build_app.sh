#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
mkdir -p "$project_dir/.build/tmp"
export TMPDIR="$project_dir/.build/tmp"
destination="${1:-$project_dir/dist}"
configuration="${SWIFT_BUILD_CONFIGURATION:-release}"
channel="${TYPINGPET_BUILD_CHANNEL:-development}"
version="${TYPINGPET_VERSION:-$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$project_dir/version.json")}"
build_number="${TYPINGPET_BUILD:-$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["build"])' "$project_dir/version.json")}"
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
    echo "Missing $update_key_dir/$channel.pub. Restore the original update public key for released builds." >&2
    exit 1
else
    echo "Warning: no development update key. Run: swift scripts/update_keys.swift generate development"
fi
app_dir="$destination/$app_name.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"

cd "$project_dir"
if [[ -z "${SDKROOT:-}" && -d "/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk" ]]; then
    export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
fi
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$project_dir/.build/module-cache}"

build_args=(-c "$configuration" --disable-sandbox)
if [[ "$channel" == production ]]; then
    # Distribution bundles carry their resources; exclude local source resource lookup.
    build_args+=(-Xswiftc -D -Xswiftc TYPINGPET_DISTRIBUTION)
fi
swift build "${build_args[@]}"

binary_path="$(swift build "${build_args[@]}" --show-bin-path)/TypingPet"
rm -rf "$app_dir"
mkdir -p "$macos_dir" "$resources_dir"
cp "$binary_path" "$macos_dir/$executable_name"
if [[ "$channel" == production && "$configuration" == release ]]; then
    xcrun strip -S "$macos_dir/$executable_name"
fi
cp Sources/TypingPet/Resources/*.png "$resources_dir/"
cp Sources/TypingPet/Resources/*.icns "$resources_dir/"
cp -R Sources/TypingPet/Localization/*.lproj "$resources_dir/"

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

entitlements_file="$project_dir/Sources/TypingPet/Resources/TypingPet.entitlements"
if [[ ! -f "$entitlements_file" ]]; then
    echo "Error: missing entitlements file at $entitlements_file" >&2
    exit 1
fi

# Production updates trust only this Team ID. It comes from the Developer ID identity by default.
team_id="${TYPINGPET_TEAM_ID:-}"
if [[ -z "$team_id" && "$signing_identity" == "Developer ID Application:"* ]]; then
    team_id="$(sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p' <<<"$signing_identity")"
fi
if [[ "$channel" == production && -z "$team_id" ]]; then
    echo "Warning: no Developer ID Team ID. Updates are checked by the Ed25519 signature only, and macOS asks for Input Monitoring again after each update."
fi

python3 "$project_dir/scripts/generate_plist.py" "$contents_dir/Info.plist" "$app_name" "$executable_name" "$bundle_id" "$display_name" "$channel" \
    "$version" "$build_number" "$team_id" "$update_public_key"

if [[ "$signing_identity" == "Developer ID Application:"* ]]; then
    codesign --force --options runtime --entitlements "$entitlements_file" --timestamp --sign "$signing_identity" "$app_dir"
    echo "Signed for distribution with $signing_identity"
else
    codesign --force --options runtime --entitlements "$entitlements_file" --timestamp=none --sign "$signing_identity" "$app_dir"
    echo "Warning: this build is not signed with Developer ID and cannot be notarized."
fi
echo "$app_dir"

zip_name="TypingPet-macOS.zip"
zip_path="$destination/$zip_name"
if [[ -f "$project_dir/README.txt" ]]; then
    cp "$project_dir/README.txt" "$destination/README.txt"
fi
rm -f "$zip_path"
(
    cd "$destination"
    if [[ -f "README.txt" ]]; then
        zip -r -y -q "$zip_name" "$app_name.app" "README.txt" -x "*.DS_Store*"
    else
        zip -r -y -q "$zip_name" "$app_name.app" -x "*.DS_Store*"
    fi
)
echo "$zip_path"
shasum -a 256 "$zip_path"
