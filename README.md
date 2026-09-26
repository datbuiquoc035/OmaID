# OmaID

OmaID is an Omarchy face-authentication integration built around Facelock.

![OmaID lock screen with the face badge and password field](preview.png)

The project targets four surfaces:

- the SDDM login greeter;
- the Omarchy/Quickshell session lock;
- terminal `sudo` authentication;
- graphical polkit authentication.

This project is inspired by [rio.facelock](https://github.com/harshjsh01/rio.facelock)

## Current status

The user lock overlay and a socket-activated root face bridge are implemented and tested on the current Omarchy host. The bridge is required because Quickshell's non-root PAM subprocess is not attached to a logind session; it preserves Facelock's daemon-side SSH/session checks instead of weakening them.

## Design

- `plugin/` is an overlay of the stock `omarchy.lock` service. The installer creates a trusted clone and overlays these files.
- `sddm/` is a root-owned theme installed outside the user home because SDDM runs as the `sddm` user.
- `root/` contains the small privileged event notifier, face bridge, systemd units, and PAM templates.
- `assets/face-id/` is the canonical location for the future face artwork. Installers copy it into both the user plugin and SDDM theme.
- Facelock models, enrollment data, encryption keys, logs, and PAM backups are never stored in this repository.

