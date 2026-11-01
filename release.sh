#!/usr/bin/env bash
# Canonical release entrypoint. Keep release implementation in scripts/.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec "$ROOT/scripts/release-sign.sh" "$@"
