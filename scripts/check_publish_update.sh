#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/typingpet-publish-check.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
export TYPINGPET_UPDATE_KEY_DIR="$test_root/keys"
swift "$project_dir/scripts/update_keys.swift" generate development >/dev/null

app="$test_root/TypingPet Dev.app"
mkdir -p "$app/Contents/MacOS" "$test_root/server"
print -n 'test executable' >"$app/Contents/MacOS/TypingPetDev"
python3 - "$app/Contents/Info.plist" "$(<"$TYPINGPET_UPDATE_KEY_DIR/development.pub")" <<'PYPLIST'
import plistlib
import sys

with open(sys.argv[1], "wb") as file:
    plistlib.dump({
        "CFBundleExecutable": "TypingPetDev",
        "CFBundleVersion": "19",
        "CFBundleShortVersionString": "0.13.0",
        "LSMinimumSystemVersion": "13.0",
        "TypingPetBuildChannel": "development",
        "TypingPetUpdatePublicKey": sys.argv[2],
    }, file)
PYPLIST

"$project_dir/scripts/deploy_update.sh" development "$app" "$test_root/server"
cp "$test_root/server/development/latest.json" "$test_root/first-manifest.json"
# Prepared releases must preserve their exact bytes across retries.
mkdir "$test_root/prepared"
cp -R "$test_root/server/development" "$test_root/prepared/"
"$project_dir/scripts/deploy_update.sh" development "$app" "$test_root/server" "$test_root/prepared"
cmp -s "$test_root/first-manifest.json" "$test_root/server/development/latest.json" || {
    echo "Prepared retry changed the published manifest" >&2
    exit 1
}
print -n 'tampered' >>"$test_root/prepared/development/TypingPetDev-0.13.0-19-arm64.zip"
if "$project_dir/scripts/deploy_update.sh" development "$app" "$test_root/server" "$test_root/prepared" >/dev/null 2>&1; then
    echo "Tampered prepared archive unexpectedly deployed" >&2
    exit 1
fi
retry_output="$("$project_dir/scripts/deploy_update.sh" development "$app" "$test_root/server" 2>&1)" || {
    [[ "$retry_output" == *"Refusing to replace an existing build with different bytes"* ]] || {
        echo "Unexpected retry failure: $retry_output" >&2
        exit 1
    }
}
cmp -s "$test_root/first-manifest.json" "$test_root/server/development/latest.json" || {
    echo "Retry changed the published manifest" >&2
    exit 1
}

signature="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["signature"])' "$test_root/server/development/latest.json")"
swift "$project_dir/scripts/update_keys.swift" verify development \
    "$test_root/server/development/TypingPetDev-0.13.0-19-arm64.zip" "$signature" >/dev/null

/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 18' "$app/Contents/Info.plist"
if "$project_dir/scripts/deploy_update.sh" development "$app" "$test_root/server" >/dev/null 2>&1; then
    echo "Downgrade unexpectedly succeeded" >&2
    exit 1
fi

python3 - "$test_root/server/development/latest.json" <<'PYCHECK'
import json
import sys

with open(sys.argv[1]) as file:
    manifest = json.load(file)
assert manifest["build"] == 19
assert "localizedNotes" not in manifest  # Legacy development fixtures remain compatible.
PYCHECK

# The publisher includes the matching website translations without replacing legacy notes.
localized_version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[0]["version"])' "$project_dir/website/src/releases.json")"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $localized_version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 20' "$app/Contents/Info.plist"
UPDATE_NOTES='Legacy release notes' "$project_dir/scripts/publish_update.sh" development "$app" "$test_root/localized" >/dev/null
python3 - "$test_root/localized/development/latest.json" "$project_dir/website/src/releases.json" <<'PYLOCALIZED'
import json, sys
with open(sys.argv[1]) as file:
    manifest = json.load(file)
with open(sys.argv[2]) as file:
    note = next(note for note in json.load(file) if note['version'] == manifest['version'])
assert manifest['notes'] == 'Legacy release notes'
assert set(manifest['localizedNotes']) == {'ko', 'en', 'ja', 'zh-Hans', 'zh-Hant'}
for language, text in manifest['localizedNotes'].items():
    assert text.startswith(note[language]['title'])
    assert '• ' + note[language]['items'][0] in text
PYLOCALIZED

swift "$project_dir/scripts/update_keys.swift" generate production >/dev/null
cp "$TYPINGPET_UPDATE_KEY_DIR/production.key" "$TYPINGPET_UPDATE_KEY_DIR/development.key"
if swift "$project_dir/scripts/update_keys.swift" check development >/dev/null 2>&1; then
    echo "Mismatched update key unexpectedly passed" >&2
    exit 1
fi
rm "$TYPINGPET_UPDATE_KEY_DIR/development.key"
if swift "$project_dir/scripts/update_keys.swift" generate development >/dev/null 2>&1; then
    echo "Existing public key was unexpectedly replaced" >&2
    exit 1
fi
echo "Update publication checks passed"
