#!/bin/bash
set -euo pipefail

export LC_ALL=C

memory_root="${MEMORY_ROLE_BACKUP_ROOT:-${HOME}/basic-memory}"
expected_remote="${MEMORY_ROLE_BACKUP_REMOTE:-https://github.com/hun99999/basic-memory-data.git}"
state_root="${MEMORY_ROLE_BACKUP_STATE_ROOT:-${HOME}/.basic-memory}"
log_file="${state_root}/git-backup.log"
lock_dir="${state_root}/git-backup.lock"
force=false

if [[ "${1:-}" == "--force" ]]; then
  force=true
elif [[ $# -gt 0 ]]; then
  echo "usage: $0 [--force]" >&2
  exit 2
fi

mkdir -p "${state_root}"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >>"${log_file}"
}

if ! mkdir "${lock_dir}" 2>/dev/null; then
  log "SKIP backup already running or stale lock exists"
  exit 0
fi
trap 'rmdir "${lock_dir}" 2>/dev/null || true' EXIT INT TERM

case "${memory_root}" in
  /|"${HOME}"|"${HOME}/")
    log "FAIL unsafe memory root"
    exit 1
    ;;
esac

if [[ ! -d "${memory_root}" ]]; then
  log "FAIL memory root is missing"
  exit 1
fi

resolved_root="$(cd "${memory_root}" && pwd -P)"
git_root="$(git -C "${resolved_root}" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "${git_root}" || "${git_root}" != "${resolved_root}" ]]; then
  log "FAIL memory root is not the exact Git worktree root"
  exit 1
fi

branch="$(git -C "${resolved_root}" branch --show-current)"
if [[ "${branch}" != "main" ]]; then
  log "SKIP expected branch main, found ${branch:-detached}"
  exit 0
fi

origin="$(git -C "${resolved_root}" remote get-url origin 2>/dev/null || true)"
if [[ "${origin}" != "${expected_remote}" ]]; then
  log "FAIL origin does not match the reviewed private remote"
  exit 1
fi

git_dir="$(git -C "${resolved_root}" rev-parse --git-dir)"
for marker in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG rebase-merge rebase-apply; do
  if [[ -e "${resolved_root}/${git_dir}/${marker}" ]]; then
    log "SKIP Git operation in progress: ${marker}"
    exit 0
  fi
done

invalid_tracked=false
while IFS= read -r -d '' path; do
  if [[ "${path}" != ".gitignore" && "${path}" != *.md ]]; then
    invalid_tracked=true
    break
  fi
done < <(git -C "${resolved_root}" ls-files -z)
if [[ "${invalid_tracked}" == true ]]; then
  log "FAIL tracked file is outside the Markdown allowlist"
  exit 1
fi

if find "${resolved_root}" -type l -name '*.md' -not -path "${resolved_root}/.git/*" -print -quit | grep -q .; then
  log "FAIL Markdown symlink found; refusing automatic staging"
  exit 1
fi

if [[ "${force}" != true ]] && find "${resolved_root}" -type f -name '*.md' -not -path "${resolved_root}/.git/*" -mmin -1 -print -quit | grep -q .; then
  log "SKIP Markdown changed within the last 60 seconds"
  exit 0
fi

if ! git -C "${resolved_root}" diff --cached --quiet --; then
  log "SKIP pre-existing staged changes require manual review"
  exit 0
fi

git -C "${resolved_root}" add -u -- .
git -C "${resolved_root}" add -- .gitignore ':(glob)**/*.md'

invalid_staged=false
while IFS= read -r -d '' path; do
  if [[ "${path}" != ".gitignore" && "${path}" != *.md ]]; then
    invalid_staged=true
    break
  fi
done < <(git -C "${resolved_root}" diff --cached --name-only -z --diff-filter=ACMRTUXB)
if [[ "${invalid_staged}" == true ]]; then
  git -C "${resolved_root}" restore --staged -- .
  log "FAIL staged file is outside the Markdown allowlist"
  exit 1
fi

if git -C "${resolved_root}" diff --cached --quiet --; then
  log "OK no Markdown changes"
  exit 0
fi

if git -C "${resolved_root}" diff --cached --no-ext-diff --binary | grep -Eq '(^|[^A-Za-z0-9])(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-(proj-)?[A-Za-z0-9_-]{16,}|AKIA[A-Z0-9]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----)'; then
  git -C "${resolved_root}" restore --staged -- .
  log "FAIL potential secret signature detected; changes left unstaged"
  exit 1
fi

# Test repositories provide a remote override. The production path re-checks
# visibility immediately before every commit/push that contains new memory.
if [[ -z "${MEMORY_ROLE_BACKUP_REMOTE+x}" ]]; then
  gh_command="/opt/homebrew/bin/gh"
  if [[ ! -x "${gh_command}" ]]; then
    git -C "${resolved_root}" restore --staged -- .
    log "FAIL GitHub CLI is unavailable; changes left unstaged"
    exit 1
  fi
  is_private="$("${gh_command}" repo view hun99999/basic-memory-data --json isPrivate,visibility --jq '.isPrivate == true and .visibility == "PRIVATE"' 2>>"${log_file}" || true)"
  if [[ "${is_private}" != "true" ]]; then
    git -C "${resolved_root}" restore --staged -- .
    log "FAIL private visibility could not be verified; changes left unstaged"
    exit 1
  fi
fi

commit_message="chore(memory): backup $(TZ=Asia/Seoul date '+%Y-%m-%d %H:%M:%S KST')"
if ! git -C "${resolved_root}" commit -m "${commit_message}" >>"${log_file}" 2>&1; then
  log "FAIL commit failed; inspect local worktree"
  exit 1
fi

commit_sha="$(git -C "${resolved_root}" rev-parse --short=12 HEAD)"
if git -C "${resolved_root}" push origin main >>"${log_file}" 2>&1; then
  log "OK pushed ${commit_sha}"
else
  log "FAIL push failed; local commit ${commit_sha} preserved"
  exit 1
fi
