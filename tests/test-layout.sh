#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root_dir"

required=(
  README.md
  VERSION
  plugin/Service.qml
  plugin/LockView.qml
  plugin/FaceIdBadge.qml
  plugin/SudoScanPill.qml
  plugin/FaceAuthSocket.qml
  plugin/FaceAuthClient.qml
  assets/omarchy-logo-hackerman.png
  sddm/Main.qml
  sddm/metadata.desktop
  root/src/omaid-notify.c
  root/src/omaid-face-bridge.c
  root/omaid-face-bridge.service
  root/omaid-face-bridge.socket
  root/omaid-face-bridge.conf
  root/pam/omaid-lock-face.pam
  root/pam/omaid-sddm-auth.pam
  root/pam/omaid-sddm-password.pam
  scripts/install-user-plugin.sh
  scripts/install-root.sh
  scripts/install-sddm.sh
  scripts/install-sudo-notifier.sh
  scripts/pam-sudo-notifier.py
  scripts/uninstall.sh
)

for path in "${required[@]}"; do
  [[ -f "$path" ]] || { printf 'missing %s\n' "$path" >&2; exit 1; }
done

printf 'ok       layout\n'
