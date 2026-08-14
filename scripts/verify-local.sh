#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source "${repo_root}/versions.env"
expected_version="${BASIC_MEMORY_VERSION}"
setup_permalink="main/codex/setup/basic-memory-setup-verification-2026-08-15"

for command_name in codex basic-memory bm uv python3 git gh launchctl plutil; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "FAIL: missing command: ${command_name}" >&2
    exit 1
  fi
done

if ! basic-memory --version | grep -Fq "${expected_version}"; then
  echo "FAIL: Basic Memory version is not ${expected_version}" >&2
  exit 1
fi

python3 - "${expected_version}" "${repo_root}" <<'PY'
import json
import plistlib
import shutil
import stat
import sys
import tomllib
from pathlib import Path

expected_version = sys.argv[1]
repo_root = Path(sys.argv[2]).resolve()
home = Path.home()
codex_path = home / ".codex" / "config.toml"
hooks_path = home / ".codex" / "hooks.json"
agents_path = home / ".codex" / "AGENTS.md"
bm_path = home / ".basic-memory" / "config.json"
canonical_path = home / "basic-memory"
launch_agent_path = home / "Library" / "LaunchAgents" / "com.hun.memory-role.basic-memory-backup.plist"

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
if codex.get("features", {}).get("hooks") is not True:
    raise SystemExit("FAIL: Codex hooks feature is not enabled")
memory_settings = codex.get("memories", {})
if memory_settings.get("generate_memories") is not False or memory_settings.get("use_memories") is not False:
    raise SystemExit("FAIL: Codex native memory generation/use is not disabled")

actual_hooks = json.loads(hooks_path.read_text())
expected_hooks = json.loads((repo_root / "config" / "hooks.json.example").read_text())
if actual_hooks != expected_hooks:
    raise SystemExit("FAIL: ~/.codex/hooks.json differs from the reviewed repository copy")
agents_snippet = (repo_root / "config" / "global-agents-basic-memory.md").read_text().strip()
if agents_snippet not in agents_path.read_text():
    raise SystemExit("FAIL: global AGENTS.md is missing the reviewed automatic Basic Memory rules")
hook_state = codex.get("hooks", {}).get("state", {})
for hook_name in ("session_start", "pre_compact"):
    key = f"{hooks_path}:{hook_name}:0:0"
    trusted_hash = hook_state.get(key, {}).get("trusted_hash", "")
    if not isinstance(trusted_hash, str) or not trusted_hash.startswith("sha256:"):
        raise SystemExit(f"FAIL: hook is not persistently trusted: {hook_name}")

actual_plist = plistlib.loads(launch_agent_path.read_bytes())
expected_plist = plistlib.loads((repo_root / "config" / launch_agent_path.name).read_bytes())
if actual_plist != expected_plist:
    raise SystemExit("FAIL: installed LaunchAgent differs from the reviewed repository copy")
if actual_plist.get("StartInterval") != 900 or actual_plist.get("RunAtLoad") is not True:
    raise SystemExit("FAIL: LaunchAgent is not configured for 15-minute backup")

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

canonical_root="$(git -C "${HOME}/basic-memory" rev-parse --show-toplevel)"
if [[ "${canonical_root}" != "${HOME}/basic-memory" ]]; then
  echo "FAIL: ~/basic-memory is not the exact Git worktree root" >&2
  exit 1
fi
if [[ "$(git -C "${canonical_root}" branch --show-current)" != "main" ]]; then
  echo "FAIL: canonical memory backup is not on main" >&2
  exit 1
fi
if [[ "$(git -C "${canonical_root}" remote get-url origin)" != "https://github.com/hun99999/basic-memory-data.git" ]]; then
  echo "FAIL: canonical memory origin differs from the reviewed private remote" >&2
  exit 1
fi
if git -C "${canonical_root}" ls-files | grep -Ev '(^\.gitignore$|\.md$)' >/dev/null; then
  echo "FAIL: canonical memory Git tracks a non-Markdown payload" >&2
  exit 1
fi

repo_json="$(gh repo view hun99999/basic-memory-data --json isPrivate,visibility,defaultBranchRef)"
python3 - "${repo_json}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
if payload.get("isPrivate") is not True or payload.get("visibility") != "PRIVATE":
    raise SystemExit("FAIL: basic-memory-data is not private")
if payload.get("defaultBranchRef", {}).get("name") != "main":
    raise SystemExit("FAIL: basic-memory-data default branch is not main")
PY

launchctl print "gui/$(id -u)/com.hun.memory-role.basic-memory-backup" >/dev/null

hook_output="$(printf '%s\n' "{\"session_id\":\"verify-local\",\"cwd\":\"${repo_root}\",\"hook_event_name\":\"SessionStart\",\"source\":\"startup\"}" | /usr/bin/python3 -B "${repo_root}/hooks/session_start.py")"
python3 - "${hook_output}" <<'PY'
import json
import sys

payload = json.loads(sys.argv[1])
context = payload.get("hookSpecificOutput", {}).get("additionalContext", "")
if not context or len(context) > 3200:
    raise SystemExit("FAIL: SessionStart did not return bounded Basic Memory context")
if "repo=memory-role" not in context or "selected=main/" not in context:
    raise SystemExit("FAIL: SessionStart context is not repository-scoped")
PY

"${repo_root}/scripts/backup-memory.sh" --force

echo "PASS: Basic Memory ${expected_version}, bounded trusted hooks, private Markdown backup, 15-minute LaunchAgent"
