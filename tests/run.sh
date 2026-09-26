#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
qml_test_dir="$root_dir/tests/qml"
# FaceIdBadge imports qs.Commons, which only resolves inside a running
# Quickshell. The stub on this import path stands in for it.
qml_stub_dir="$qml_test_dir/stubs"

"$root_dir/scripts/validate.sh"
"$root_dir/tests/test-layout.sh"
"$root_dir/tests/test-templates.sh"

# The success mark is a Shape, so it only proves anything against a real render
# backend. Skip cleanly when qmltestrunner is missing rather than failing the
# suite on a machine without the Qt 6 tools.
qmltestrunner=$(command -v qmltestrunner || true)
if [[ -z "$qmltestrunner" ]]; then
  for candidate in /usr/lib/qt6/bin/qmltestrunner /usr/lib/qt6/libexec/qmltestrunner; do
    [[ -x "$candidate" ]] && { qmltestrunner="$candidate"; break; }
  done
fi

if [[ -z "$qmltestrunner" ]]; then
  printf 'skip     qml   qmltestrunner unavailable\n'
  exit 0
fi

if QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
  "$qmltestrunner" -import "$qml_stub_dir" -input "$qml_test_dir" 2>&1 | sed 's/^/         /'; then
  printf 'ok       qml   tests/qml\n'
else
  printf 'invalid  qml   tests/qml\n'
  exit 1
fi
