# Testing

Testing is staged so PAM failures cannot lock the only active session.

## Source checks

```bash
./scripts/validate.sh
```

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
5. Keep a root TTY open during the first real lock test.

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
