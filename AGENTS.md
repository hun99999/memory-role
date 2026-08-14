# memory-role repository rules

This public repository is the control plane for Hun's local Basic Memory setup. It is never a
canonical memory store.

- Keep personal notes, checkpoints, SQLite state, embeddings, caches, logs, credentials, and local
  payloads out of this Git tree.
- Treat `~/basic-memory` as canonical Markdown and `~/.basic-memory` as derived local state.
- Preserve the exact stable version in `versions.env`; verify a new stable release before updating.
- Keep Codex native Memories off while this repository documents Basic Memory as the sole
  cross-session memory layer.
- Do not install the Basic Memory Codex plugin, trust hooks, enable cloud sync, or create a private
  memory-data remote without Hun's explicit approval.
- Validate changes with `scripts/verify-local.sh`. Use `scripts/check-repository-link.sh` when a code
  repository already has an explicit `.codex/basic-memory.json` mapping.
- Current user intent, repository rules/docs, Git/runtime/test evidence, and live provider state all
  outrank recalled Basic Memory notes.
