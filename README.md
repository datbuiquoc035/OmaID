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

`./install.sh` is the single entrypoint. It sequences the per-surface installers, escalates only the steps that write outside the user home, and refuses to run under `sudo` (that would install the plugin as `root.lock` instead of `<you>.lock`).

Every installer is dry-run by default and only touches the system with an explicit `--apply`. Review the generated plan before applying anything. Run all commands from the repository root.

```bash
# Dependencies (Facelock, TPM, camera, omarchy, jq)
./scripts/check-deps.sh

# The common case: session lock plugin + root face bridge
./install.sh                 # dry run, the default
./install.sh --apply

# Everything, including the sudo pill and the SDDM theme
./install.sh all --apply

# Register the facelock PAM rules while you are there
./install.sh --apply --pam omarchy-lock-face,sudo,polkit-1
```

Surfaces are `plugin`, `root`, `notifier`, `sddm`, and `all`; the default is `plugin root`. The root face bridge and the lock PAM service are on by default because the lock face path needs them. Run `./install.sh --help` for the rest.

The underlying scripts stay available when you want one step in isolation:

```bash
# Session lock plugin (no root; stamps the OmaID manifest into the clone)
./scripts/install-user-plugin.sh --dry-run
./scripts/install-user-plugin.sh --apply

# Root bridge, notifier, and PAM service
sudo ./scripts/install-root.sh --dry-run --bridge --bridge-user "$USER"
sudo ./scripts/install-root.sh --apply   --bridge --bridge-user "$USER"

# Optional: sudo scan pill (refuses to edit a sudo stack without pam_facelock.so)
sudo ./scripts/install-sudo-notifier.sh --dry-run
sudo ./scripts/install-sudo-notifier.sh --apply

# Optional: SDDM greeter theme
sudo ./scripts/install-sddm.sh --dry-run
sudo ./scripts/install-sddm.sh --apply
sudo ./scripts/install-sddm.sh --apply-pam
```

Verify without changing PAM or SDDM:

```bash
sudo -k && sudo -v
omarchy-shell lock lock
```

The `root` surface is not optional for the lock screen. The lock face path runs through the root bridge because Quickshell's PAM subprocess is not attached to a logind session; without the bridge installed, face authentication at the lock will not succeed.

The face badge artwork is not bundled. Place a square or near-square image at `assets/face-id/face.svg` before applying, or the badge renders without its image. `install.sh` warns when it is missing.

See [docs/install.md](docs/install.md) for the reasoning behind the split and the Facelock enrolment commands.

## Update

`install.sh` is idempotent — it reuses the existing clone, re-stamps the manifest, and recompiles the root helpers — so re-run it after every pull:

```bash
git pull
./tests/run.sh
./install.sh --apply --restart
```

Re-run the `notifier` and `sddm` surfaces only when their inputs changed (`root/src/*.c`, `root/pam/*`, `root/*.service`, `sddm/`). The sudo notifier keeps a timestamped backup under `/var/lib/omaid/backups` and refuses to touch a sudo stack that lacks `pam_facelock.so`.

The version is defined once in `VERSION` and mirrored into `plugin/manifest.json`. Bump `VERSION`, re-apply the plugin, and `tests/test-layout.sh` fails if the two drift apart.

## Remove

Preview first, then apply. Like `install.sh`, `uninstall.sh` is dry-run by default, escalates only the root steps itself, and refuses to run under `sudo`.

```bash
./uninstall.sh --dry-run          # everything
./uninstall.sh --apply

./uninstall.sh --dry-run plugin   # one surface
./uninstall.sh --apply notifier
```

Surfaces are `plugin`, `root`, `notifier`, `sddm`, and `all`; the default is `all`. The old flag form (`--plugin`, `--root`, `--sddm`) still works.

- `plugin` removes the `$USER.lock` clone and re-enables first-party `omarchy.lock`.
- `root` removes the OmaID PAM rules via `facelock pam remove`, disables the bridge socket, and deletes the units, the `/usr/libexec/omaid` binaries, and the runtime socket. It includes the notifier removal.
- `notifier` removes only the OmaID events from `/etc/pam.d/sudo` and leaves the rest installed.
- `sddm` removes `/usr/local/share/sddm/themes/omaid` and the OmaID SDDM drop-in.

Facelock models, enrollment data, encryption keys, and logs are never stored in this repository and are not touched by uninstall. Remove them separately with `facelock` if you want the backend gone too.

Keep a root recovery shell available while testing any PAM change.

## License

Released under the MIT License. See [LICENSE](LICENSE).

