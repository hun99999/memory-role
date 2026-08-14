# memory-role repository rules

This public repository is the control plane for Hun's local Basic Memory setup. It is never a
canonical memory store.

- Keep personal notes, checkpoints, SQLite state, embeddings, caches, logs, credentials, and local
  payloads out of this Git tree.
- Treat `~/basic-memory` as canonical Markdown and `~/.basic-memory` as derived local state.
- Preserve the exact stable version in `versions.env`; verify a new stable release before updating.
- Keep Codex native Memories off while this repository documents Basic Memory as the sole
  cross-session memory layer.
- The reviewed user-level SessionStart/PreCompact hooks and the private Markdown backup remote are
  approved parts of this setup. Keep the Basic Memory plugin and cloud sync disabled.
- Keep automatic orientation to one search with at most 3 results and one exact read. Keep automatic
  checkpoints pointer-first and redacted; never copy full transcripts, diffs, source, or logs.
- Automatic Git backup may commit and push only allowlisted Markdown to the exact reviewed private
  remote. It must never pull, reset, clean, stash, rebase, force-push, or resolve conflicts.
- Validate changes with `scripts/verify-local.sh`. Use `scripts/check-repository-link.sh` when a code
  repository already has an explicit `.codex/basic-memory.json` mapping.
- Current user intent, repository rules/docs, Git/runtime/test evidence, and live provider state all
  outrank recalled Basic Memory notes.
