#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
apply=0
remove_plugin=0
remove_root=0
remove_sddm=0
dry_run=0

while (($# > 0)); do
  case "$1" in
    --apply) apply=1; shift ;;
    --plugin) remove_plugin=1; shift ;;
    --root) remove_root=1; shift ;;
    --sddm) remove_sddm=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help)
      printf 'Usage: %s [--dry-run|--apply] [--plugin] [--root] [--sddm]\n' "$0"
      exit 0
      ;;
    *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if ((dry_run)); then
  apply=0
fi

if ((apply == 0)); then
  if ((remove_plugin)); then printf '%s\n' 'dry-run: would remove the OmaID lock clone and re-enable omarchy.lock'; fi
  if ((remove_root)); then printf '%s\n' 'dry-run: would remove OmaID PAM rules, face bridge, and root helpers'; fi
  if ((remove_sddm)); then printf '%s\n' 'dry-run: would remove the OmaID SDDM theme and configuration'; fi
  exit 0
fi

if ((remove_plugin)); then
  command -v omarchy >/dev/null 2>&1 || { printf '%s\n' 'omarchy is not installed' >&2; exit 1; }
  omarchy plugin remove "${USER:-$(id -un)}.lock" --yes || true
  omarchy plugin enable omarchy.lock
fi

if ((remove_root)); then
  ((EUID == 0)) || { printf '%s\n' 'run with sudo' >&2; exit 1; }
  if [[ -x "$root_dir/scripts/install-sudo-notifier.sh" ]]; then
    "$root_dir/scripts/install-sudo-notifier.sh" --remove
  fi
  if command -v facelock >/dev/null 2>&1; then
    facelock pam remove --service omarchy-lock-face --if-present --no-confirm || true
    facelock pam remove --service sudo --if-present --no-confirm || true
    facelock pam remove --service polkit-1 --if-present --no-confirm || true
  fi
  systemctl disable --now omaid-face-bridge.socket 2>/dev/null || true
  rm -f /etc/systemd/system/omaid-face-bridge.service /etc/systemd/system/omaid-face-bridge.socket /etc/tmpfiles.d/omaid-face-bridge.conf
  systemctl daemon-reload 2>/dev/null || true
  rm -f /usr/libexec/omaid/omaid-face-bridge /usr/libexec/omaid/omaid-notify
  rm -f /run/omaid/face-auth.sock
  rmdir /usr/libexec/omaid /run/omaid 2>/dev/null || true
  rm -f /etc/pam.d/omaid-lock-face
fi

if ((remove_sddm)); then
  ((EUID == 0)) || { printf '%s\n' 'run with sudo' >&2; exit 1; }
  rm -rf /usr/local/share/sddm/themes/omaid
  rm -f /etc/sddm.conf.d/99-zz-omaid.conf
fi
