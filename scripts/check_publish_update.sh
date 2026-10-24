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
    assert json.load(file)["build"] == 19
PYCHECK

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
