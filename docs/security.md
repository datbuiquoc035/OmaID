# Security notes

## Authentication

- `pam_facelock.so` must be `sufficient`, never `required` or `requisite`.
- Camera failure, timeout, missing enrollment, or internal errors must fall through to password authentication.
- The face-only lock service must not contain a password fallback.
- SDDM's empty-token path must reject an empty password if face authentication abstains.

## Session-lock bridge

The Quickshell lock service cannot use Facelock's daemon transport directly because its non-root PAM subprocess is not registered with logind. The root bridge must:

- listen on a root-created Unix socket owned by the target user with mode `0600`;
- verify the peer UID on every connection;
- accept only a bounded, request-correlated `AUTH` line;
- execute only the fixed `/usr/bin/facelock auth` command with fixed arguments and a sanitized environment;
- run as root only for the Facelock child and never evaluate shell input;
- terminate the child when the client disconnects or the request times out;
- never set `security.abort_if_ssh=false` as a workaround.

The bridge returns a face result only to the requesting QML client. It does not expose a general-purpose unlock or privilege operation.

## Privileged code

The sudo notifier is a small root-owned helper with fixed arguments. It must:

- never accept a password;
- never evaluate a shell string from PAM data;
- validate the PAM service and username;
- write only bounded event data;
- fail open if the graphical session or socket is unavailable.

The socket is cosmetic. A user process must not be able to use it to unlock a session or approve a privileged command.

## Storage

Do not commit:

- face embeddings;
- face images;
- encryption keys;
- PAM backups;
- logs;
- tokens or credentials.

Facelock remains responsible for biometric storage and model verification.

## UI boundary

The QML plugin is user-writable and therefore must not be treated as a trusted authentication root. The PAM result is the only authority for unlocking or approval.
