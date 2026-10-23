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

if [[ "$channel" == production ]] && /usr/libexec/PlistBuddy -c "Print :TypingPetTeamIdentifier" "$info" >/dev/null 2>&1; then
    spctl --assess --type execute "$app_path" || { echo "Notarize the app first: ./scripts/notarize_release.sh" >&2; exit 1; }
fi

mkdir -p "$output/$channel"
archive_name="$executable-$version-$build-arm64.zip"
archive="$output/$channel/$archive_name"
rm -f "$archive"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive"
size="$(stat -f %z "$archive")"
sha256="$(shasum -a 256 "$archive" | cut -d ' ' -f 1)"
signature="$(swift "$project_dir/scripts/update_keys.swift" sign "$channel" "$archive")"
notes="${UPDATE_NOTES:-$(awk -v v="## $version " 'index($0, v) == 1 { found = 1; next } /^## / && found { exit } found && NF' "$project_dir/CHANGELOG.md")}"

python3 - "$output/$channel/latest.json" "$version" "$build" "$minimum" "$base_url/$channel/$archive_name" "$size" "$sha256" "$signature" "$notes" <<'PYJSON'
import json, sys
path, version, build, minimum, url, size, sha256, signature, notes = sys.argv[1:]
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
with open(path, "w") as file:
    json.dump(manifest, file, ensure_ascii=False, indent=2)
    file.write("\n")
PYJSON
echo "$output/$channel/latest.json"
