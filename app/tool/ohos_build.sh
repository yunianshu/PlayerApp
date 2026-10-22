#!/usr/bin/env bash
# Compatibility entry point; all work takes place in build/ohos-workspace.
set -euo pipefail
cd "$(dirname "$0")/.."
exec "${PYTHON:-python}" tool/ohos_build.py "$@"
