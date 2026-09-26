#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root_dir"

required=(
  README.md
  VERSION
  install.sh
  uninstall.sh
  plugin/manifest.json
  plugin/Service.qml
  plugin/LockView.qml
  plugin/FaceIdBadge.qml
  plugin/SuccessMark.qml
  plugin/SudoScanPill.qml
  plugin/FaceAuthSocket.qml
  plugin/FaceAuthClient.qml
  assets/omarchy-logo-hackerman.png
  preview.png
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
  tests/qml/tst_successmark.qml
  tests/qml/tst_faceidbadge.qml
  tests/qml/stubs/qs/Commons/qmldir
  tests/qml/stubs/qs/Commons/Color.qml
  tests/qml/stubs/qs/Commons/Style.qml
)

for path in "${required[@]}"; do
  [[ -f "$path" ]] || { printf 'missing %s\n' "$path" >&2; exit 1; }
done

for path in install.sh uninstall.sh scripts/*.sh; do
  [[ -x "$path" ]] || { printf '%s is not executable\n' "$path" >&2; exit 1; }
done

version=$(<VERSION)

jq -e '.schemaVersion == 1' plugin/manifest.json >/dev/null \
  || { printf 'plugin/manifest.json has an unsupported schemaVersion\n' >&2; exit 1; }

jq -e '.name == "OmaID"' plugin/manifest.json >/dev/null \
  || { printf 'plugin/manifest.json name is not OmaID\n' >&2; exit 1; }

jq -e --arg version "$version" '.version == $version' plugin/manifest.json >/dev/null \
  || { printf 'plugin/manifest.json version does not match VERSION (%s)\n' "$version" >&2; exit 1; }

jq -e '.omarchy.clonedFrom == "omarchy.lock"' plugin/manifest.json >/dev/null \
  || { printf 'plugin/manifest.json does not declare omarchy.lock as clonedFrom\n' >&2; exit 1; }

jq -e '.entryPoints.service == "Service.qml"' plugin/manifest.json >/dev/null \
  || { printf 'plugin/manifest.json service entry point must be clone-root relative\n' >&2; exit 1; }

printf 'ok       layout\n'
