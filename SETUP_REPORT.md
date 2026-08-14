# Basic Memory setup report

## 조사 기준

- 시각: 2026-08-15 04:03 KST (`Asia/Seoul`)
- workspace: `~/memory-role`
- 목적: 공개 운영 저장소와 private local memory data를 분리한 Codex 장기 기억 계층

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
- 공식 stable에 Codex plugin이 포함되고 현재 Codex도 plugin/hook을 지원하지만 plugin은 설치하지 않았습니다.
- 검토한 plugin hook은 SessionStart에서 여러 search를 병렬 실행해 자동 brief를 주입하고, PreCompact에서 transcript와 Git status를 읽어 자동 checkpoint를 생성합니다.
- token overhead와 third-party hook trust를 피하기 위해 수동 orientation/checkpoint를 선택했습니다.
- Basic Memory cloud, 다른 memory 도구, lifecycle hook, 자동 Git backup은 사용하지 않습니다.

## 경로와 데이터

| 역할 | 경로 |
| --- | --- |
| 공개 운영 workspace | `~/memory-role` |
| canonical Markdown | `~/basic-memory` |
| Basic Memory config/DB/cache/log | `~/.basic-memory` |
| Basic Memory CLI | `~/.local/bin/basic-memory` |
| Codex user config | `~/.codex/config.toml` |
| Codex global instructions | `~/.codex/AGENTS.md` |

Basic Memory project는 `main` 하나만 만들었고 `~/basic-memory`를 default canonical path로 사용합니다. WIPI-X, DBelto, RetroBook 등은 실제 repository identity와 분리 필요가 확인되기 전까지 빈 project를 만들지 않았습니다.

`~/basic-memory`에는 Markdown note만 있고, SQLite·cache·log는 `~/.basic-memory`에 분리되어 있음을 확인했습니다. Basic Memory config는 `0600`, config directory는 `0700`입니다.

## 설정 backup

- `~/.codex/config.toml.backup-20260815T040019+0900`
- `~/.codex/AGENTS.md.backup-20260815T040019+0900`
- `~/.basic-memory/config.json.backup-20260815T041159+0900`

기존 파일 전체를 덮어쓰지 않고 Basic Memory 관련 항목과 짧은 운영 규칙만 추가했습니다.

## Codex 연결

- MCP id: `basic-memory`
- command: `~/.local/bin/basic-memory mcp`
- startup timeout: 30초
- enabled tools: `search_notes`, `read_note`, `write_note`, `edit_note`, `list_directory`, `list_memory_projects`
- 중복 등록: 없음, 정확히 1개
- Codex native Memories: feature/use/generation 모두 `false`; 기존 memory data는 보존
- `~/.codex/basic-memory.json`: 생성하지 않음. 공식 plugin을 설치하지 않았으므로 dead user-level plugin config를 만들지 않았습니다.
- Basic Memory `auto_update`: `false`; exact package pin은 수동 upgrade 때만 변경

## Plugin / Hook

- Basic Memory Codex plugin: 미설치
- Basic Memory lifecycle hook: 미설치·미신뢰
- 현재 Codex의 plugin/hook 지원 자체: 확인됨
- 수동 recall/checkpoint 정책: global `AGENTS.md`와 이 repository 문서에 반영

## Git

- `memory-role` workspace는 조사 시작 시 Git repository가 아니었고 파일도 없었습니다.
- local branch: `main`
- remote: `https://github.com/hun99999/memory-role.git`
- GitHub visibility: `PUBLIC`으로 API 재확인
- 공개 repository에는 운영 자산만 포함합니다.
- canonical Markdown private remote: 미구성
- 자동 backup: 미구성

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
- plugin/hook 미설치 확인
- canonical Markdown과 SQLite/cache/log 분리 확인
- secret/runtime file이 공개 Git staging 대상이 되지 않도록 ignore/검증 규칙 추가
- GitHub `hun99999/memory-role` remote 생성과 `PUBLIC` visibility 확인

### FAIL

- 없음

### PENDING

- 없음. canonical Markdown의 private GitHub backup은 검증 누락이 아니라 의도적으로 선택하지 않은 상태입니다.

## 토큰 효율 증거

- Basic Memory SessionStart/PreCompact hook이 없으므로 자동 memory brief 주입량은 0입니다.
- fresh Codex E2E task는 검색 1회, exact read 1회만 수행했습니다.
- 해당 task의 전체 사용량은 18,695 tokens였습니다. 이 값은 Basic Memory 결과뿐 아니라 Codex의 전역 instructions, 설치된 skill/plugin catalog, 모델 입출력을 모두 포함합니다.
- 정상 운영에서는 이미 대화에 있는 내용을 재검색하지 않고, search 결과를 최대 3개로 제한하며, 필요한 exact note 하나만 읽습니다.

## 알려진 제한

- standalone MCP에서는 `.codex/basic-memory.json`을 Basic Memory가 자동 소비하지 않습니다. global `AGENTS.md`가 repository routing contract로 사용합니다.
- 현재 `main`은 소규모 공통 기억용입니다. 데이터가 커지거나 repository 간 접근 경계가 필요해질 때만 별도 project를 추가해야 합니다.
- 자동 SessionStart context가 없으므로 과거 문맥이 필요한 세션은 제한된 수동 search를 한 번 수행해야 합니다.
- semantic model cache는 파생 상태이며 삭제 시 다시 다운로드됩니다.

## Rollback

1. `codex mcp remove basic-memory`
2. 필요하면 timestamp backup에서 `~/.codex/config.toml`과 `~/.codex/AGENTS.md` 복원
3. package 제거가 필요하면 `uv tool uninstall basic-memory`
4. canonical Markdown과 `~/.basic-memory`는 별도 삭제 승인이 없으면 보존

## 남은 정확한 한 가지 조치

- 없음
