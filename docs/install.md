# Installation

Installation is intentionally split.

`./install.sh` sequences the steps below and escalates only the ones that need root. It is dry-run by default. Run it as your normal user: under `sudo` the plugin step would install as `root.lock` instead of `<you>.lock`, so it refuses to start as root.

```bash
./install.sh --dry-run   # plan for the default surfaces: plugin root
./install.sh --apply
```

The per-surface scripts documented here remain the source of truth and can still be run individually.

## 1. Dependencies

```bash
sudo pacman -S --needed onnxruntime-cpu
yay -S --needed facelock-bin
sudo facelock setup --camera /dev/video2 --encryption tpm --no-pam --systemd --no-enroll
sudo facelock enroll --user "$USER" --label primary
sudo facelock test --user "$USER"
```

Keep Facelock's default daemon mode for `sudo` and other PAM consumers. The session-lock bridge invokes the fixed root `facelock auth` path directly; do not set `security.abort_if_ssh=false` to work around Quickshell's PAM session provenance.

## 2. User plugin

Preview first:

```bash
./scripts/install-user-plugin.sh --dry-run
```

Apply only after reviewing the generated plan:

```bash
./scripts/install-user-plugin.sh --apply
```

The installer creates or reuses a clone of `omarchy.lock`, then overlays the repository's QML and asset files.

## 3. Root integration

Preview:

```bash
./scripts/install-root.sh --dry-run
```

Apply after the Facelock backend and user plugin have been tested:

```bash
./scripts/install-root.sh --apply --bridge --bridge-user "$USER"
```

This installs the root notifier, the face bridge at `/usr/libexec/omaid/omaid-face-bridge`, and the socket-activated `omaid-face-bridge.socket`. The socket is owned by the target user with mode `0600`; the bridge runs `/usr/bin/facelock auth` as root with fixed arguments and returns only a request-correlated result.

For the terminal sudo pill, add the notifier lines only after Facelock is present in the sudo stack:

```bash
./scripts/install-sudo-notifier.sh --dry-run
./scripts/install-sudo-notifier.sh --apply
```

The notifier provisioner makes a timestamped root backup under `/var/lib/omaid/backups` and refuses to edit a sudo stack that does not already contain `pam_facelock.so`.

Validate face authentication without changing PAM or SDDM:

```bash
sudo -k
sudo -v
omarchy-shell lock lock
```

Keep a root recovery shell available while testing any PAM change.

`./uninstall.sh` reverses this, with the same surface names and the same dry-run default:

```bash
./uninstall.sh --dry-run
./uninstall.sh --apply
```

## 4. SDDM

SDDM is separate because the current machine has autologin enabled:

```bash
./scripts/install-sddm.sh --dry-run
./scripts/install-sddm.sh --apply
./scripts/install-sddm.sh --apply-pam
```

`--apply-pam` installs the SDDM-specific auth templates and asks Facelock's audited writer to add the face rule. It does not rewrite `/etc/pam.d/sddm`; review that include change separately. The SDDM step must be performed from a controlled test session with TTY recovery available.
