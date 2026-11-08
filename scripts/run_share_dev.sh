#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
export TYPINGPET_SHARE_STATE_DIR="${TYPINGPET_SHARE_STATE_DIR:-$HOME/Library/Application Support/TypingPetDev/ShareService}"
export TYPINGPET_SHARE_PORT="${TYPINGPET_SHARE_PORT:-17868}"
uv sync --project "$project_dir/scripts/share-service" --locked
exec "$project_dir/scripts/share-service/.venv/bin/python" "$project_dir/scripts/share_dev_server.py"
