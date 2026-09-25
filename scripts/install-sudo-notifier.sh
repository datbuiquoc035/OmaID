#!/usr/bin/env bash
set -euo pipefail

apply=0
remove=0
dry_run=0

while (($# > 0)); do
  case "$1" in
    --apply) apply=1; shift ;;
    --remove) remove=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help)
      printf 'Usage: %s [--dry-run|--apply|--remove]\n' "$0"
      exit 0
      ;;
    *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if ((dry_run)); then
  if ((remove)); then
    printf '%s\n' 'dry-run: would remove OmaID notifier lines from /etc/pam.d/sudo'
  else
    printf '%s\n' 'dry-run: would verify pam_facelock.so in /etc/pam.d/sudo'
    printf '%s\n' 'dry-run: would back up /etc/pam.d/sudo under /var/lib/omaid/backups'
    printf '%s\n' 'dry-run: would add begin/fallback auth events and an account end event'
  fi
  exit 0
fi

if ((apply == 1 && remove == 1)); then
  printf '%s\n' '--apply and --remove are mutually exclusive' >&2
  exit 2
fi

if ((apply == 0 && remove == 0)); then
  if ((remove)); then
    printf '%s\n' 'dry-run: would remove OmaID notifier lines from /etc/pam.d/sudo'
  else
    printf '%s\n' 'dry-run: would verify pam_facelock.so in /etc/pam.d/sudo'
    printf '%s\n' 'dry-run: would back up /etc/pam.d/sudo under /var/lib/omaid/backups'
    printf '%s\n' 'dry-run: would add begin/fallback auth events and an account end event'
  fi
  exit 0
fi

((EUID == 0)) || { printf '%s\n' 'run with sudo' >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { printf '%s\n' 'python3 is required' >&2; exit 1; }
[[ -f /etc/pam.d/sudo ]] || { printf '%s\n' 'missing /etc/pam.d/sudo' >&2; exit 1; }

if ((remove == 0)); then
  grep -Fq 'pam_facelock.so' /etc/pam.d/sudo || {
    printf '%s\n' 'pam_facelock.so is not present; add it with facelock first' >&2
    exit 1
  }
fi

args=(
  --file /etc/pam.d/sudo
  --backup-dir /var/lib/omaid/backups
)

if ((remove)); then
  args+=(--remove)
fi

python3 "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/pam-sudo-notifier.py" "${args[@]}"
