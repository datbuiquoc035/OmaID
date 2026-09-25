#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

"$root_dir/scripts/validate.sh"
"$root_dir/tests/test-layout.sh"
"$root_dir/tests/test-templates.sh"
