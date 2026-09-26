# Architecture

## Session lock

The stock `omarchy.lock` service is cloned into a user-owned plugin. The clone keeps the original `lock` IPC target and remains the only service holding a `WlSessionLock`.

The overlay adds:

- an immediate root bridge request for face authentication after the lock surface becomes secure;
- enrollment/availability probing through `facelock is-enrolled --quiet`;
- a top-center face state machine for idle, scanning, success, failure, and unavailable states, with the Omarchy mark drawn on success;
- a user-runtime socket server for sudo visual events;
- a top-center, focus-free sudo scan pill that shows the Omarchy mark after successful face authentication.

Password and fingerprint PAM contexts remain separate. The lock face path uses the root bridge because the Quickshell PAM subprocess is non-root and has no logind session; the bridge invokes Facelock directly as root and returns only a request-correlated result. A face result never creates a public unlock IPC method.

## Success mark

`plugin/SuccessMark.qml` draws the Omarchy mark with the same stroke-dash choreography as the omarchy.org header logo. The site normalises every path with `pathLength="1"` and then animates `stroke-dashoffset` from 1 to 0, so the dash maths is relative to path length rather than pixels. `ShapePath.trim` is the native equivalent, because `trim.start` and `trim.end` are also path-length fractions, so the five paths port over as their verbatim `d` strings with no path-length arithmetic. The two stubs are the site's `mark-draw-back` paths: they grow from their far end, which is a moving `trim.start` with `trim.end` pinned at 1.

The mark is geometry rather than an asset, so it is stroked in the badge's own state colour and always matches the badge border it sits inside. Success uses the same fixed green the badge already used for that state; `Color.lock` has no success entry to theme against. It needs `ShapePath.trim`, so **Qt 6.10 or newer**. `OMAID_SUCCESS_STYLE=image` falls back to the bundled `assets/omarchy-logo-hackerman.png` raster on an older Qt, and `OMAID_MOTION=0` renders the mark fully drawn and static; QML has no equivalent of `prefers-reduced-motion`, so the environment is the only lever.

`SuccessMark.totalDuration` is the largest delay plus duration across all five paths, which is *not* the last path in the list: the inner frame starts late enough to outlive it. Every success state that shows the mark holds open longer than that, and `tests/test-templates.sh` reads both numbers out of the sources and fails if a hold ever drops to or below the animation.

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
