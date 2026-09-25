# OmaID

OmaID is an Omarchy face-authentication integration built around Facelock.

The project targets four surfaces:

- the SDDM login greeter;
- the Omarchy/Quickshell session lock;
- terminal `sudo` authentication;
- graphical polkit authentication.

The repository is the source of truth. Runtime copies are created only by explicit installer commands.

## Current status

The user lock overlay and a socket-activated root face bridge are implemented and tested on the current Omarchy host. The bridge is required because Quickshell's non-root PAM subprocess is not attached to a logind session; it preserves Facelock's daemon-side SSH/session checks instead of weakening them.

## Design

- `plugin/` is an overlay of the stock `omarchy.lock` service. The installer creates a trusted clone and overlays these files.
- `sddm/` is a root-owned theme installed outside the user home because SDDM runs as the `sddm` user.
- `root/` contains the small privileged event notifier, face bridge, systemd units, and PAM templates.
- `assets/face-id/` is the canonical location for the future face artwork. Installers copy it into both the user plugin and SDDM theme.
- Facelock models, enrollment data, encryption keys, logs, and PAM backups are never stored in this repository.

## Safety model

- Face rules are always `sufficient`, never `required`.
- The session lock uses a separate root face bridge with a request-correlated result; the standalone face-only PAM service remains available for direct PAM consumers.
- SDDM uses a hardened SDDM-specific chain that rejects an empty password token after face authentication abstains.
- The sudo pill is cosmetic and never grants authorization.
- Root installers require an explicit apply flag and keep backups.
- SDDM autologin changes are a separate opt-in operation.

## Development commands

```bash
./scripts/check-deps.sh
./scripts/validate.sh
./scripts/install-user-plugin.sh --dry-run
./scripts/install-root.sh --dry-run --bridge --bridge-user USER
./scripts/install-sudo-notifier.sh --dry-run
./scripts/install-sddm.sh --dry-run
```

Do not run an `--apply` installer until the generated plan and backups have been reviewed.
