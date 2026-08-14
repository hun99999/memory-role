#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
origin_url="$(git -C "${repo_root}" remote get-url origin)"
mapping_file="${repo_root}/.codex/basic-memory.json"

if [[ ! -f "${mapping_file}" ]]; then
  echo "FAIL: missing ${mapping_file}" >&2
  exit 1
fi

primary_project="$(python3 - "${mapping_file}" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text())
project = data.get("basicMemory", {}).get("primaryProject")
if not isinstance(project, str) or not project.strip():
    raise SystemExit("FAIL: basicMemory.primaryProject must be a non-empty string")
print(project)
PY
)"

project_json="$(basic-memory project list --json)"
python3 - "${primary_project}" "${project_json}" <<'PY'
import json
import sys

expected = sys.argv[1]
payload = json.loads(sys.argv[2])
names = {row.get("name") for row in payload.get("projects", [])}
if expected not in names:
    raise SystemExit(f"FAIL: Basic Memory project does not exist: {expected}")
PY

echo "PASS: repository=${origin_url}"
echo "PASS: basic-memory-project=${primary_project}"
