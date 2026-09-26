# Testing

Testing is staged so PAM failures cannot lock the only active session.

## Source checks

```bash
./scripts/validate.sh
```

## Test suite

```bash
./tests/run.sh
```

Runs the source checks, the layout and template guards, and the headless QML tests in `tests/qml`. The QML tests need a render backend and `qmltestrunner`; they are skipped with a `skip` line when it is missing. `tests/qml/stubs` stands in for the `qs.Commons` singletons, which only resolve inside a running Quickshell.

`tests/qml/tst_successmark.qml` covers the drawn mark: that it starts empty, fills completely, keeps its stagger, replays instead of resuming, and reverses the two stubs. `tests/qml/tst_faceidbadge.qml` covers the badge around it: that success shows the mark and suppresses the raster fallback, that `image` mode inverts that, and that no other state shows either.

## Backend checks

```bash
facelock capabilities
facelock is-enrolled --quiet
sudo facelock status --json
sudo facelock devices --json
sudo facelock test --user "$USER"
```

`facelock test` must be judged from its human output; exit code zero alone is not a match result.

## Lock checks

1. Validate the cloned plugin.
2. Restart the shell while unlocked.
3. Use the non-locking lock preview.
4. Test face success, face failure, password fallback, no enrollment, and camera failure.
5. On face success, watch that the mark finishes drawing before the screen unlocks. The hold is deliberately longer than the animation; if it cuts off mid-stroke, `faceSuccessTimer` has dropped to or below `SuccessMark.totalDuration` and `tests/test-templates.sh` will say so.
6. Repeat with `OMAID_MOTION=0` to confirm the static mark renders in full, and with `OMAID_SUCCESS_STYLE=image` to confirm the raster fallback still works.
7. Keep a root TTY open during the first real lock test.

## Sudo checks

Test the pill in normal, maximized, and fullscreen terminals. Verify that it never takes focus, clears on every terminal outcome, and disappears when no session socket exists.

## SDDM checks

Use a disposable guest or controlled VT session. Test face success, face failure plus password, empty token rejection, wrong password, camera failure, theme reload, and TTY recovery.

## Rollback checks

Verify that:

- re-enabling `omarchy.lock` restores the stock service;
- OmaID PAM rules can be removed without touching shared stacks;
- the SDDM theme/config backup restores the previous greeter;
- biometric data is preserved unless an explicit purge is requested.
