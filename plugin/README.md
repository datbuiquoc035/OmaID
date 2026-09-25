# OmaID plugin overlay

These files are overlaid onto a trusted clone of Omarchy's first-party `omarchy.lock` plugin. The installer preserves the clone-generated manifest and capability metadata.

The overlay keeps the stock `lock` IPC target and `WlSessionLock` ownership. It adds an immediate face request through the root bridge, an unblurred lock view, a top-center face badge, and a session-runtime socket for a sudo scan pill that shows the success logo.

The canonical face artwork belongs at `assets/face-id/face.svg` in the repository and is copied into the installed clone. The successful-scan artwork is copied from `assets/omarchy-logo-hackerman.png`.
