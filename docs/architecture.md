# Architecture

## Session lock

The stock `omarchy.lock` service is cloned into a user-owned plugin. The clone keeps the original `lock` IPC target and remains the only service holding a `WlSessionLock`.

The overlay adds:

- an immediate root bridge request for face authentication after the lock surface becomes secure;
- enrollment/availability probing through `facelock is-enrolled --quiet`;
- a top-center face state machine for idle, scanning, success, failure, and unavailable states, with the OmaID logo shown on success;
- a user-runtime socket server for sudo visual events;
- a top-center, focus-free sudo scan pill that shows the OmaID logo after successful face authentication.

Password and fingerprint PAM contexts remain separate. The lock face path uses the root bridge because the Quickshell PAM subprocess is non-root and has no logind session; the bridge invokes Facelock directly as root and returns only a request-correlated result. A face result never creates a public unlock IPC method.

## PAM services

- `omarchy-lock-face` remains a face-only PAM service with a deny terminator for direct PAM consumers; the Quickshell lock UI uses the root bridge because its PAM subprocess cannot satisfy Facelock's daemon session gate.
- `sudo` receives a Facelock `sufficient` rule plus optional notifier calls.
- `polkit-1` receives only the Facelock rule; the existing Omarchy polkit agent remains in charge.
- `sddm-auth` is an SDDM-specific chain with shell/nologin checks before face auth and a password chain without `nullok` after it.

Shared authentication stacks are never edited.

## SDDM

The greeter is outside the user session. SDDM receives a root-owned theme from `/usr/local/share/sddm/themes` and an SDDM-specific PAM service. The theme copies the canonical OmaID face asset because the greeter cannot read the user's plugin directory.

## Privilege boundary

The repository contains user UI source, a small root notifier, and the socket-activated face bridge. The bridge is installed under `/usr/libexec/omaid`; it accepts only the configured user's requests, invokes a fixed Facelock command with a sanitized environment, and never exposes a general unlock or privilege API. The notifier remains cosmetic.
