#!/usr/bin/env bash
set -u

status=0

check_command() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    printf 'ok       command %s\n' "$name"
  else
    printf 'missing  command %s\n' "$name"
    status=1
  fi
}

check_path() {
  local path="$1"
  if [[ -e "$path" ]]; then
    printf 'ok       path %s\n' "$path"
  else
    printf 'missing  path %s\n' "$path"
    status=1
  fi
}

check_command pacman
check_command yay
check_command facelock
check_command omarchy
check_path /usr/lib/security/pam_facelock.so
check_path /dev/video2
check_path /dev/tpmrm0

if command -v pacman >/dev/null 2>&1; then
  pacman -Si onnxruntime-cpu 2>/dev/null | awk '/^(Repository|Version|Architecture|Provides)/ {print "info     " $0}'
fi

if command -v facelock >/dev/null 2>&1; then
  facelock capabilities 2>/dev/null | sed 's/^/cap      /'
fi

exit "$status"
