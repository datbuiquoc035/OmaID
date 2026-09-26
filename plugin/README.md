# OmaID plugin overlay

These files are overlaid onto a trusted clone of Omarchy's first-party `omarchy.lock` plugin. `manifest.json` carries the OmaID identity: its `name` is `OmaID` and its `version` tracks the repository `VERSION`. The installer stamps it into the clone, rewrites `id` to the per-user clone id, and refuses to stamp a clone that does not declare `omarchy.clonedFrom: omarchy.lock`. The `authentication` capability and `clonedFrom` are preserved rather than invented. Entry point paths in the manifest are relative to the clone root, not to this directory.

The overlay keeps the stock `lock` IPC target and `WlSessionLock` ownership. It adds an immediate face request through the root bridge, an unblurred lock view, a top-center face badge, and a session-runtime socket for a sudo scan pill that shows the success logo.

The canonical face artwork belongs at `assets/face-id/face.svg` in the repository and is copied into the installed clone. The successful-scan artwork is copied from `assets/omarchy-logo-hackerman.png`.
