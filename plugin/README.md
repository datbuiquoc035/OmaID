# OmaID plugin overlay

These files are overlaid onto a trusted clone of Omarchy's first-party `omarchy.lock` plugin. The installer preserves the clone-generated manifest and capability metadata.

The overlay keeps the stock `lock` IPC target and `WlSessionLock` ownership. It adds a delayed face request through the root bridge, an unblurred lock view, a face badge, and a session-runtime socket for the sudo scan pill.

The canonical face artwork belongs at `assets/face-id/face.svg` in the repository and is copied into the installed clone.
