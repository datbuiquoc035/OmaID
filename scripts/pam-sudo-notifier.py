#!/usr/bin/env python3

import argparse
import os
import shutil
import stat
import tempfile
from pathlib import Path

BEGIN = "auth optional pam_exec.so quiet /usr/libexec/omaid/omaid-notify begin"
FALLBACK = "auth optional pam_exec.so quiet /usr/libexec/omaid/omaid-notify fallback"
END = "account optional pam_exec.so quiet /usr/libexec/omaid/omaid-notify end"


def normalized(line: str) -> str:
    return " ".join(line.split())


def build_lines(path: Path) -> list[str]:
    lines = path.read_text().splitlines()
    cleaned = [line for line in lines if "omaid-notify" not in line]
    face_index = next(
        (
            index
            for index, line in enumerate(cleaned)
            if normalized(line).startswith("auth")
            and "pam_facelock.so" in normalized(line)
        ),
        None,
    )
    if face_index is None:
        raise RuntimeError("pam_facelock.so is not present in the sudo auth stack")

    updated = cleaned[:face_index] + [BEGIN, cleaned[face_index], FALLBACK] + cleaned[face_index + 1 :]
    account_index = next(
        (
            index
            for index, line in enumerate(updated)
            if normalized(line).startswith("account")
        ),
        None,
    )
    if account_index is None:
        updated.append(END)
    else:
        updated.insert(account_index + 1, END)

    if updated and updated[-1] != "":
        updated.append("")
    return updated


def remove_lines(path: Path) -> list[str]:
    return [line for line in path.read_text().splitlines() if "omaid-notify" not in line]


def write_updated(path: Path, updated: list[str], backup_dir: Path, dry_run: bool) -> None:
    current = path.read_text().splitlines()
    if current == updated:
        print("sudo notifier already has the requested state")
        return

    if dry_run:
        print("would update", path)
        for line in updated:
            print(line)
        return

    backup_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    backup = backup_dir / f"sudo.{os.getpid()}"
    shutil.copy2(path, backup)
    metadata = path.stat()
    os.chmod(backup, stat.S_IMODE(metadata.st_mode))
    os.chown(backup, metadata.st_uid, metadata.st_gid)

    with tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        dir=path.parent,
        prefix=f".{path.name}.omaid.",
        delete=False,
    ) as handle:
        temporary = Path(handle.name)
        handle.write("\n".join(updated) + "\n")
        handle.flush()
        os.fsync(handle.fileno())

    os.chmod(temporary, stat.S_IMODE(metadata.st_mode))
    os.chown(temporary, metadata.st_uid, metadata.st_gid)
    os.replace(temporary, path)
    print(f"updated {path}; backup: {backup}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", type=Path, required=True)
    parser.add_argument("--backup-dir", type=Path, required=True)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--remove", action="store_true")
    args = parser.parse_args()
    updated = remove_lines(args.file) if args.remove else build_lines(args.file)
    write_updated(args.file, updated, args.backup_dir, args.dry_run)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
