#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
destination="${1:-$project_dir/dist-dev}"
python3 - <<'PYLOCK'
from pathlib import Path
import fcntl, sys
lock = Path.home() / "Library/Application Support/TypingPetDev/.runtime.lock"
if lock.exists():
    with lock.open("r+") as file:
        try:
            fcntl.flock(file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("TypingPet Dev is running. Quit Dev before rebuilding. The production app can stay running.", file=sys.stderr)
            sys.exit(1)
PYLOCK
export TYPINGPET_BUILD_CHANNEL=development
export SWIFT_BUILD_CONFIGURATION=debug
export CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
"$project_dir/scripts/build_app.sh" "$destination"
open "$destination/TypingPet Dev.app" --args --show-todos
