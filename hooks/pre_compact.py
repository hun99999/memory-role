#!/usr/bin/env python3
"""Write a small, pointer-first Basic Memory checkpoint before compaction."""

from __future__ import annotations

import json
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable

from basic_memory_hook import (
    BASIC_MEMORY_COMMAND,
    load_payload,
    log_event,
    memory_mapping,
    parse_json_output,
    payload_cwd,
    repository_context,
    run,
    safe_excerpt,
    slugify,
)


MAX_TRANSCRIPT_BYTES = 2_000_000
MAX_STATUS_LINES = 20


def content_text(value: Any) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return " ".join(filter(None, (content_text(item) for item in value)))
    if isinstance(value, dict):
        for key in ("text", "input_text", "output_text"):
            if isinstance(value.get(key), str):
                return value[key]
        if "content" in value:
            return content_text(value["content"])
    return ""


def message_pairs(value: Any) -> Iterable[tuple[str, str]]:
    if isinstance(value, dict):
        role = value.get("role")
        if role in {"user", "assistant"}:
            text = content_text(value.get("content", value.get("message", "")))
            if text:
                yield str(role), text
                return
        for nested in value.values():
            yield from message_pairs(nested)
    elif isinstance(value, list):
        for nested in value:
            yield from message_pairs(nested)


def transcript_messages(path_value: Any) -> list[tuple[str, str]]:
    if not isinstance(path_value, str) or not path_value:
        return []
    path = Path(path_value).expanduser()
    if not path.is_file():
        return []
    try:
        size = path.stat().st_size
        with path.open("rb") as handle:
            if size > MAX_TRANSCRIPT_BYTES:
                handle.seek(size - MAX_TRANSCRIPT_BYTES)
                handle.readline()
            raw = handle.read(MAX_TRANSCRIPT_BYTES)
    except OSError:
        return []

    messages: list[tuple[str, str]] = []
    for raw_line in raw.splitlines():
        try:
            item = json.loads(raw_line.decode("utf-8", errors="replace"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        for role, text in message_pairs(item):
            excerpt = safe_excerpt(text, 520)
            if excerpt and (not messages or messages[-1] != (role, excerpt)):
                messages.append((role, excerpt))
    return messages[-12:]


def git_status(root: Path | None) -> list[str]:
    if root is None:
        return []
    result = run(["git", "-C", str(root), "status", "--short"], timeout=5)
    if result.returncode != 0:
        return []
    return [safe_excerpt(line, 240) for line in result.stdout.splitlines()[:MAX_STATUS_LINES] if line.strip()]


def last_for_role(messages: list[tuple[str, str]], role: str) -> str:
    for message_role, text in reversed(messages):
        if message_role == role:
            return safe_excerpt(text, 520)
    return ""


def checkpoint_content(
    payload: dict[str, Any],
    context: dict[str, Any],
    messages: list[tuple[str, str]],
    status: list[str],
) -> str:
    latest_user = last_for_role(messages, "user") or "Continue the current task from live repository evidence."
    last_assistant = last_for_role(messages, "assistant") or "No concise assistant progress signal was recoverable."
    root = str(context["root"] or context["cwd"])
    remote = context.get("remote") or "none"
    session_id = safe_excerpt(payload.get("session_id", "unknown"), 80)
    trigger = safe_excerpt(payload.get("trigger", "unknown"), 40)
    status_block = "\n".join(f"- `{line}`" for line in status) if status else "- clean or unavailable"
    next_action = safe_excerpt(latest_user, 360)
    return f"""# Automatic Codex checkpoint

Generated before compaction. This is a pointer, not current authority and not a transcript.

## Evidence pointers
- Repository: `{root}`
- Origin: `{remote}`
- Branch / HEAD: `{context['branch']}` / `{context['head']}`
- Session / trigger: `{session_id}` / `{trigger}`

## Latest user intent (redacted excerpt)
{safe_excerpt(latest_user, 520)}

## Last progress signal (redacted excerpt)
{safe_excerpt(last_assistant, 520)}

## Working tree pointers
{status_block}

## Next action
{next_action}
"""


def checkpoint(payload: dict[str, Any], runner: Any = subprocess.run) -> str:
    cwd = payload_cwd(payload)
    context = repository_context(cwd)
    mapping = memory_mapping(context)
    messages = transcript_messages(payload.get("transcript_path"))
    status = git_status(context.get("root"))
    content = checkpoint_content(payload, context, messages, status)
    now = datetime.now().astimezone()
    session_short = slugify(str(payload.get("session_id", "session")))[:12]
    title = f"{context['slug']} checkpoint {now.strftime('%Y-%m-%d %H%M%S %Z')} {session_short}"
    folder = f"{mapping['capture_folder'].rstrip('/')}/{context['slug']}"
    result = run(
        [
            str(BASIC_MEMORY_COMMAND),
            "tool",
            "write-note",
            "--title",
            title,
            "--folder",
            folder,
            "--tags",
            f"codex,checkpoint,{context['slug']}",
            "--type",
            "checkpoint",
            "--project",
            mapping["project"],
            "--local",
        ],
        input_text=content,
        timeout=20,
        runner=runner,
    )
    output = parse_json_output(result)
    if result.returncode != 0:
        log_event("PreCompact", "write-failed", f"project={mapping['project']} repo={context['slug']}")
        return ""
    permalink = output.get("permalink") if isinstance(output.get("permalink"), str) else title
    log_event("PreCompact", "written", f"project={mapping['project']} permalink={permalink}")
    return str(permalink)


def main() -> int:
    try:
        checkpoint(load_payload())
    except Exception as exc:  # Hooks must fail open so compaction cannot be blocked.
        log_event("PreCompact", "error", type(exc).__name__)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
