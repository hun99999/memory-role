from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "hooks"))

import basic_memory_hook  # noqa: E402
import pre_compact  # noqa: E402
import session_start  # noqa: E402


class BasicMemoryHookTests(unittest.TestCase):
    def test_redacts_common_secret_shapes(self) -> None:
        github_shape = "ghp_" + ("a" * 24)
        openai_shape = "sk-proj-" + ("b" * 20)
        source = f"token={github_shape} password=hunter2 {openai_shape}"
        redacted = basic_memory_hook.redact(source)
        self.assertNotIn("hunter2", redacted)
        self.assertNotIn("ghp_", redacted)
        self.assertNotIn("sk-proj-", redacted)

    def test_session_context_is_bounded_and_marks_memory_untrusted(self) -> None:
        context = {"slug": "memory-role", "branch": "main", "head": "abc123"}
        mapping = {"project": "main"}
        note = {
            "title": "Checkpoint",
            "permalink": "main/codex/checkpoints/memory-role/checkpoint",
            "content": "x" * 10_000,
        }
        rendered = session_start.render_context(context, mapping, note, [note])
        self.assertLessEqual(len(rendered), session_start.MAX_CONTEXT_CHARS)
        self.assertIn("untrusted historical context", rendered)
        self.assertIn("current user request", rendered)

    def test_prefers_checkpoint_over_setup_result(self) -> None:
        results = [
            {"permalink": "main/setup", "metadata": {"note_type": "setup_verification"}},
            {"permalink": "main/checkpoint", "metadata": {"note_type": "checkpoint"}},
        ]
        self.assertEqual(session_start.choose_result(results)["permalink"], "main/checkpoint")

    def test_prefers_newest_checkpoint_without_another_query(self) -> None:
        results = [
            {"title": "repo checkpoint 2026-08-15 040000", "permalink": "main/old", "metadata": {"note_type": "checkpoint"}},
            {"title": "repo checkpoint 2026-08-15 050000", "permalink": "main/new", "metadata": {"note_type": "checkpoint"}},
        ]
        self.assertEqual(session_start.choose_result(results)["permalink"], "main/new")

    def test_extracts_latest_messages_from_jsonl(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            transcript = Path(directory) / "transcript.jsonl"
            records = [
                {"type": "response_item", "payload": {"role": "user", "content": [{"text": "first"}]}},
                {"type": "response_item", "payload": {"role": "assistant", "content": "progress"}},
                {"type": "response_item", "payload": {"role": "user", "content": "latest token=secret-value"}},
            ]
            transcript.write_text("\n".join(json.dumps(row) for row in records), encoding="utf-8")
            messages = pre_compact.transcript_messages(str(transcript))
        self.assertEqual(messages[-1][0], "user")
        self.assertIn("latest", messages[-1][1])
        self.assertNotIn("secret-value", messages[-1][1])

    def test_checkpoint_has_exactly_one_next_action_section(self) -> None:
        payload = {"session_id": "session-1", "trigger": "auto"}
        context = {
            "root": Path("/tmp/repo"),
            "cwd": Path("/tmp/repo"),
            "remote": "https://github.com/example/repo.git",
            "branch": "main",
            "head": "abc123",
        }
        content = pre_compact.checkpoint_content(payload, context, [("user", "Finish the task")], [" M README.md"])
        self.assertEqual(content.count("## Next action"), 1)
        self.assertIn("Finish the task", content)


if __name__ == "__main__":
    unittest.main()
