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
require_text plugin/FaceIdBadge.qml 'SuccessMark {'
require_text plugin/SuccessMark.qml 'PathSvg { path: "M640 1160H40V40H1160V1160H720" }'
require_text plugin/SuccessMark.qml 'trim.end:'
require_text plugin/SuccessMark.qml 'trim.start:'
require_text plugin/Service.qml 'OMAID_SUCCESS_STYLE'
require_text plugin/Service.qml 'OMAID_MOTION'
require_text plugin/LockView.qml 'successStyle: root.faceSuccessStyle'
require_text plugin/SudoScanPill.qml 'successStyle: root.successStyle'
reject_text plugin/Service.qml 'interval: 350'
reject_text plugin/LockView.qml 'MultiEffect'
require_text root/pam/omaid-lock-face.pam 'pam_deny.so'
require_text root/pam/omaid-sddm-auth.pam 'pam_shells.so'
require_text scripts/install-sddm.sh 'facelock pam add --service sddm-auth'
reject_text root/pam/omaid-sddm-password.pam 'nullok'
require_text sddm/Main.qml 'onInformationMessage'
require_text sddm/Main.qml 'sddm.login'

# The mark draws for SuccessMark.totalDuration, so every success state that
# shows it has to stay open longer than that or the animation is cut off
# mid-stroke. Extract both numbers instead of restating them here, so retuning
# the choreography cannot silently desync the holds.
mark_duration=$(grep -oE 'totalDuration: [0-9]+' plugin/SuccessMark.qml | grep -oE '[0-9]+')
face_hold=$(awk '/id: faceSuccessTimer/{found=1} found && /interval: [0-9]+/{gsub(/[^0-9]/, "", $2); print $2; exit}' plugin/Service.qml)
sudo_hold=$(awk '/id: sudoSuccessTimer/{found=1} found && /interval: [0-9]+/{gsub(/[^0-9]/, "", $2); print $2; exit}' plugin/Service.qml)

if [[ -z "$mark_duration" || -z "$face_hold" || -z "$sudo_hold" ]]; then
  printf 'could not read the success hold timings\n' >&2
  exit 1
fi

if ((face_hold <= mark_duration)); then
  printf 'faceSuccessTimer (%sms) does not outlast SuccessMark.totalDuration (%sms)\n' "$face_hold" "$mark_duration" >&2
  exit 1
fi

if ((sudo_hold <= mark_duration)); then
  printf 'sudoSuccessTimer (%sms) does not outlast SuccessMark.totalDuration (%sms)\n' "$sudo_hold" "$mark_duration" >&2
  exit 1
fi

printf 'ok       templates\n'
