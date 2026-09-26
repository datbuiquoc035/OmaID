#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
script_dir="$root_dir/scripts"

apply=0
dry_run=0
restart=0
run_checks=1
run_deps=1
bridge=1
sddm_pam=0
bridge_user=""
pam_services=""
requested=()

usage() {
  cat <<'USAGE'
Usage: ./install.sh [--dry-run|--apply] [options] [surface...]

Sequences the per-surface installers in the right order and escalates only the
steps that write outside the user home. It is a front end: the individual
scripts remain the source of truth and can still be run directly.

Surfaces (default: plugin root):
  plugin     session-lock overlay plus the OmaID manifest
  root       root notifier, face bridge socket, and the lock PAM service
  notifier   sudo scan pill events in /etc/pam.d/sudo
  sddm       SDDM greeter theme
  all        every surface above

Options:
  --apply              change the system; without it this is a dry run
  --dry-run            print the plan only (default)
  --restart            reload the Omarchy shell after the plugin step
  --bridge-user USER   user the face bridge socket accepts (default: you)
  --no-bridge          install the root helper without the face bridge socket
  --pam LIST           register facelock pam services, comma separated
                       (omarchy-lock-face, sudo, polkit-1)
  --sddm-pam           also install the SDDM PAM templates and face rule
  --no-checks          skip scripts/validate.sh
  --no-deps            skip scripts/check-deps.sh
  -h, --help           this text

The face bridge and the root PAM service are on by default because the lock
face path needs them. --disable-autologin is not exposed here: it is a
reviewed, manual step and install-sddm.sh deliberately makes no change for it.

Run this as your normal user. Under sudo the plugin step would install as
root.lock instead of <you>.lock, so it refuses to start as root.
USAGE
  exit 0
}

while (($# > 0)); do
  case "$1" in
    --apply) apply=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    --restart) restart=1; shift ;;
    --bridge-user) bridge_user=${2:-}; shift 2 ;;
    --no-bridge) bridge=0; shift ;;
    --pam) pam_services=${2:-}; shift 2 ;;
    --sddm-pam) sddm_pam=1; shift ;;
    --no-checks) run_checks=0; shift ;;
    --no-deps) run_deps=0; shift ;;
    -h|--help) usage ;;
    plugin|root|notifier|sddm|all) requested+=("$1"); shift ;;
    -*) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
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

run_user=$(id -un)

if [[ -n $USER && $USER != "$run_user" ]]; then
  printf 'warning: USER=%s but the effective user is %s; the plugin step follows $USER\n' "$USER" "$run_user" >&2
fi

if ((${#requested[@]} == 0)); then
  requested=(plugin root)
fi

declare -A seen=()
surfaces=()
for entry in "${requested[@]}"; do
  if [[ $entry == all ]]; then
    entry=(plugin root notifier sddm)
  fi
  for surface in "${entry[@]}"; do
    if [[ -z ${seen[$surface]:-} ]]; then
      seen[$surface]=1
      surfaces+=("$surface")
    fi
  done
done

if [[ -z $bridge_user ]]; then
  bridge_user=$run_user
fi
if ! [[ $bridge_user =~ ^[a-zA-Z0-9_.-]+$ ]]; then
  printf 'invalid --bridge-user: %s\n' "$bridge_user" >&2
  exit 1
fi

root_args=()
if ((bridge)); then
  root_args+=(--bridge --bridge-user "$bridge_user")
fi

if [[ -n $pam_services ]]; then
  root_args+=(--services)
  IFS=',' read -r -a pam_list <<<"$pam_services"
  for service in "${pam_list[@]}"; do
    case "$service" in
      omarchy-lock-face) ;;
      sudo) root_args+=(--sudo) ;;
      polkit|polkit-1) root_args+=(--polkit) ;;
      '') ;;
      *) printf 'unknown --pam service: %s\n' "$service" >&2; exit 2 ;;
    esac
  done
fi

needs_root=0
for surface in "${surfaces[@]}"; do
  case "$surface" in
    root|notifier|sddm) needs_root=1 ;;
  esac
done

if ((apply && needs_root)); then
  command -v sudo >/dev/null 2>&1 || { printf '%s\n' 'sudo is required for the root steps' >&2; exit 1; }
fi

if ((apply)); then
  mode=apply
  mode_args=(--apply)
else
  mode=dry-run
  mode_args=(--dry-run)
  if ((needs_root)); then
    command -v sudo >/dev/null 2>&1 || printf 'warning: sudo is unavailable; root plans will still print\n' >&2
  fi
fi

printf 'OmaID installer: %s as %s\n' "$mode" "$run_user"
printf 'surfaces: %s\n' "${surfaces[*]}"
if ((${#root_args[@]} > 0)); then
  printf 'root options: %s\n' "${root_args[*]}"
fi

if [[ ! -f $root_dir/assets/face-id/face.svg ]]; then
  printf 'warning: assets/face-id/face.svg is missing; the lock and greeter will use their fallback artwork\n' >&2
fi

if ((run_deps && apply)); then
  printf '\n== dependencies\n'
  "$script_dir/check-deps.sh" || printf 'warning: dependency check reported problems; review them before continuing\n' >&2
fi

if ((run_checks)); then
  printf '\n== checks\n'
  if "$script_dir/validate.sh"; then
    :
  elif ((apply)); then
    printf '%s\n' 'checks failed; refusing to modify the system' >&2
    exit 1
  else
    printf 'warning: checks failed; continuing because this is a dry run\n' >&2
  fi
fi

if ((apply && needs_root)); then
  printf '\n== requesting sudo once for the root steps\n'
  sudo -v
fi

status=0
for surface in "${surfaces[@]}"; do
  case "$surface" in
    plugin)
      printf '\n== plugin\n'
      args=()
      if ((apply)); then args+=(--apply); fi
      if ((restart)); then args+=(--restart); fi
      "$script_dir/install-user-plugin.sh" "${args[@]}"
      ;;
    root)
      printf '\n== root\n'
      if ((apply)); then
        sudo "$script_dir/install-root.sh" "${mode_args[@]}" "${root_args[@]}"
      else
        "$script_dir/install-root.sh" "${mode_args[@]}" "${root_args[@]}"
      fi
      ;;
    notifier)
      printf '\n== notifier\n'
      if ((apply)); then
        sudo "$script_dir/install-sudo-notifier.sh" --apply
      else
        "$script_dir/install-sudo-notifier.sh" --dry-run
      fi
      ;;
    sddm)
      printf '\n== sddm\n'
      sddm_args=()
      if ((sddm_pam)); then sddm_args+=(--apply-pam); fi
      if ((apply)); then
        sudo "$script_dir/install-sddm.sh" --apply "${sddm_args[@]}"
      else
        if ((${#sddm_args[@]} > 0)); then
          "$script_dir/install-sddm.sh" --dry-run "${sddm_args[@]}"
        else
          "$script_dir/install-sddm.sh" --dry-run
        fi
      fi
      ;;
  esac
done

printf '\nOmaID %s complete: %s\n' "$mode" "${surfaces[*]}"
if ((apply)); then
  printf '%s\n' 'verify with: sudo -k && sudo -v, then omarchy-shell lock lock'
fi

exit "$status"
