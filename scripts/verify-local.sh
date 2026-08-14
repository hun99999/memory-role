#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/versions.env"
expected_version="${BASIC_MEMORY_VERSION}"
setup_permalink="main/codex/setup/basic-memory-setup-verification-2026-08-15"

for command_name in codex basic-memory bm uv python3 git; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "FAIL: missing command: ${command_name}" >&2
    exit 1
  fi
done

if ! basic-memory --version | grep -Fq "${expected_version}"; then
  echo "FAIL: Basic Memory version is not ${expected_version}" >&2
  exit 1
fi

python3 - "${expected_version}" <<'PY'
import json
import shutil
import stat
import sys
import tomllib
from pathlib import Path

expected_version = sys.argv[1]
home = Path.home()
codex_path = home / ".codex" / "config.toml"
bm_path = home / ".basic-memory" / "config.json"
canonical_path = home / "basic-memory"

codex = tomllib.loads(codex_path.read_text())
server = codex.get("mcp_servers", {}).get("basic-memory")
if not isinstance(server, dict):
    raise SystemExit("FAIL: basic-memory MCP is not configured")
if server.get("args") != ["mcp"]:
    raise SystemExit("FAIL: basic-memory MCP args differ from ['mcp']")
resolved_command = Path(server.get("command", "")).resolve()
path_command = shutil.which("basic-memory")
if path_command is None or resolved_command != Path(path_command).resolve():
    raise SystemExit("FAIL: basic-memory MCP command differs from the installed executable")
expected_tools = {
    "search_notes",
    "read_note",
    "write_note",
    "edit_note",
    "list_directory",
    "list_memory_projects",
}
if set(server.get("enabled_tools", [])) != expected_tools:
    raise SystemExit("FAIL: basic-memory MCP enabled_tools differs from the reviewed allowlist")
if codex.get("features", {}).get("memories") is not False:
    raise SystemExit("FAIL: Codex native Memories feature is not disabled")
memory_settings = codex.get("memories", {})
if memory_settings.get("generate_memories") is not False or memory_settings.get("use_memories") is not False:
    raise SystemExit("FAIL: Codex native memory generation/use is not disabled")

bm = json.loads(bm_path.read_text())
if bm.get("default_project") != "main":
    raise SystemExit("FAIL: Basic Memory default project is not main")
if bm.get("auto_update") is not False:
    raise SystemExit("FAIL: Basic Memory auto_update must be false for an exact version pin")
main = bm.get("projects", {}).get("main", {})
if Path(main.get("path", "")).resolve() != canonical_path.resolve():
    raise SystemExit("FAIL: main project canonical path differs from ~/basic-memory")
if not (home / ".basic-memory" / "memory.db").is_file():
    raise SystemExit("FAIL: derived SQLite database is missing")
if stat.S_IMODE(bm_path.stat().st_mode) != 0o600:
    raise SystemExit("FAIL: ~/.basic-memory/config.json permissions are not 0600")
if stat.S_IMODE(bm_path.parent.stat().st_mode) != 0o700:
    raise SystemExit("FAIL: ~/.basic-memory directory permissions are not 0700")
PY

mcp_count="$(codex mcp list 2>/dev/null | awk '/^basic-memory[[:space:]]/ {count++} END {print count+0}')"
if [[ "${mcp_count}" -ne 1 ]]; then
  echo "FAIL: expected one basic-memory MCP entry, found ${mcp_count}" >&2
  exit 1
fi

basic-memory status --project main --wait --timeout 60 --json >/dev/null
note_body="$(basic-memory tool read-note "${setup_permalink}" --project main --local)"
if [[ "${note_body}" != *"Basic Memory 0.22.1"* ]]; then
  echo "FAIL: setup verification note could not be read" >&2
  exit 1
fi

if find "${HOME}/basic-memory" -type f \( -name '*.db' -o -name '*.sqlite' -o -name '*-wal' -o -name '*-shm' -o -name '*.log' \) | grep -q .; then
  echo "FAIL: derived state found in canonical Markdown root" >&2
  exit 1
fi

if git -C "${repo_root}" ls-files | grep -E '(\.db($|-)|\.sqlite($|-)|\.wal$|\.shm$|\.log$)' >/dev/null; then
  echo "FAIL: runtime state is tracked by Git" >&2
  exit 1
fi

echo "PASS: Basic Memory ${expected_version}, canonical/derived separation, MCP allowlist, persistence note"
