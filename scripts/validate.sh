#!/usr/bin/env bash
set -u

status=0
root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root_dir" || exit 1

check_shell() {
  local file="$1"
  local error_file
  error_file=$(mktemp)

  if bash -n "$file" 2>"$error_file"; then
    printf 'ok       bash %s\n' "$file"
  else
    printf 'invalid  bash %s\n' "$file"
    printf '%s\n' "$(<"$error_file")"
    status=1
  fi

  rm -f "$error_file"
}

for script in install.sh uninstall.sh scripts/*.sh; do
  check_shell "$script"
done

if command -v cc >/dev/null 2>&1; then
  build_dir=$(mktemp -d)
  if cc -std=c11 -Wall -Wextra -Werror -O2 -o "$build_dir/omaid-notify" root/src/omaid-notify.c 2>"$build_dir/cc.err"; then
    printf 'ok       c     root/src/omaid-notify.c\n'
  else
    printf 'invalid  c     root/src/omaid-notify.c\n'
    printf '%s\n' "$(<"$build_dir/cc.err")"
    status=1
  fi
  if cc -std=c11 -Wall -Wextra -Werror -O2 -o "$build_dir/omaid-face-bridge" root/src/omaid-face-bridge.c 2>"$build_dir/bridge-cc.err"; then
    printf 'ok       c     root/src/omaid-face-bridge.c\n'
  else
    printf 'invalid  c     root/src/omaid-face-bridge.c\n'
    printf '%s\n' "$(<"$build_dir/bridge-cc.err")"
    status=1
  fi
  rm -rf "$build_dir"
else
  printf 'skip     c     compiler unavailable\n'
fi

if command -v python3 >/dev/null 2>&1; then
  if python3 -c 'from pathlib import Path; compile(Path("scripts/pam-sudo-notifier.py").read_text(), "scripts/pam-sudo-notifier.py", "exec")'; then
    printf 'ok       python scripts/pam-sudo-notifier.py\n'
  else
    printf 'invalid  python scripts/pam-sudo-notifier.py\n'
    status=1
  fi
else
  printf 'skip     python compiler unavailable\n'
fi

if command -v jq >/dev/null 2>&1; then
  if jq -e '
        .schemaVersion == 1
        and (.id | test("^[A-Za-z0-9][A-Za-z0-9._-]*$"))
        and (.id | contains("..") | not)
        and (.id | startswith("omarchy.") | not)
        and (.name | type == "string" and length > 0)
        and (.version | type == "string" and length > 0)
        and (.kinds | type == "array" and length > 0)
        and (.entryPoints | type == "object")
      ' plugin/manifest.json >/dev/null; then
    printf 'ok       json  plugin/manifest.json\n'
  else
    printf 'invalid  json  plugin/manifest.json\n'
    status=1
  fi
else
  printf 'skip     json  jq unavailable\n'
fi

qml_files=(
  plugin/Service.qml
  plugin/LockView.qml
  plugin/FaceIdBadge.qml
  plugin/SuccessMark.qml
  plugin/SudoScanPill.qml
  plugin/FaceAuthSocket.qml
  plugin/FaceAuthClient.qml
  sddm/Main.qml
  tests/qml/tst_successmark.qml
  tests/qml/tst_faceidbadge.qml
)

# The Qt 6 tools are not on PATH on a stock Arch install, so look in the
# location qt6-base actually installs them to before giving up on the lint.
qmllint_bin=$(command -v qmllint || true)
if [[ -z "$qmllint_bin" ]]; then
  for candidate in /usr/lib/qt6/bin/qmllint /usr/lib/qt6/libexec/qmllint; do
    [[ -x "$candidate" ]] && { qmllint_bin="$candidate"; break; }
  done
fi

if [[ -n "$qmllint_bin" ]]; then
  if "$qmllint_bin" "${qml_files[@]}"; then
    printf 'ok       qml   source files\n'
  else
    printf 'invalid  qml   source files\n'
    status=1
  fi
else
  printf 'skip     qml   qmllint unavailable\n'
fi

exit "$status"
