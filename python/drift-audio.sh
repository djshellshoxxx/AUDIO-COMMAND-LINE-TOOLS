#!/usr/bin/env bash
# Launcher, not a native Bash audio engine. Requires Python and NumPy.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$script_dir/drift_audio.py" "$@"
