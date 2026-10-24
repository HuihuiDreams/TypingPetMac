#!/bin/zsh
set -euo pipefail

# Publish a signed update to the local static server. The manifest is replaced last.
#   ./scripts/deploy_update.sh <development|production> <app> [server-root]
project_dir="${0:A:h:h}"
channel="${1:?Usage: deploy_update.sh <channel> <app> [server-root]}"
app_path="${2:?Usage: deploy_update.sh <channel> <app> [server-root]}"
server_root="${3:-${TYPINGPET_UPDATE_ROOT:-$HOME/TypingPetUpdate}}"
case "$channel" in
    production)
        info="$app_path/Contents/Info.plist"
        team="$(/usr/libexec/PlistBuddy -c 'Print :TypingPetTeamIdentifier' "$info" 2>/dev/null)" || {
            echo "Production updates require a Developer ID Team ID." >&2
            exit 1
        }
        signed_team="$(codesign -dv --verbose=4 "$app_path" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -n 1)"
        [[ -n "$team" && "$team" == "$signed_team" ]] || {
            echo "The app's Team ID does not match its code signature." >&2
            exit 1
        }
        codesign --verify --deep --strict "$app_path"
        spctl --assess --type execute "$app_path"
        base_url="https://pet.miel.ing/update"
        ;;
    development)
        base_url="http://localhost:8787"
        ;;
    *) echo "Unknown channel: $channel" >&2; exit 1 ;;
esac
[[ -d "$server_root" ]] || { echo "Update server root does not exist: $server_root" >&2; exit 1; }

staging="$(mktemp -d "${TMPDIR:-/tmp}/typingpet-deploy.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
"$project_dir/scripts/publish_update.sh" "$channel" "$app_path" "$staging" "$base_url" >/dev/null

python3 - "$staging/$channel" "$server_root/$channel" <<'PYDEPLOY'
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
from urllib.parse import urlparse

source, destination = map(Path, sys.argv[1:])
manifest_bytes = (source / "latest.json").read_bytes()
manifest = json.loads(manifest_bytes)
archive_name = Path(urlparse(manifest["url"]).path).name
if not archive_name.endswith(".zip") or archive_name in {"", ".", ".."}:
    raise SystemExit("Invalid archive name in update manifest")
archive = source / archive_name
if not archive.is_file():
    raise SystemExit("Update archive is missing")
def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

digest = sha256(archive)
if archive.stat().st_size != manifest["size"] or digest != manifest["sha256"]:
    raise SystemExit("Update archive does not match its manifest")

destination.mkdir(parents=True, exist_ok=True)
current_path = destination / "latest.json"
if current_path.exists():
    current = json.loads(current_path.read_text())
    if manifest["build"] < current["build"]:
        raise SystemExit("Refusing to replace a newer update")
    if manifest["build"] == current["build"]:
        if manifest["sha256"] == current["sha256"] and manifest["url"] == current["url"]:
            print(f"Already deployed: build {manifest['build']}")
            raise SystemExit(0)
        raise SystemExit("Refusing to replace an existing build with different bytes")

target_archive = destination / archive_name
if target_archive.exists():
    if sha256(target_archive) != digest:
        raise SystemExit("An archive with this name already has different bytes")

def atomic_copy(data_path: Path, target: Path) -> None:
    with tempfile.NamedTemporaryFile(dir=destination, prefix=".upload-", delete=False) as temp:
        temporary = Path(temp.name)
        try:
            with data_path.open("rb") as source_file:
                shutil.copyfileobj(source_file, temp)
            temp.flush()
            os.fsync(temp.fileno())
        except BaseException:
            temporary.unlink(missing_ok=True)
            raise
    try:
        os.chmod(temporary, 0o644)
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)

if not target_archive.exists():
    atomic_copy(archive, target_archive)
with tempfile.NamedTemporaryFile(dir=destination, prefix=".manifest-", delete=False) as temp:
    temporary_manifest = Path(temp.name)
    temp.write(manifest_bytes)
    temp.flush()
    os.fsync(temp.fileno())
try:
    os.chmod(temporary_manifest, 0o644)
    os.replace(temporary_manifest, current_path)
finally:
    temporary_manifest.unlink(missing_ok=True)
print(f"Deployed build {manifest['build']}: {current_path}")
PYDEPLOY

if [[ "$channel" == production ]]; then
    curl --fail --silent --show-error --retry 2 --retry-delay 1 \
        "$base_url/$channel/latest.json" -o "$staging/public-latest.json"
    python3 - "$server_root/$channel/latest.json" "$staging/public-latest.json" <<'PYVERIFY'
import json
import sys

with open(sys.argv[1]) as file:
    local = json.load(file)
with open(sys.argv[2]) as file:
    remote = json.load(file)
for field in ("build", "sha256", "signature", "url"):
    if local[field] != remote[field]:
        raise SystemExit(f"Public update feed differs at {field}")
print("Public update feed verified")
PYVERIFY
    archive_url="$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["url"])' "$server_root/$channel/latest.json")"
    curl --fail --silent --show-error --retry 2 --retry-delay 1 \
        "$archive_url" -o "$staging/public-update.zip"
    archive_name="${archive_url:t}"
    cmp -s "$staging/public-update.zip" "$server_root/$channel/$archive_name" || {
        echo "Public update archive differs from the deployed archive." >&2
        exit 1
    }
    echo "Public update archive verified"
fi
