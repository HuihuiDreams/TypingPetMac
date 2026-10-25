#!/bin/zsh
set -euo pipefail

# Writes a signed archive and latest.json. Upload the channel folder to the update server.
#   ./scripts/publish_update.sh <development|production> <app> [output] [base-url]
project_dir="${0:A:h:h}"
channel="${1:?Usage: publish_update.sh <channel> <app> [output] [base-url]}"
app_path="${2:?Usage: publish_update.sh <channel> <app> [output] [base-url]}"
case "$channel" in
    development)
        output="${3:-$project_dir/dist-dev/update-server}"
        base_url="${4:-http://localhost:8787}"
        ;;
    production)
        output="${3:-$project_dir/dist/update-server}"
        base_url="${4:-https://pet.miel.ing/update}"
        ;;
    *) echo "Unknown channel: $channel" >&2; exit 1 ;;
esac

info="$app_path/Contents/Info.plist"
plist_value() { /usr/libexec/PlistBuddy -c "Print :$1" "$info" }
[[ "$(plist_value TypingPetBuildChannel)" == "$channel" ]] || { echo "$app_path is not a $channel build." >&2; exit 1; }
version="$(plist_value CFBundleShortVersionString)"
build="$(plist_value CFBundleVersion)"
minimum="$(plist_value LSMinimumSystemVersion)"
executable="$(plist_value CFBundleExecutable)"
update_key_dir="${TYPINGPET_UPDATE_KEY_DIR:-$HOME/.config/typingpet/update-keys}"
public_key_file="$update_key_dir/$channel.pub"
[[ -f "$public_key_file" ]] || { echo "Missing $public_key_file" >&2; exit 1; }
[[ "$(plist_value TypingPetUpdatePublicKey)" == "$(<"$public_key_file")" ]] || {
    echo "The app's update public key does not match $public_key_file." >&2
    exit 1
}
swift "$project_dir/scripts/update_keys.swift" check "$channel" >/dev/null

if [[ "$channel" == production ]] && /usr/libexec/PlistBuddy -c "Print :TypingPetTeamIdentifier" "$info" >/dev/null 2>&1; then
    spctl --assess --type execute "$app_path" || { echo "Notarize the app first: ./scripts/notarize_release.sh" >&2; exit 1; }
fi

mkdir -p "$output/$channel"
archive_name="$executable-$version-$build-arm64.zip"
staging="$(mktemp -d "$output/$channel/.publish.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
archive="$staging/$archive_name"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive"
size="$(stat -f %z "$archive")"
sha256="$(shasum -a 256 "$archive" | cut -d ' ' -f 1)"
signature="$(swift "$project_dir/scripts/update_keys.swift" sign "$channel" "$archive")"
notes="${UPDATE_NOTES:-$(awk -v v="## $version " 'index($0, v) == 1 { found = 1; next } /^## / && found { exit } found && NF' "$project_dir/CHANGELOG.md")}"

python3 - "$staging/latest.json" "$version" "$build" "$minimum" "$base_url/$channel/$archive_name" "$size" "$sha256" "$signature" "$notes" "$project_dir" "$channel" <<'PYJSON'
import json, sys
from pathlib import Path
path, version, build, minimum, url, size, sha256, signature, notes, project, channel = sys.argv[1:]
sys.path.insert(0, str(Path(project) / "scripts"))
from release_notes import localized_release_notes
manifest = {
    "version": version,
    "build": int(build),
    "minimumSystemVersion": minimum,
    "url": url,
    "size": int(size),
    "sha256": sha256,
    "signature": signature,
}
if notes.strip():
    manifest["notes"] = notes.strip()
translations = localized_release_notes(Path(project), version, required=channel == "production")
if translations:
    manifest["localizedNotes"] = translations
with open(path, "w") as file:
    json.dump(manifest, file, ensure_ascii=False, indent=2)
    file.write("\n")
PYJSON
mv -f "$archive" "$output/$channel/$archive_name"
mv -f "$staging/latest.json" "$output/$channel/latest.json"
echo "$output/$channel/latest.json"
