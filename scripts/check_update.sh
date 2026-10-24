#!/bin/zsh
set -euo pipefail

# End-to-end update check with Dev builds and a local server.
# Builds an old and a new Dev app, rejects a bad feed, then installs and relaunches the new app.
project_dir="${0:A:h:h}"
work="${UPDATE_CHECK_DIR:-$project_dir/.build/update-check}"
port="${UPDATE_CHECK_PORT:-8787}"
domain="ing.miel.typingpet.dev.preferences"
feed="http://127.0.0.1:$port/development/latest.json"
old_build=18 new_build=19 new_version=0.13.0
app="$work/install/TypingPet Dev.app"
binary="$app/Contents/MacOS/TypingPetDev"

python3 - <<'PYLOCK'
from pathlib import Path
import fcntl, sys
lock = Path.home() / "Library/Application Support/TypingPetDev/.runtime.lock"
if lock.exists():
    with lock.open("r+") as file:
        try:
            fcntl.flock(file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("Quit TypingPet Dev before running the update check.", file=sys.stderr)
            sys.exit(1)
PYLOCK

key_dir="${TYPINGPET_UPDATE_KEY_DIR:-$HOME/.config/typingpet/update-keys}"
[[ -f "$key_dir/development.pub" ]] || swift "$project_dir/scripts/update_keys.swift" generate development

rm -rf "$work"
export TYPINGPET_BUILD_CHANNEL=development SWIFT_BUILD_CONFIGURATION=debug CODE_SIGN_IDENTITY=-
TYPINGPET_BUILD=$old_build "$project_dir/scripts/build_app.sh" "$work/install" >/dev/null
TYPINGPET_VERSION=$new_version TYPINGPET_BUILD=$new_build "$project_dir/scripts/build_app.sh" "$work/new" >/dev/null
UPDATE_NOTES="Update check build" "$project_dir/scripts/publish_update.sh" development "$work/new/TypingPet Dev.app" \
    "$work/server" "http://127.0.0.1:$port" >/dev/null
manifest="$work/server/development/latest.json"
cp "$manifest" "$work/latest.good.json"

previous_feed="$(defaults read "$domain" UpdateFeedURL 2>/dev/null || true)"
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$work/server" >"$work/server.log" 2>&1 &
server_pid=$!
cleanup() {
    kill "$server_pid" 2>/dev/null || true
    pkill -f "$binary" 2>/dev/null || true
    if [[ -n "$previous_feed" ]]; then defaults write "$domain" UpdateFeedURL "$previous_feed"
    else defaults delete "$domain" UpdateFeedURL 2>/dev/null || true; fi
    for key in LastUpdateCheck NotifiedUpdateBuild; do defaults delete "$domain" "$key" 2>/dev/null || true; done
}
trap cleanup EXIT
defaults write "$domain" UpdateFeedURL "$feed"
for _ in {1..50}; do curl -fs "$feed" >/dev/null && break; sleep 0.1; done

passed=0
pass() { passed=$((passed + 1)); echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; exit 1; }
build_of() { /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$app/Contents/Info.plist" }
rewrite() { python3 -c "import json,sys; m=json.load(open(sys.argv[1])); $2; json.dump(m, open(sys.argv[1], 'w'))" "$manifest" }
expect_rejected() {
    local name="$1" pattern="$2" output code=0
    output="$(perl -e 'alarm 60; exec @ARGV' "$binary" -AppLanguageMode english --install-update-now 2>&1)" || code=$?
    [[ $code -ne 0 && "$output" == *"UPDATE CHECK FAILED"*"$pattern"* ]] || fail "$name: $output"
    [[ "$(build_of)" == "$old_build" ]] || fail "$name changed the installed app"
    pass "$name"
}

rewrite "$manifest" "s = m['signature']; m['signature'] = s[:10] + ('B' if s[10] == 'A' else 'A') + s[11:]"
expect_rejected "Bad signature is rejected" "signature"
cp "$work/latest.good.json" "$manifest"
rewrite "$manifest" "m['sha256'] = '0' * 64"
expect_rejected "Hash mismatch is rejected" "hash"
cp "$work/latest.good.json" "$manifest"
rewrite "$manifest" "m['build'] = $old_build"
expect_rejected "Same build is not offered" "up to date"
cp "$work/latest.good.json" "$manifest"
rewrite "$manifest" "m['url'] = 'http://example.com/update.zip'"
expect_rejected "Remote http archive is refused" "secure"
cp "$work/latest.good.json" "$manifest"

"$binary" -AppLanguageMode english --install-update-now >"$work/old-app.log" 2>&1 &
for _ in {1..300}; do
    [[ "$(build_of)" == "$new_build" ]] && pgrep -f "$binary" >/dev/null && break
    sleep 0.1
done
[[ "$(build_of)" == "$new_build" ]] || fail "New build was not installed. $(cat "$work/old-app.log")"
pass "Update installs over the old app"
pgrep -f "$binary" >/dev/null || fail "Updated app did not relaunch"
pass "Updated app relaunches"
for _ in {1..100}; do
    defaults read "$domain" PendingUpdateBuild >/dev/null 2>&1 || break
    sleep 0.1
done
defaults read "$domain" PendingUpdateBuild >/dev/null 2>&1 && fail "Updated app did not record the finished install"
pass "Updated app confirms the install"
codesign --verify --strict "$app" || fail "Installed app signature is broken"
pass "Installed app signature is valid"
[[ -z "$(find "$work/install" -maxdepth 1 -name '*.app' ! -name 'TypingPet Dev.app')" ]] || fail "Backup app left beside the install"
pass "No backup bundle remains"
echo "$passed update checks passed."
