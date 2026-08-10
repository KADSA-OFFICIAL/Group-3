# 팀 협업 가이드

Group-3(젤리 워즈)은 여러 명이 함께 작업하는 Godot 4 프로젝트입니다. 이 문서는 팀원들이 충돌 없이,
검증된 코드만 `main`에 남기도록 일하는 방법을 정리합니다. 규칙의 근거는
[CLAUDE.md](../CLAUDE.md) / [AGENTS.md](../AGENTS.md)의 issue-first 하네스이고,
명령 흐름은 [github-workflow.md](github-workflow.md)에 있습니다.

## 브랜치 모델

```
feat/fix/issue-<번호>-<주제>   ← 각자 작업하는 일회용 브랜치
        │  (PR, CLEAN이면 자동 머지 가능)
        ▼
       dev                     ← 통합/테스트. 먼저 여기 모아서 확인
        │  (PR, 검증 통과하면 자동 머지)
        ▼
       main                    ← 안정 버전. 발표/제출 기준. 항상 실행 가능 상태 유지
```

- `main`에는 **검증을 마친 코드만** 들어갑니다. 직접 커밋 금지, 항상 PR로.
- `dev`에서 먼저 합쳐 보고, Godot에서 실행해 문제가 없을 때만 `main`으로 올립니다.
- 작업 브랜치는 **이슈 1개당 1개**, 끝나면 삭제합니다.
- `main` 반영에 **사람 리뷰를 요구하지 않습니다**(이슈 #115). 팀원 대부분이 코드를 읽지 못해 리뷰가 검증 역할을 하지 못했고, 리뷰 요청만 쌓인 채 `main` 반영이 막혔습니다. 게이트는 리뷰가 아니라 **검증**입니다.

## 하루 작업 흐름

```bash
# 1. GitHub에서 이슈 생성 (템플릿: Feature / Improvement / Bug / Task)

# 2. 이슈 번호로 dev에서 작업 브랜치 시작 (dev를 최신화한 뒤 분기)
scripts/start-task.sh 12 feat player-jump

# 3. 작업 + Godot에서 확인

# 4. 커밋·푸시하고 dev 대상 PR 생성
scripts/finish-task.sh 12 "Add player jump"

# 5. dev에서 확인되면 같은 브랜치에서 main 대상 PR 생성
scripts/promote-main.sh 12 "Add player jump"

# 6. main 머지 후 원격 작업 브랜치 삭제
```

두 PR 스크립트는 Summary가 빈 PR 본문을 넣습니다. 생성 후 실제 검증 내용으로 채워 주세요.

## 에이전트(Claude Code / Codex)가 작업할 때

- `dev` 대상 PR은 mergeable/CLEAN이고 변경 파일이 이슈 범위와 일치하면 에이전트가 자동으로 머지합니다.
- **`main` 대상 PR도 같은 조건이면 에이전트가 이어서 머지합니다**(이슈 #115). 리뷰를 기다리지 않습니다.
- **예외: 화면으로만 판단되는 변경**(UI 색·배치·글자 크기, 맵 지형 높이, 조작감)은 `dev`까지만 머지하고 멈춥니다. 헤드리스 실행은 오류 유무만 알려주므로 색이 안 읽혀도 통과합니다 — 이런 변경은 사용자가 F5로 본 뒤에 `main`에 올립니다.
- 브랜치 보호를 admin 권한으로 우회하지 않습니다(`gh pr merge --admin` 금지).
- 자세한 중단 조건은 [CLAUDE.md](../CLAUDE.md)의 Merge Flow 섹션에 있습니다. 그 조건은 `dev`와 `main` 양쪽에 적용됩니다.

## 서로 부딪히지 않으려면

- **작업 시작 전에 이슈를 자기 앞으로 assign**해서 누가 무엇을 하는지 드러냅니다.
- 가능하면 **서로 다른 씬/스크립트 파일**을 건드리도록 이슈를 나눕니다.
  Godot의 `.tscn` 파일은 충돌이 나면 손으로 합치기 까다롭습니다.
- 항상 **`start-task.sh`로 시작**하세요. 이 스크립트가 `dev`를 최신으로 당겨오므로
  다른 사람의 최근 작업 위에서 시작하게 됩니다.
- 충돌이 나면 작업 브랜치에서 `dev`를 먼저 머지해 해결한 뒤 다시 푸시합니다.
  (`git merge origin/dev` → 충돌 해결 → 커밋 → 푸시)
- 머지에 리뷰가 필요하지는 않지만, 다른 사람의 PR 본문(summary·verification)은 **무엇이 바뀌었는지 알아 두는 용도로** 한 번씩 읽어 두면 좋습니다. 같은 파일을 건드릴 때 충돌을 미리 피할 수 있습니다.

## 최초 1회 GitHub 설정 (저장소 관리자)

> **현재 상태: `main`과 `dev`에 브랜치 보호가 설정되어 있지 않습니다.** ruleset도 없습니다.
> 2026-08-11 확인 결과 `GET /branches/{main,dev}/protection`이 404 `Branch not protected`,
> `GET /rulesets`가 `[]`입니다. 아래 설정은 **적용해야 하는 것이 아니라 필요해지면 참고할 것**입니다.

### 1) 브랜치 보호를 켠다면 (선택)

지금은 켜지 않은 상태로 두고 있습니다. 검증은 에이전트가 하고 리뷰는 요구하지 않기 때문에(이슈 #115),
보호를 켜서 얻는 것보다 잃는 것이 큽니다.

만약 켠다면 **승인 요구는 넣지 마세요.** `Require approvals`나 `Require review from Code Owners`를
켜면 리뷰해 줄 사람이 필요해져서 지금 흐름(`dev` → `main` 자동 머지)이 그대로 막힙니다.
직접 푸시만 막고 싶다면 이 정도가 적당합니다.

- Require a pull request before merging (직접 푸시 차단)
- Require branches to be up to date before merging

`enforce_admins=true`는 켜지 마세요. 팀원 전원이 admin인데 승인해 줄 사람이 없으면
아무도 머지할 수 없게 됩니다.

### 2) CODEOWNERS

[.github/CODEOWNERS](../.github/CODEOWNERS)의 소유자는 **`@LouizXT` 한 명입니다**(이슈 #115).
전원을 넣어 두었더니 모든 PR에 6명이 리뷰어로 지정되어, 아무도 처리하지 않는 리뷰 요청 알림만 쌓였습니다.
머지를 막는 효력은 없고(보호 규칙이 없으므로) 경로별 소유 표시 용도로만 남겨 둡니다.

### 3) PR 머지 방식

`Settings → General → Pull Requests`에서 "Allow squash merging"만 켜두면
`main` 히스토리가 깔끔하게 유지됩니다.
