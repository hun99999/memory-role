#!/usr/bin/env python3
"""Shared, dependency-free helpers for the Basic Memory lifecycle hooks."""

from __future__ import annotations

import json
import os
import re
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urlsplit, urlunsplit


HOME = Path.home()
BASIC_MEMORY_COMMAND = HOME / ".local" / "bin" / "basic-memory"
EVENT_LOG = HOME / ".basic-memory" / "hook-events.jsonl"
DEFAULT_PROJECT = "main"
DEFAULT_CAPTURE_FOLDER = "codex/checkpoints"

Runner = Callable[..., subprocess.CompletedProcess[str]]


def load_payload() -> dict[str, Any]:
    try:
        payload = json.load(sys_stdin())
    except (json.JSONDecodeError, OSError, TypeError, ValueError):
        return {}
    return payload if isinstance(payload, dict) else {}


def sys_stdin() -> Any:
    # Kept behind a function so pure helpers remain easy to test.
    import sys

    return sys.stdin


def log_event(event: str, status: str, detail: str = "") -> None:
    try:
        EVENT_LOG.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        record = {
            "timestamp": datetime.now().astimezone().isoformat(timespec="seconds"),
            "event": safe_excerpt(event, 80),
            "status": safe_excerpt(status, 80),
        }
        if detail:
            record["detail"] = safe_excerpt(detail, 400)
        with EVENT_LOG.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
    except OSError:
        pass


def run(
    args: list[str],
    *,
    cwd: Path | None = None,
    input_text: str | None = None,
    timeout: int = 12,
    runner: Runner = subprocess.run,
) -> subprocess.CompletedProcess[str]:
    return runner(
        args,
        cwd=str(cwd) if cwd else None,
        input=input_text,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )


def command_output(args: list[str], cwd: Path | None = None, timeout: int = 5) -> str:
    try:
        result = run(args, cwd=cwd, timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return ""
    return result.stdout.strip() if result.returncode == 0 else ""


def payload_cwd(payload: dict[str, Any]) -> Path:
    value = payload.get("cwd")
    if isinstance(value, str) and value:
        candidate = Path(value).expanduser()
        if candidate.is_dir():
            return candidate.resolve()
    return Path.cwd().resolve()


def git_root(cwd: Path) -> Path | None:
    output = command_output(["git", "-C", str(cwd), "rev-parse", "--show-toplevel"])
    if not output:
        return None
    candidate = Path(output)
    return candidate.resolve() if candidate.is_dir() else None


def safe_remote(remote: str) -> str:
    remote = remote.strip()
    if not remote:
        return ""
    if "://" not in remote:
        return remote
    try:
        parsed = urlsplit(remote)
        hostname = parsed.hostname or ""
        if parsed.port:
            hostname = f"{hostname}:{parsed.port}"
        return urlunsplit((parsed.scheme, hostname, parsed.path, parsed.query, parsed.fragment))
    except ValueError:
        return ""


def repository_slug(root: Path | None, remote: str) -> str:
    candidate = ""
    cleaned = safe_remote(remote)
    if cleaned:
        path = cleaned
        if cleaned.startswith("git@") and ":" in cleaned:
            path = cleaned.split(":", 1)[1]
        else:
            path = urlsplit(cleaned).path if "://" in cleaned else cleaned
        candidate = path.rstrip("/").rsplit("/", 1)[-1]
        if candidate.endswith(".git"):
            candidate = candidate[:-4]
    if not candidate and root:
        candidate = root.name
    return slugify(candidate or "workspace")


def slugify(value: str) -> str:
    slug = re.sub(r"[^A-Za-z0-9._-]+", "-", value.strip()).strip("-._").lower()
    return slug[:80] or "workspace"


def repository_context(cwd: Path) -> dict[str, Any]:
    root = git_root(cwd)
    git_cwd = root or cwd
    remote = command_output(["git", "-C", str(git_cwd), "remote", "get-url", "origin"]) if root else ""
    branch = command_output(["git", "-C", str(git_cwd), "branch", "--show-current"]) if root else ""
    head = command_output(["git", "-C", str(git_cwd), "rev-parse", "--short=12", "HEAD"]) if root else ""
    return {
        "cwd": cwd,
        "root": root,
        "remote": safe_remote(remote),
        "branch": branch or "detached-or-none",
        "head": head or "none",
        "slug": repository_slug(root, remote),
    }


def memory_mapping(context: dict[str, Any]) -> dict[str, str]:
    candidates: list[Path] = []
    root = context.get("root")
    if isinstance(root, Path):
        candidates.append(root / ".codex" / "basic-memory.json")
    cwd = context.get("cwd")
    if isinstance(cwd, Path):
        local_candidate = cwd / ".codex" / "basic-memory.json"
        if local_candidate not in candidates:
            candidates.append(local_candidate)
    candidates.append(HOME / ".codex" / "basic-memory.json")

    mapping: dict[str, str] = {
        "project": DEFAULT_PROJECT,
        "capture_folder": DEFAULT_CAPTURE_FOLDER,
        "focus": "",
        "source": "default",
    }
    for path in candidates:
        if not path.is_file():
            continue
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
            config = payload.get("basicMemory", {})
        except (OSError, json.JSONDecodeError, AttributeError):
            continue
        if not isinstance(config, dict):
            continue
        project = config.get("primaryProject")
        capture_folder = config.get("captureFolder")
        focus = config.get("focus")
        if isinstance(project, str) and project.strip():
            mapping["project"] = project.strip()
        if isinstance(capture_folder, str) and capture_folder.strip():
            mapping["capture_folder"] = capture_folder.strip().strip("/")
        if isinstance(focus, str):
            mapping["focus"] = safe_excerpt(focus, 160)
        mapping["source"] = str(path)
        break
    return mapping


SECRET_PATTERNS = (
    (re.compile(r"(?i)\b(bearer)\s+[A-Za-z0-9._~+/=-]{12,}"), r"\1 [REDACTED]"),
    (re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"), "[REDACTED_GITHUB_TOKEN]"),
    (re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9_-]{16,}\b"), "[REDACTED_API_KEY]"),
    (re.compile(r"\bAKIA[A-Z0-9]{16}\b"), "[REDACTED_AWS_KEY]"),
    (
        re.compile(r"(?i)\b(api[_-]?key|access[_-]?token|token|password|passwd|secret)\s*[:=]\s*([^\s,;]+)"),
        r"\1=[REDACTED]",
    ),
    (re.compile(r"(?i)(https?://)[^/@\s:]+:[^/@\s]+@"), r"\1[REDACTED]@"),
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"), "[REDACTED_PRIVATE_KEY]"),
)


def redact(text: str) -> str:
    value = text
    for pattern, replacement in SECRET_PATTERNS:
        value = pattern.sub(replacement, value)
    return value


def safe_excerpt(value: Any, limit: int) -> str:
    if not isinstance(value, str):
        return ""
    compact = re.sub(r"\s+", " ", redact(value)).strip()
    if len(compact) <= limit:
        return compact
    return compact[: max(0, limit - 1)].rstrip() + "…"


def parse_json_output(result: subprocess.CompletedProcess[str]) -> dict[str, Any]:
    if result.returncode != 0:
        return {}
    try:
        payload = json.loads(result.stdout)
    except (json.JSONDecodeError, TypeError):
        return {}
    return payload if isinstance(payload, dict) else {}
