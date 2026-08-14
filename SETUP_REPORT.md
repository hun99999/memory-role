# Basic Memory setup report

## 조사 기준

- 시각: 2026-08-15 04:03 KST (`Asia/Seoul`)
- workspace: `~/memory-role`
- 최종 자동화 전환: 2026-08-15 04:39 KST
- 목적: 공개 운영 저장소와 private memory data를 분리하고, Codex가 별도 요청 없이 회상·기록·백업하는 장기 기억 계층

## 환경과 버전

| 항목 | 확인값 |
| --- | --- |
| macOS | 15.7.3 (24G419) |
| architecture | Apple Silicon `arm64` |
| shell | `/bin/zsh` |
| Homebrew | 6.0.13 |
| Python | 3.14.5 |
| Git | 2.50.0 |
| GitHub CLI | 2.74.2, active account `hun99999` |
| Codex | 0.144.4, npm installation |
| uv | 0.12.4, Homebrew |
| Basic Memory | 0.22.1, `uv tool` |

Codex 0.147.0이 조사 시점에 available이었지만, Basic Memory 설치에 필요하지 않고 Codex 자체 upgrade는 이 작업 범위가 아니므로 변경하지 않았습니다.

## 선택한 release

- stable tag: `v0.22.1`
- release commit: `232f4690656d7c93f39fc0cb13b0826243f2e0da`
- published: 2026-06-13 03:35:06 UTC
- PyPI artifact/package: `basic-memory==0.22.1`
- 공식 tag checkout의 HEAD와 release commit이 일치함을 확인했습니다.

## architecture 결정

- standalone local stdio MCP를 user-level Codex config에 등록했습니다.
- 공식 stable plugin은 설치하지 않았습니다. plugin의 넓은 자동 brief 대신 이 저장소의 stdlib-only hook 2개만 검토·신뢰했습니다.
- SessionStart는 repository slug 검색 1회, 최대 3결과, 최신 checkpoint/decision exact read 1회로 고정했습니다. 실제 문자열 한도는 3,200자이고 Codex `additionalContextLimit`는 1,200 token입니다.
- PreCompact는 transcript tail을 최대 2MB까지만 best-effort로 읽고 redacted excerpt, Git pointer, 다음 action 하나만 checkpoint에 씁니다. hook 오류는 Codex task/compaction을 막지 않게 fail-open 처리합니다.
- Codex global rule은 의미 있는 결정·구현·검증 변화가 있을 때만 별도 요청 없이 durable note 하나를 남기며 trivial/duplicate/sensitive state는 건너뜁니다.
- Basic Memory cloud와 다른 memory 도구는 사용하지 않습니다. canonical Markdown만 private GitHub repository에 백업합니다.

## 경로와 데이터

| 역할 | 경로 |
| --- | --- |
| 공개 운영 workspace | `~/memory-role` |
| canonical Markdown | `~/basic-memory` |
| Basic Memory config/DB/cache/log | `~/.basic-memory` |
| Basic Memory CLI | `~/.local/bin/basic-memory` |
| Codex user config | `~/.codex/config.toml` |
| Codex global instructions | `~/.codex/AGENTS.md` |
| Codex lifecycle hooks | `~/.codex/hooks.json` |
| backup LaunchAgent | `~/Library/LaunchAgents/com.hun.memory-role.basic-memory-backup.plist` |
| private canonical backup | `https://github.com/hun99999/basic-memory-data` |

Basic Memory project는 `main` 하나만 만들었고 `~/basic-memory`를 default canonical path로 사용합니다. WIPI-X, DBelto, RetroBook 등은 실제 repository identity와 분리 필요가 확인되기 전까지 빈 project를 만들지 않았습니다.

`~/basic-memory`에는 Markdown note만 있고, SQLite·cache·log는 `~/.basic-memory`에 분리되어 있음을 확인했습니다. Basic Memory config는 `0600`, config directory는 `0700`입니다.

## 설정 backup

- `~/.codex/config.toml.backup-20260815T040019+0900`
- `~/.codex/AGENTS.md.backup-20260815T040019+0900`
- `~/.basic-memory/config.json.backup-20260815T041159+0900`
- `~/.codex/config.toml.backup-20260815T043559+0900`

기존 파일 전체를 덮어쓰지 않고 Basic Memory 관련 항목과 짧은 운영 규칙만 추가했습니다.

## Codex 연결

- MCP id: `basic-memory`
- command: `~/.local/bin/basic-memory mcp`
- startup timeout: 30초
- enabled tools: `search_notes`, `read_note`, `write_note`, `edit_note`, `list_directory`, `list_memory_projects`
- 중복 등록: 없음, 정확히 1개
- Codex native Memories: feature/use/generation 모두 `false`; 기존 memory data는 보존
- Codex hooks feature: `true`
- trusted commands: `/usr/bin/python3 -B ~/memory-role/hooks/session_start.py`, `/usr/bin/python3 -B ~/memory-role/hooks/pre_compact.py`의 absolute-path 명령
- `~/.codex/basic-memory.json`: 생성하지 않음. 공식 plugin을 설치하지 않았으므로 dead user-level plugin config를 만들지 않았습니다.
- Basic Memory `auto_update`: `false`; exact package pin은 수동 upgrade 때만 변경

## Plugin / Hook

- Basic Memory Codex plugin: 미설치
- custom SessionStart/PreCompact hook: 설치, TUI review 후 persistent trust hash 기록
- SessionStart direct invocation: repository-scoped exact note와 3,200자 이하 context 반환
- PreCompact direct invocation: actual Basic Memory checkpoint 생성, frontmatter type/tag/permalink와 다음 action 1개 확인
- current task보다 새로 열린 Codex task부터 자동 hook discovery가 적용됨

## Git

- `memory-role` workspace는 조사 시작 시 Git repository가 아니었고 파일도 없었습니다.
- local branch: `main`
- remote: `https://github.com/hun99999/memory-role.git`
- GitHub visibility: `PUBLIC`으로 API 재확인
- 공개 repository에는 운영 자산만 포함합니다.
- canonical Markdown Git root: `~/basic-memory`, branch `main`
- private remote: `hun99999/basic-memory-data`, GitHub API에서 `PRIVATE` 재확인
- initial push와 automatic checkpoint push에서 local/remote SHA 일치 확인
- LaunchAgent: `com.hun.memory-role.basic-memory-backup`, `RunAtLoad=true`, `StartInterval=900`, last exit `0`
- automatic backup은 Markdown allowlist만 stage하고 변경이 있을 때마다 remote `PRIVATE` visibility를 재검증하며 pull/reset/clean/stash/rebase/force/conflict resolution을 하지 않음

## 검증 결과

### PASS

- Basic Memory CLI exact version `0.22.1`
- release tag, commit SHA, installed package version 일치
- `main` project와 canonical path 확인
- setup verification note 작성:
  - `main/codex/setup/basic-memory-setup-verification-2026-08-15`
- 별도 MCP process에서 title search 결과 제한 3과 exact permalink read 성공
- MCP process 종료 후 새 process로 재시작하고 동일 search/read 성공
- fresh ephemeral Codex CLI task가 Basic Memory MCP의 두 도구만 사용해 `BASIC_MEMORY_CODEX_E2E_PASS` 반환
- `basic-memory doctor`의 API write, filesystem sync, search, clean status 모두 통과
- Codex config strict parse와 Basic Memory MCP 단일 등록 확인
- Basic Memory background auto-update 비활성화 확인
- native Memories 비활성화 확인
- 공식 plugin 미설치, custom hook exact config와 persistent trust 확인
- hook unit test: redaction, context bound, checkpoint preference, JSONL extraction, next-action contract 통과
- backup integration test: no-change, successful push, failed-push local commit preservation 통과
- private repository visibility `PRIVATE`, default branch `main`, local/remote SHA 일치
- LaunchAgent loaded, 900초 interval, RunAtLoad execution exit `0`, stderr 없음
- fresh natural Codex E2E: hook trust 우회 없이 새 ephemeral task를 시작하고 tool call을 금지했을 때 `/Users/hooooonje/basic-memory`, `900초`를 정확히 응답
- E2E 전후 hook event count `6 -> 7`, 선택 permalink `main/codex/checkpoints/memory-role/memory-role-checkpoint-2026-08-15-044600-kst-automatic-memory-ready`
- canonical Markdown과 SQLite/cache/log 분리 확인
- secret/runtime file이 공개 Git staging 대상이 되지 않도록 ignore/검증 규칙 추가
- GitHub `hun99999/memory-role` remote 생성과 `PUBLIC` visibility 확인

### FAIL

- 없음

### PENDING

- 없음

## 토큰 효율 증거

- SessionStart는 search 1회(`page-size=3`)와 exact read 1회만 사용하고 같은 task에서 재검색하지 않도록 context에 명시합니다.
- 실제 E2E가 선택한 checkpoint context는 2,100자였으며 hard limit 3,200자 이내였습니다. Codex 자체 `additionalContextLimit=1200`도 적용됩니다.
- 관련 note가 없으면 context를 출력하지 않습니다.
- PreCompact는 전체 transcript/content graph를 주입하지 않고 최대 2MB tail의 짧은 excerpt만 checkpoint 작성에 사용합니다.
- 15분 Git backup은 Codex token을 사용하지 않는 local shell/launchd 작업입니다.
- fresh E2E 전체 입력은 18,095 tokens, 출력은 28 tokens였습니다. 전체 입력은 global instructions와 설치된 skill/plugin catalog를 포함하며, Basic Memory hook 자체 주입은 위 2,100자입니다.

## 알려진 제한

- standalone MCP에서는 `.codex/basic-memory.json`을 Basic Memory가 자동 소비하지 않습니다. global `AGENTS.md`가 repository routing contract로 사용합니다.
- 현재 `main`은 소규모 공통 기억용입니다. 데이터가 커지거나 repository 간 접근 경계가 필요해질 때만 별도 project를 추가해야 합니다.
- hook의 repository routing은 explicit `.codex/basic-memory.json` 또는 fallback `main`에 의존합니다. mapping 없는 저장소는 `main`에서 repository slug만 검색합니다.
- 현재 열려 있던 Codex task는 새 hook을 다시 읽지 않을 수 있으며 새 task부터 보장됩니다.
- transcript JSONL 형식은 안정 API가 아니므로 PreCompact extraction은 best-effort입니다. 실패해도 Git pointer checkpoint 또는 fail-open으로 Codex를 계속 사용합니다.
- GitHub가 unavailable하거나 remote가 diverge하면 push를 강제로 고치지 않습니다. local commit과 로그를 보존하고 사람이 확인해야 합니다.
- semantic model cache는 파생 상태이며 삭제 시 다시 다운로드됩니다.

## Rollback

1. `codex mcp remove basic-memory`
2. 필요하면 timestamp backup에서 `~/.codex/config.toml`과 `~/.codex/AGENTS.md` 복원
3. package 제거가 필요하면 `uv tool uninstall basic-memory`
4. canonical Markdown과 `~/.basic-memory`는 별도 삭제 승인이 없으면 보존

## 남은 정확한 한 가지 조치

- 없음
