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

## Install

Every installer is dry-run by default and only touches the system with an explicit `--apply`. Review the generated plan before applying anything. Steps marked `sudo` write outside the user home and refuse to run unprivileged. Run all commands from the repository root.

```bash
# 1. Dependencies (Facelock, TPM, camera, omarchy, jq)
./scripts/check-deps.sh

# 2. Static checks — bash/C/python/QML syntax plus the plugin manifest
./scripts/validate.sh
./tests/run.sh

# 3. Session lock plugin (no root; stamps the OmaID manifest into the clone)
./scripts/install-user-plugin.sh --dry-run
./scripts/install-user-plugin.sh --apply

# 4. Root bridge, notifier, and PAM service (required for the lock face path)
sudo ./scripts/install-root.sh --dry-run --bridge --bridge-user "$USER"
sudo ./scripts/install-root.sh --apply   --bridge --bridge-user "$USER"

# 5. Optional: sudo scan pill (refuses to edit a sudo stack without pam_facelock.so)
sudo ./scripts/install-sudo-notifier.sh --dry-run
sudo ./scripts/install-sudo-notifier.sh --apply

# 6. Optional: SDDM greeter theme
sudo ./scripts/install-sddm.sh --dry-run
sudo ./scripts/install-sddm.sh --apply
sudo ./scripts/install-sddm.sh --apply-pam
```

Verify without changing PAM or SDDM:

```bash
sudo -k && sudo -v
omarchy-shell lock lock
```

Step 4 is not optional for the lock screen. The lock face path runs through the root bridge because Quickshell's PAM subprocess is not attached to a logind session; without the bridge installed, face authentication at the lock will not succeed.

The face badge artwork is not bundled. Place a square or near-square image at `assets/face-id/face.svg` before applying, or the badge renders without its image.

See [docs/install.md](docs/install.md) for the reasoning behind the split and the Facelock enrolment commands.

## Update

The plugin installer is idempotent — it reuses the existing clone and re-stamps the manifest, so re-run it after every pull:

```bash
git pull
./tests/run.sh
./scripts/install-user-plugin.sh --dry-run
./scripts/install-user-plugin.sh --apply --restart
```

Re-run the root, sudo-notifier, and SDDM steps only when their inputs changed (`root/src/*.c`, `root/pam/*`, `root/*.service`, `sddm/`). They compile and install unconditionally and are safe to repeat; the sudo notifier keeps a timestamped backup under `/var/lib/omaid/backups` and refuses to touch a sudo stack that lacks `pam_facelock.so`.

The version is defined once in `VERSION` and mirrored into `plugin/manifest.json`. Bump `VERSION`, re-apply the plugin, and `tests/test-layout.sh` fails if the two drift apart.

## Remove

Preview first, then apply. `--root` and `--sddm` require `sudo`; `--plugin` does not.

```bash
./scripts/uninstall.sh --dry-run --plugin --root --sddm
./scripts/uninstall.sh --apply   --plugin --root --sddm
```

Select surfaces individually with any combination of `--plugin`, `--root`, and `--sddm`.

- `--plugin` removes the `$USER.lock` clone and re-enables first-party `omarchy.lock`.
- `--root` removes the OmaID PAM rules via `facelock pam remove`, disables the bridge socket, and deletes the units, the `/usr/libexec/omaid` binaries, and the runtime socket.
- `--sddm` removes `/usr/local/share/sddm/themes/omaid` and the OmaID SDDM drop-in.

To undo only the sudo PAM events and keep the rest installed:

```bash
sudo ./scripts/install-sudo-notifier.sh --remove
```

Facelock models, enrollment data, encryption keys, and logs are never stored in this repository and are not touched by uninstall. Remove them separately with `facelock` if you want the backend gone too.

Keep a root recovery shell available while testing any PAM change.

## License

Released under the MIT License. See [LICENSE](LICENSE).

