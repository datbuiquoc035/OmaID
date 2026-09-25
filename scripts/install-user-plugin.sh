#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
config_root="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"
user_name=${USER:-$(id -un)}
target_id="$user_name.lock"
target_dir="$config_root/plugins/$target_id"
apply=0
restart=0
dry_run=0

while (($# > 0)); do
  case "$1" in
    --apply) apply=1; shift ;;
    --restart) restart=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help)
      printf 'Usage: %s [--dry-run|--apply] [--restart]\n' "$0"
      exit 0
      ;;
    *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if ((dry_run)); then
  apply=0
fi

if ((apply == 0)); then
  printf 'dry-run: would ensure %s\n' "$target_dir"
  printf 'dry-run: would overlay Service.qml, LockView.qml, FaceIdBadge.qml, SudoScanPill.qml, FaceAuthSocket.qml, FaceAuthClient.qml\n'
  printf 'dry-run: would copy assets/face-id when present\n'
  if ((restart)); then printf 'dry-run: would run omarchy restart shell\n'; fi
  exit 0
fi

command -v omarchy >/dev/null 2>&1 || { printf 'omarchy is not installed\n' >&2; exit 1; }
mkdir -p "$config_root/plugins"

if [[ ! -d "$target_dir" ]]; then
  printf 'creating clone %s\n' "$target_id"
  omarchy plugin clone omarchy.lock
fi

[[ -f "$target_dir/manifest.json" ]] || { printf 'missing clone manifest: %s\n' "$target_dir/manifest.json" >&2; exit 1; }

for file in Service.qml LockView.qml FaceIdBadge.qml SudoScanPill.qml FaceAuthSocket.qml FaceAuthClient.qml; do
  install -m 0644 "$root_dir/plugin/$file" "$target_dir/$file"
done

if [[ -f "$root_dir/assets/face-id/face.svg" ]]; then
  install -d -m 0755 "$target_dir/assets/face-id"
  install -m 0644 "$root_dir/assets/face-id/face.svg" "$target_dir/assets/face-id/face.svg"
fi

omarchy plugin validate "$target_dir"
printf 'installed overlay at %s\n' "$target_dir"

if ((restart)); then
  omarchy restart shell
fi
