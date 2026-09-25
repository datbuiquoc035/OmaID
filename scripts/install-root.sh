#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
apply=0
services=0
include_sudo=0
include_polkit=0
bridge=0
bridge_user=""
dry_run=0

while (($# > 0)); do
  case "$1" in
    --apply) apply=1; shift ;;
    --services) services=1; shift ;;
    --sudo) include_sudo=1; shift ;;
    --polkit) include_polkit=1; shift ;;
    --bridge) bridge=1; shift ;;
    --bridge-user) bridge_user=${2:-}; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help)
      printf 'Usage: %s [--dry-run|--apply] [--services] [--sudo] [--polkit] [--bridge] [--bridge-user USER]\n' "$0"
      exit 0
      ;;
    *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if ((dry_run)); then
  apply=0
fi

if ((services == 1 && apply == 0 && dry_run == 0)); then
  printf '%s\n' '--services requires --apply' >&2
  exit 2
fi

helper_source="$root_dir/root/src/omaid-notify.c"
helper_target=/usr/libexec/omaid/omaid-notify
bridge_target=/usr/libexec/omaid/omaid-face-bridge
bridge_service=/etc/systemd/system/omaid-face-bridge.service
bridge_socket=/etc/systemd/system/omaid-face-bridge.socket
bridge_tmpfiles=/etc/tmpfiles.d/omaid-face-bridge.conf
lock_service=/etc/pam.d/omaid-lock-face

if ((apply == 0)); then
  printf 'dry-run: would compile %s\n' "$helper_source"
  printf 'dry-run: would install %s root:root 0755\n' "$helper_target"
  printf 'dry-run: would install %s if absent\n' "$lock_service"
  if ((bridge)); then
    printf 'dry-run: would compile %s\n' "$root_dir/root/src/omaid-face-bridge.c"
     printf 'dry-run: would install %s root:root 0755\n' "$bridge_target"
     printf 'dry-run: would install %s and create /run/omaid\n' "$bridge_tmpfiles"
     printf 'dry-run: would install and enable omaid-face-bridge.socket for %s\n' "${bridge_user:-SUDO_USER}"
  fi
  if ((services)); then
    printf 'dry-run: would run facelock pam add --service omarchy-lock-face --no-confirm\n'
    if ((include_sudo)); then printf 'dry-run: would run facelock pam add --service sudo --no-confirm\n'; fi
    if ((include_polkit)); then printf 'dry-run: would run facelock pam add --service polkit-1 --no-confirm\n'; fi
  fi
  exit 0
fi

((EUID == 0)) || { printf '%s\n' 'run with sudo' >&2; exit 1; }
command -v cc >/dev/null 2>&1 || { printf '%s\n' 'cc is required' >&2; exit 1; }

if ((bridge)); then
  if [[ -z "$bridge_user" ]]; then bridge_user=${SUDO_USER:-}; fi
  [[ "$bridge_user" =~ ^[a-zA-Z0-9_.-]+$ ]] || { printf '%s\n' 'a valid --bridge-user or SUDO_USER is required' >&2; exit 1; }
  id -u "$bridge_user" >/dev/null 2>&1 || { printf 'unknown bridge user: %s\n' "$bridge_user" >&2; exit 1; }
fi

build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
cc -std=c11 -Wall -Wextra -Werror -O2 -o "$build_dir/omaid-notify" "$helper_source"
install -d -m 0755 -o root -g root "$(dirname "$helper_target")"
install -m 0755 -o root -g root "$build_dir/omaid-notify" "$helper_target"

if ((bridge)); then
  cc -std=c11 -Wall -Wextra -Werror -O2 -o "$build_dir/omaid-face-bridge" "$root_dir/root/src/omaid-face-bridge.c"
  install -m 0755 -o root -g root "$build_dir/omaid-face-bridge" "$bridge_target"
  install -m 0644 -o root -g root "$root_dir/root/omaid-face-bridge.service" "$bridge_service"
  install -m 0644 -o root -g root "$root_dir/root/omaid-face-bridge.socket" "$bridge_socket"
  install -m 0644 -o root -g root "$root_dir/root/omaid-face-bridge.conf" "$bridge_tmpfiles"
  sed -i "s/@USER@/$bridge_user/g" "$bridge_service" "$bridge_socket"
  systemd-tmpfiles --create "$bridge_tmpfiles"
  systemctl daemon-reload
  systemctl enable --now omaid-face-bridge.socket
fi

if [[ ! -e "$lock_service" ]]; then
  install -m 0644 -o root -g root "$root_dir/root/pam/omaid-lock-face.pam" "$lock_service"
else
  printf 'keeping existing %s\n' "$lock_service"
fi

if ((services)); then
  command -v facelock >/dev/null 2>&1 || { printf '%s\n' 'facelock is required for --services' >&2; exit 1; }
  facelock pam add --service omarchy-lock-face --no-confirm
  if ((include_sudo)); then facelock pam add --service sudo --no-confirm; fi
  if ((include_polkit)); then facelock pam add --service polkit-1 --no-confirm; fi
fi

printf 'installed root helper at %s\n' "$helper_target"
if ((bridge)); then printf 'installed face bridge socket for %s\n' "$bridge_user"; fi
