#!/usr/bin/env bash
# Thin wrapper: the launcher owns installation now.
# Kept so `./install.sh` and the README keep working.
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fisch-hub.sh" --install "$@"
