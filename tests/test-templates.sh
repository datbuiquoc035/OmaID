#!/usr/bin/env bash
set -euo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root_dir"

require_text() {
  local file="$1"
  local text="$2"
  if ! grep -Fq -- "$text" "$file"; then
    printf 'missing %s in %s\n' "$text" "$file" >&2
    exit 1
  fi
}

reject_text() {
  local file="$1"
  local text="$2"
  if grep -Fq -- "$text" "$file"; then
    printf 'unexpected %s in %s\n' "$text" "$file" >&2
    exit 1
  fi
}

require_text plugin/Service.qml 'faceBridgeConfigured'
require_text plugin/Service.qml 'FaceAuthClient'
require_text plugin/FaceAuthClient.qml 'Socket'
require_text root/omaid-face-bridge.service 'ExecStart=/usr/libexec/omaid/omaid-face-bridge'
require_text root/omaid-face-bridge.socket 'ListenStream=/run/omaid/face-auth.sock'
reject_text plugin/Service.qml 'faceStartDelay'
require_text plugin/Service.qml 'assets/omarchy-logo-hackerman.png'
require_text plugin/Service.qml 'sessionLock.secure'
reject_text plugin/Service.qml 'root.sessionLock'
require_text plugin/FaceAuthSocket.qml 'SocketServer'
require_text plugin/LockView.qml 'FaceIdBadge'
require_text plugin/LockView.qml 'anchors.top: parent.top'
require_text plugin/LockView.qml 'successAssetSource: root.faceSuccessAssetSource'
require_text plugin/SudoScanPill.qml 'successAssetSource: root.successAssetSource'
require_text plugin/Service.qml 'id: sudoSuccessTimer'
require_text plugin/FaceIdBadge.qml 'id: successImage'
reject_text plugin/LockView.qml 'MultiEffect'
require_text root/pam/omaid-lock-face.pam 'pam_deny.so'
require_text root/pam/omaid-sddm-auth.pam 'pam_shells.so'
require_text scripts/install-sddm.sh 'facelock pam add --service sddm-auth'
reject_text root/pam/omaid-sddm-password.pam 'nullok'
require_text sddm/Main.qml 'onInformationMessage'
require_text sddm/Main.qml 'sddm.login'

printf 'ok       templates\n'
