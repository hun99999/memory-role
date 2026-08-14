#!/bin/bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
backup_script="${repo_root}/scripts/backup-memory.sh"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/memory-role-backup-test.XXXXXX")"
memory_root="${test_root}/memory"
remote_root="${test_root}/remote.git"
state_root="${test_root}/state"

cleanup() {
  rm -rf "${test_root}"
}
trap cleanup EXIT INT TERM

git init --bare -b main "${remote_root}" >/dev/null
git init -b main "${memory_root}" >/dev/null
git -C "${memory_root}" config user.name "memory-role test"
git -C "${memory_root}" config user.email "memory-role-test@example.invalid"

printf '%s\n' '*' '!*/' '!*.md' '!.gitignore' >"${memory_root}/.gitignore"
mkdir -p "${memory_root}/notes"
printf '%s\n' '# Initial memory' >"${memory_root}/notes/note.md"
git -C "${memory_root}" add -- .gitignore notes/note.md
git -C "${memory_root}" commit -m initial >/dev/null
git -C "${memory_root}" remote add origin "${remote_root}"
git -C "${memory_root}" push -u origin main >/dev/null

MEMORY_ROLE_BACKUP_ROOT="${memory_root}" \
MEMORY_ROLE_BACKUP_REMOTE="${remote_root}" \
MEMORY_ROLE_BACKUP_STATE_ROOT="${state_root}" \
  "${backup_script}" --force
grep -Fq 'OK no Markdown changes' "${state_root}/git-backup.log"

printf '%s\n' '# Changed memory' >"${memory_root}/notes/note.md"
MEMORY_ROLE_BACKUP_ROOT="${memory_root}" \
MEMORY_ROLE_BACKUP_REMOTE="${remote_root}" \
MEMORY_ROLE_BACKUP_STATE_ROOT="${state_root}" \
  "${backup_script}" --force

local_sha="$(git -C "${memory_root}" rev-parse HEAD)"
remote_sha="$(git -C "${memory_root}" ls-remote --heads origin main | awk '{print $1}')"
if [[ "${local_sha}" != "${remote_sha}" ]]; then
  echo "FAIL: successful backup did not reach the remote" >&2
  exit 1
fi

missing_remote="${test_root}/missing.git"
git -C "${memory_root}" remote set-url origin "${missing_remote}"
printf '%s\n' '# Locally preserved after push failure' >"${memory_root}/notes/note.md"
before_count="$(git -C "${memory_root}" rev-list --count HEAD)"
if MEMORY_ROLE_BACKUP_ROOT="${memory_root}" \
  MEMORY_ROLE_BACKUP_REMOTE="${missing_remote}" \
  MEMORY_ROLE_BACKUP_STATE_ROOT="${state_root}" \
  "${backup_script}" --force; then
  echo "FAIL: push failure unexpectedly returned success" >&2
  exit 1
fi
after_count="$(git -C "${memory_root}" rev-list --count HEAD)"

if [[ "${after_count}" -ne $((before_count + 1)) ]]; then
  echo "FAIL: failed push did not preserve exactly one local commit" >&2
  exit 1
fi
if ! git -C "${memory_root}" diff --quiet -- || ! git -C "${memory_root}" diff --cached --quiet --; then
  echo "FAIL: failed push did not preserve a clean committed worktree" >&2
  exit 1
fi
grep -Fq 'FAIL push failed; local commit' "${state_root}/git-backup.log"

echo "PASS: backup no-change, push, and failed-push local preservation"
