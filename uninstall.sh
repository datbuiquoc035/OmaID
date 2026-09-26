#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

apply=0
remove_plugin=0
remove_root=0
remove_notifier=0
remove_sddm=0
dry_run=0
requested=()

usage() {
  cat <<'USAGE'
Usage: ./uninstall.sh [--dry-run|--apply] [options] [surface...]

Surfaces:
  plugin     remove the <user>.lock clone and re-enable omarchy.lock
  root       remove the OmaID pam rules, the face bridge, and the root helpers
  notifier   remove only the OmaID notifier events from /etc/pam.d/sudo
  sddm       remove the OmaID SDDM theme and drop-in
  all        plugin, root, notifier, and sddm (default)

Options:
  --apply    actually remove; without it this is a dry run
  --dry-run  print the plan only (default)
  -h, --help this text

Run this as your normal user; the root surfaces are escalated with sudo
individually. Running it under sudo would target root.lock instead of
<you>.lock, so it refuses to start as root.

--root already includes the notifier removal, matching install.sh --apply.
USAGE
  exit 0
}

while (($# > 0)); do
  case "$1" in
    --apply) apply=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    --plugin) remove_plugin=1; shift ;;
    --root) remove_root=1; shift ;;
    --notifier) remove_notifier=1; shift ;;
    --sddm) remove_sddm=1; shift ;;
    --all) remove_plugin=1; remove_root=1; remove_notifier=1; remove_sddm=1; shift ;;
    -h|--help) usage ;;
    -*) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
    plugin|root|notifier|sddm|all)
      requested+=("$1")
      shift
      ;;
    *) printf 'unknown surface: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if ((dry_run)); then
  apply=0
fi

if ((EUID == 0)); then
  printf '%s\n' 'run this as your normal user; it escalates only the steps that need root' >&2
  exit 1
fi

if ((${#requested[@]} > 0)); then
  remove_plugin=0
  remove_root=0
  remove_notifier=0
  remove_sddm=0
  for surface in "${requested[@]}"; do
    case "$surface" in
      all)
        remove_plugin=1
        remove_root=1
        remove_notifier=1
        remove_sddm=1
        ;;
      plugin) remove_plugin=1 ;;
      root) remove_root=1 ;;
      notifier) remove_notifier=1 ;;
      sddm) remove_sddm=1 ;;
    esac
  done
fi

if ((remove_plugin == 0 && remove_root == 0 && remove_notifier == 0 && remove_sddm == 0)); then
  remove_plugin=1
  remove_root=1
  remove_notifier=1
  remove_sddm=1
fi

if ((remove_root)); then
  remove_notifier=1
fi

surfaces=()
((remove_plugin)) && surfaces+=(plugin)
((remove_root)) && surfaces+=(root)
((remove_notifier)) && surfaces+=(notifier)
((remove_sddm)) && surfaces+=(sddm)

if ((apply == 0)); then
  for surface in "${surfaces[@]}"; do
    case "$surface" in
      plugin) printf '%s\n' 'dry-run: would remove the OmaID lock clone and re-enable omarchy.lock' ;;
      root) printf '%s\n' 'dry-run: would remove OmaID PAM rules, face bridge, and root helpers' ;;
      notifier) printf '%s\n' 'dry-run: would remove OmaID notifier lines from /etc/pam.d/sudo' ;;
      sddm) printf '%s\n' 'dry-run: would remove the OmaID SDDM theme and configuration' ;;
    esac
  done
  printf 'OmaID uninstall dry-run complete: %s\n' "${surfaces[*]}"
  exit 0
fi

as_root() {
  sudo "$@"
}

if ((remove_plugin)); then
  command -v omarchy >/dev/null 2>&1 || { printf '%s\n' 'omarchy is not installed' >&2; exit 1; }
  printf '\n== plugin\n'
  omarchy plugin remove "${USER:-$(id -un)}.lock" --yes || true
  omarchy plugin enable omarchy.lock
fi

if ((remove_notifier)); then
  printf '\n== notifier\n'
  as_root "$root_dir/scripts/install-sudo-notifier.sh" --remove
fi

if ((remove_root)); then
  command -v sudo >/dev/null 2>&1 || { printf '%s\n' 'sudo is required for the root steps' >&2; exit 1; }
  printf '\n== root\n'
  if command -v facelock >/dev/null 2>&1; then
    as_root facelock pam remove --service omarchy-lock-face --if-present --no-confirm || true
    as_root facelock pam remove --service sudo --if-present --no-confirm || true
    as_root facelock pam remove --service polkit-1 --if-present --no-confirm || true
  fi
  as_root systemctl disable --now omaid-face-bridge.socket 2>/dev/null || true
  as_root rm -f /etc/systemd/system/omaid-face-bridge.service /etc/systemd/system/omaid-face-bridge.socket /etc/tmpfiles.d/omaid-face-bridge.conf
  as_root systemctl daemon-reload 2>/dev/null || true
  as_root rm -f /usr/libexec/omaid/omaid-face-bridge /usr/libexec/omaid/omaid-notify
  as_root rm -f /run/omaid/face-auth.sock
  as_root rmdir /usr/libexec/omaid /run/omaid 2>/dev/null || true
  as_root rm -f /etc/pam.d/omaid-lock-face
fi

if ((remove_sddm)); then
  command -v sudo >/dev/null 2>&1 || { printf '%s\n' 'sudo is required for the root steps' >&2; exit 1; }
  printf '\n== sddm\n'
  as_root rm -rf /usr/local/share/sddm/themes/omaid
  as_root rm -f /etc/sddm.conf.d/99-zz-omaid.conf
fi

printf '\nOmaID uninstall complete: %s\n' "${surfaces[*]}"
printf '%s\n' 'Facelock models, enrollment data, and encryption keys were left untouched'
