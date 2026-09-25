#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
theme_target=/usr/local/share/sddm/themes/omaid
config_target=/etc/sddm.conf.d/99-zz-omaid.conf
apply=0
apply_pam=0
disable_autologin=0
dry_run=0

while (($# > 0)); do
  case "$1" in
    --apply) apply=1; shift ;;
    --apply-pam) apply=1; apply_pam=1; shift ;;
    --disable-autologin) disable_autologin=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help)
      printf 'Usage: %s [--dry-run|--apply] [--apply-pam] [--disable-autologin]\n' "$0"
      exit 0
      ;;
    *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if ((dry_run)); then
  apply=0
fi

if ((apply == 0)); then
  printf 'dry-run: would install theme at %s\n' "$theme_target"
  printf 'dry-run: would install %s\n' "$config_target"
  printf 'dry-run: would install /etc/pam.d/sddm-auth and /etc/pam.d/sddm-password\n'
  if ((apply_pam)); then
    printf 'dry-run: would run facelock pam add --service sddm-auth --no-confirm\n'
    printf 'dry-run: would leave /etc/pam.d/sddm unchanged for manual review\n'
  fi
  if ((disable_autologin)); then printf 'dry-run: would disable SDDM autologin after backup\n'; fi
  exit 0
fi

((EUID == 0)) || { printf '%s\n' 'run with sudo' >&2; exit 1; }

install -d -m 0755 -o root -g root "$theme_target/assets/face-id"
for file in Main.qml metadata.desktop theme.conf; do
  install -m 0644 -o root -g root "$root_dir/sddm/$file" "$theme_target/$file"
done
if [[ -f "$root_dir/assets/face-id/face.svg" ]]; then
  install -m 0644 -o root -g root "$root_dir/assets/face-id/face.svg" "$theme_target/assets/face-id/face.svg"
else
  printf 'warning: assets/face-id/face.svg is not present; the theme will use its fallback glyph\n' >&2
fi

install -d -m 0755 -o root -g root /etc/sddm.conf.d
install -m 0644 -o root -g root "$root_dir/sddm/omaid.conf" "$config_target"

if ((apply_pam)); then
  command -v facelock >/dev/null 2>&1 || { printf '%s\n' 'facelock is required for --apply-pam' >&2; exit 1; }
  install -m 0644 -o root -g root "$root_dir/root/pam/omaid-sddm-auth.pam" /etc/pam.d/sddm-auth
  install -m 0644 -o root -g root "$root_dir/root/pam/omaid-sddm-password.pam" /etc/pam.d/sddm-password
  facelock pam add --service sddm-auth --no-confirm
  printf '%s\n' 'SDDM auth templates installed; update /etc/pam.d/sddm only after reviewing the diff'
else
  printf '%s\n' 'PAM templates were not installed; rerun with --apply-pam after review'
fi

if ((disable_autologin)); then
  printf '%s\n' 'autologin change requires a reviewed backup and controlled VT test'
  printf '%s\n' 'no autologin file was modified by this run'
fi

printf 'installed SDDM theme at %s\n' "$theme_target"
