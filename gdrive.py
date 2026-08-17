#!/usr/bin/env python3
"""Small rclone backend for the Omarchy Google Drive widget."""

from __future__ import annotations

import argparse
import heapq
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


REMOTE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9 ._-]*$")
SKIP_DIRECTORIES = {".Trash", ".cache", ".git", "lost+found"}


def clean_text(value: str, limit: int = 240) -> str:
  text = " ".join((value or "").split())
  return text if len(text) <= limit else text[: limit - 1] + "…"


def normalize_remote(value: str) -> str:
  remote = (value or "gdrive").strip().removesuffix(":").strip()
  if not REMOTE_RE.fullmatch(remote):
    raise ValueError("Remote name may only contain letters, numbers, spaces, dots, underscores, and hyphens")
  return remote


def normalize_mount(value: str) -> Path:
  path = Path(os.path.expandvars(os.path.expanduser(value or "~/Google Drive"))).resolve()
  if path == Path("/") or path == Path.home().resolve():
    raise ValueError("Choose a mount folder inside your home directory, not the directory itself")
  return path


def run(command: list[str], timeout: float = 10) -> tuple[int, str, str]:
  try:
    completed = subprocess.run(
      command,
      check=False,
      capture_output=True,
      text=True,
      timeout=timeout,
    )
  except FileNotFoundError as error:
    return 127, "", str(error)
  except subprocess.TimeoutExpired as error:
    stdout = error.stdout.decode() if isinstance(error.stdout, bytes) else (error.stdout or "")
    stderr = error.stderr.decode() if isinstance(error.stderr, bytes) else (error.stderr or "")
    return 124, stdout, stderr or "Command timed out"
  return completed.returncode, completed.stdout.strip(), completed.stderr.strip()


def configured_remotes(rclone: str) -> tuple[set[str], str]:
  code, stdout, stderr = run([rclone, "listremotes"], timeout=5)
  if code != 0:
    return set(), clean_text(stderr or stdout or "Could not read rclone configuration")
  return {line.strip().removesuffix(":") for line in stdout.splitlines() if line.strip()}, ""


def mount_info(path: Path) -> tuple[bool, bool, str, str]:
  findmnt = shutil.which("findmnt")
  if not findmnt:
    return False, False, "", ""
  code, stdout, _ = run([findmnt, "-rn", "-M", str(path), "-o", "FSTYPE,SOURCE"], timeout=3)
  if code != 0 or not stdout:
    return False, False, "", ""
  first = stdout.splitlines()[0].split(None, 1)
  fs_type = first[0] if first else ""
  source = first[1] if len(first) > 1 else ""
  return True, "rclone" in fs_type.lower(), fs_type, source


def storage_usage(rclone: str, remote: str) -> tuple[int, int, bool, str]:
  code, stdout, stderr = run([rclone, "about", f"{remote}:", "--json"], timeout=12)
  if code != 0:
    return 0, 0, False, clean_text(stderr or stdout or "Storage usage is unavailable")
  try:
    data = json.loads(stdout)
  except json.JSONDecodeError:
    return 0, 0, False, "rclone returned invalid storage information"
  total = max(0, int(data.get("total") or 0))
  used = data.get("used")
  if used is None and total > 0 and data.get("free") is not None:
    used = total - int(data.get("free") or 0)
  used_value = max(0, int(used or 0))
  return used_value, total, total > 0, ""


def scan_recent_files(path: Path, limit: int, max_depth: int = 4) -> list[dict[str, Any]]:
  """Scan a bounded part of the live mount without traversing an entire Drive."""
  if not path.is_dir():
    return []

  recent: list[tuple[int, int, dict[str, Any]]] = []
  pending: list[tuple[Path, int]] = [(path, 0)]
  visited = 0
  counter = 0
  deadline = time.monotonic() + 6

  while pending and visited < 5000 and time.monotonic() < deadline:
    folder_path, depth = pending.pop()
    try:
      entries = list(os.scandir(folder_path))
    except OSError:
      continue

    for entry in entries:
      if visited >= 5000 or time.monotonic() >= deadline:
        break
      visited += 1
      try:
        if entry.is_dir(follow_symlinks=False):
          if depth < max_depth and entry.name not in SKIP_DIRECTORIES:
            pending.append((Path(entry.path), depth + 1))
          continue
        if not entry.is_file(follow_symlinks=False):
          continue
        stat = entry.stat(follow_symlinks=False)
      except OSError:
        continue

      file_path = Path(entry.path)
      try:
        relative = file_path.relative_to(path)
      except ValueError:
        continue
      parent = str(relative.parent)
      row = {
        "name": entry.name,
        "path": str(file_path),
        "folder": "/" if parent in ("", ".") else parent,
        "modifiedTs": int(stat.st_mtime),
        "sizeBytes": max(0, int(stat.st_size)),
      }
      counter += 1
      heap_entry = (row["modifiedTs"], counter, row)
      if len(recent) < limit:
        heapq.heappush(recent, heap_entry)
      else:
        heapq.heappushpop(recent, heap_entry)

  return [entry[2] for entry in sorted(recent, reverse=True)]


def search_mounted_files(path: Path, query: str, limit: int) -> tuple[list[dict[str, Any]], bool]:
  """Search the mounted Drive with bounded traversal and rank useful matches first."""
  terms = [term.casefold() for term in query.split() if term]
  if not terms or not path.is_dir():
    return [], False

  matches: list[tuple[int, int, dict[str, Any]]] = []
  pending: list[Path] = [path]
  visited = 0
  deadline = time.monotonic() + 12
  truncated = False

  while pending:
    if visited >= 25000 or time.monotonic() >= deadline:
      truncated = True
      break
    folder_path = pending.pop()
    try:
      entries = list(os.scandir(folder_path))
    except OSError:
      continue

    for entry in entries:
      if visited >= 25000 or time.monotonic() >= deadline:
        truncated = True
        break
      visited += 1
      try:
        if entry.is_dir(follow_symlinks=False):
          if entry.name not in SKIP_DIRECTORIES:
            pending.append(Path(entry.path))
          continue
        if not entry.is_file(follow_symlinks=False):
          continue
      except OSError:
        continue

      file_path = Path(entry.path)
      try:
        relative = file_path.relative_to(path)
      except ValueError:
        continue
      searchable = str(relative).casefold()
      if not all(term in searchable for term in terms):
        continue

      try:
        stat = entry.stat(follow_symlinks=False)
      except OSError:
        continue
      name_folded = entry.name.casefold()
      phrase = " ".join(terms)
      rank = 0 if name_folded == phrase else (1 if name_folded.startswith(phrase) else (2 if phrase in name_folded else 3))
      parent = str(relative.parent)
      row = {
        "name": entry.name,
        "path": str(file_path),
        "folder": "/" if parent in ("", ".") else parent,
        "modifiedTs": int(stat.st_mtime),
        "sizeBytes": max(0, int(stat.st_size)),
      }
      matches.append((rank, -row["modifiedTs"], row))

  matches.sort(key=lambda entry: (entry[0], entry[1], entry[2]["name"].casefold()))
  return [entry[2] for entry in matches[:limit]], truncated


def search_payload(mount_value: str, query: str, limit: int) -> dict[str, Any]:
  mount_path = normalize_mount(mount_value)
  mounted, mounted_by_rclone, fs_type, _ = mount_info(mount_path)
  if not mounted_by_rclone:
    detail = f" ({fs_type})" if mounted else ""
    raise RuntimeError(f"Google Drive is not mounted{detail}")
  files, truncated = search_mounted_files(mount_path, query.strip(), limit)
  return {
    "ok": True,
    "query": query.strip(),
    "files": files,
    "truncated": truncated,
    "lastError": "",
  }


def status_payload(remote_value: str, mount_value: str, limit: int) -> dict[str, Any]:
  remote = normalize_remote(remote_value)
  mount_path = normalize_mount(mount_value)
  rclone = shutil.which("rclone")
  mounted, mounted_by_rclone, fs_type, _ = mount_info(mount_path)

  payload: dict[str, Any] = {
    "ok": True,
    "installed": rclone is not None,
    "running": mounted_by_rclone,
    "authenticated": False,
    "statusText": "Not installed",
    "accountPath": str(mount_path),
    "remoteName": remote,
    "usedBytes": 0,
    "quotaBytes": 0,
    "usagePercent": 0,
    "quotaKnown": False,
    "files": [],
    "warning": "",
    "lastError": "",
  }

  if not rclone:
    return payload

  remotes, config_error = configured_remotes(rclone)
  configured = remote in remotes
  payload["authenticated"] = configured
  if config_error:
    payload["statusText"] = "Configuration unavailable"
    payload["lastError"] = config_error
    return payload
  if not configured:
    payload["statusText"] = "Needs connection"
    return payload
  if mounted and not mounted_by_rclone:
    payload["statusText"] = "Mount folder is busy"
    payload["lastError"] = f"{mount_path} is already mounted as {fs_type}"
    return payload

  used, total, quota_known, quota_warning = storage_usage(rclone, remote)
  payload["usedBytes"] = used
  payload["quotaBytes"] = total
  payload["usagePercent"] = (used / total * 100) if total > 0 else 0
  payload["quotaKnown"] = quota_known
  payload["warning"] = quota_warning
  payload["statusText"] = "Mounted" if mounted_by_rclone else "Ready to mount"
  if mounted_by_rclone:
    payload["files"] = scan_recent_files(mount_path, limit)
  return payload


def ensure_empty_mount_folder(path: Path) -> None:
  path.mkdir(parents=True, exist_ok=True)
  try:
    next(path.iterdir())
  except StopIteration:
    return
  raise RuntimeError(f"Mount folder is not empty: {path}")


def mount_drive(remote_value: str, mount_value: str) -> None:
  remote = normalize_remote(remote_value)
  mount_path = normalize_mount(mount_value)
  rclone = shutil.which("rclone")
  if not rclone:
    raise RuntimeError("rclone is not installed")

  remotes, config_error = configured_remotes(rclone)
  if config_error:
    raise RuntimeError(config_error)
  if remote not in remotes:
    raise RuntimeError(f"rclone remote '{remote}' is not configured")

  mounted, mounted_by_rclone, fs_type, _ = mount_info(mount_path)
  if mounted_by_rclone:
    return
  if mounted:
    raise RuntimeError(f"Mount folder is already used by {fs_type}")
  ensure_empty_mount_folder(mount_path)

  state_dir = Path.home() / ".local" / "state" / "omarchy-google-drive"
  state_dir.mkdir(parents=True, exist_ok=True)
  command = [
    rclone,
    "mount",
    f"{remote}:",
    str(mount_path),
    "--daemon",
    "--vfs-cache-mode", "full",
    "--vfs-cache-max-age", "24h",
    "--dir-cache-time", "5m",
    "--poll-interval", "1m",
    "--log-file", str(state_dir / "rclone.log"),
    "--log-level", "INFO",
  ]
  code, stdout, stderr = run(command, timeout=30)
  if code != 0:
    raise RuntimeError(clean_text(stderr or stdout or "Could not mount Google Drive"))

  deadline = time.monotonic() + 12
  while time.monotonic() < deadline:
    _, active, _, _ = mount_info(mount_path)
    if active:
      return
    time.sleep(0.4)
  raise RuntimeError("rclone started but the Google Drive mount did not appear")


def unmount_drive(mount_value: str) -> None:
  mount_path = normalize_mount(mount_value)
  mounted, mounted_by_rclone, fs_type, _ = mount_info(mount_path)
  if not mounted:
    return
  if not mounted_by_rclone:
    raise RuntimeError(f"Refusing to unmount {mount_path}; it is mounted as {fs_type}, not rclone")

  fusermount = shutil.which("fusermount3") or shutil.which("fusermount")
  if not fusermount:
    raise RuntimeError("fusermount is not installed")
  code, stdout, stderr = run([fusermount, "-u", str(mount_path)], timeout=10)
  if code != 0:
    code, stdout, stderr = run([fusermount, "-uz", str(mount_path)], timeout=10)
  if code != 0:
    raise RuntimeError(clean_text(stderr or stdout or "Could not unmount Google Drive"))


def wait_to_close() -> None:
  if not sys.stdin.isatty():
    return
  try:
    input("\nPress Enter to close this terminal…")
  except (EOFError, KeyboardInterrupt):
    pass


def setup_drive(remote_value: str, install: bool) -> int:
  remote = normalize_remote(remote_value)
  rclone = shutil.which("rclone")

  if not rclone and install:
    print("Installing rclone and FUSE through Omarchy…\n", flush=True)
    result = subprocess.run(["omarchy", "pkg", "add", "rclone", "fuse3"], check=False)
    if result.returncode != 0:
      print("\nPackage installation failed.", file=sys.stderr)
      wait_to_close()
      return result.returncode
    rclone = shutil.which("rclone")

  if not rclone:
    print("rclone is not installed. Install it with: omarchy pkg add rclone fuse3", file=sys.stderr)
    wait_to_close()
    return 1

  remotes, config_error = configured_remotes(rclone)
  if config_error:
    print(config_error, file=sys.stderr)
    wait_to_close()
    return 1

  print("Google Drive connection setup", flush=True)
  print("Your OAuth token will be stored in rclone's normal user configuration.\n", flush=True)
  if remote in remotes:
    print(f"Reconnecting the existing '{remote}:' remote…\n", flush=True)
    command = [rclone, "config", "reconnect", f"{remote}:"]
  else:
    print(f"Creating the '{remote}:' Google Drive remote…", flush=True)
    print("A browser window should open for Google sign-in.\n", flush=True)
    command = [rclone, "config", "create", remote, "drive", "scope", "drive"]

  result = subprocess.run(command, check=False)
  if result.returncode == 0:
    print("\nGoogle Drive is connected. The Omarchy widget will detect it shortly.", flush=True)
  else:
    print("\nGoogle Drive setup did not complete.", file=sys.stderr, flush=True)
  wait_to_close()
  return result.returncode


def parser() -> argparse.ArgumentParser:
  result = argparse.ArgumentParser(description=__doc__)
  commands = result.add_subparsers(dest="command", required=True)

  status = commands.add_parser("status")
  status.add_argument("--remote", default="gdrive")
  status.add_argument("--mount", default="~/Google Drive")
  status.add_argument("--limit", type=int, default=25)

  mount = commands.add_parser("mount")
  mount.add_argument("--remote", default="gdrive")
  mount.add_argument("--mount", default="~/Google Drive")

  unmount = commands.add_parser("unmount")
  unmount.add_argument("--mount", default="~/Google Drive")

  search = commands.add_parser("search")
  search.add_argument("--mount", default="~/Google Drive")
  search.add_argument("--query", required=True)
  search.add_argument("--limit", type=int, default=50)

  setup = commands.add_parser("setup")
  setup.add_argument("--remote", default="gdrive")
  setup.add_argument("--install", action="store_true")
  return result


def main() -> int:
  args = parser().parse_args()
  try:
    if args.command == "status":
      limit = max(1, min(100, args.limit))
      print(json.dumps(status_payload(args.remote, args.mount, limit)))
    elif args.command == "mount":
      mount_drive(args.remote, args.mount)
    elif args.command == "unmount":
      unmount_drive(args.mount)
    elif args.command == "search":
      limit = max(1, min(100, args.limit))
      print(json.dumps(search_payload(args.mount, args.query, limit)))
    elif args.command == "setup":
      return setup_drive(args.remote, args.install)
  except (OSError, RuntimeError, ValueError) as error:
    if args.command in ("status", "search"):
      print(json.dumps({"ok": False, "lastError": clean_text(str(error)), "files": []}))
    else:
      print(clean_text(str(error)), file=sys.stderr)
      return 1
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
