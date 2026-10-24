#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir/website"
npm ci --ignore-scripts --no-audit --no-fund
npm run sync-release
npm run build
npm run test:downloads
python3 scripts/deploy.py
python3 scripts/verify.py
