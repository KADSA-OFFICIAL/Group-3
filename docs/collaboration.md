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
        │  (PR, 리뷰 후)
        ▼
       main                    ← 안정 버전. 발표/제출 기준. 항상 실행 가능 상태 유지
```

- `main`에는 **검증과 리뷰를 마친 코드만** 들어갑니다. 직접 커밋 금지, 항상 PR로.
- `dev`에서 먼저 합쳐 보고, Godot에서 실행해 문제가 없을 때만 `main`으로 올립니다.
- 작업 브랜치는 **이슈 1개당 1개**, 끝나면 삭제합니다.

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
- **`main` 대상 PR은 에이전트가 자동으로 머지하지 않습니다.** PR을 열어 두고 CODEOWNERS 리뷰를 기다립니다.
- 브랜치 보호를 admin 권한으로 우회하지 않습니다(`gh pr merge --admin` 금지).
- 자세한 중단 조건은 [CLAUDE.md](../CLAUDE.md)의 Merge Flow 섹션에 있습니다.

## 서로 부딪히지 않으려면

- **작업 시작 전에 이슈를 자기 앞으로 assign**해서 누가 무엇을 하는지 드러냅니다.
- 가능하면 **서로 다른 씬/스크립트 파일**을 건드리도록 이슈를 나눕니다.
  Godot의 `.tscn` 파일은 충돌이 나면 손으로 합치기 까다롭습니다.
- 항상 **`start-task.sh`로 시작**하세요. 이 스크립트가 `dev`를 최신으로 당겨오므로
  다른 사람의 최근 작업 위에서 시작하게 됩니다.
- 충돌이 나면 작업 브랜치에서 `dev`를 먼저 머지해 해결한 뒤 다시 푸시합니다.
  (`git merge origin/dev` → 충돌 해결 → 커밋 → 푸시)
- 다른 사람의 PR은 **CODEOWNERS 기준으로 자동 지정된 리뷰**를 한 번씩 봐 줍니다.

## 최초 1회 GitHub 설정 (저장소 관리자)

> **현재 상태: `main`과 `dev`에 브랜치 보호가 설정되어 있지 않습니다.**
> 아래 설정은 아직 적용되지 않았습니다. 팀원 전원이 admin 권한이라 설정하면 모두에게 영향이 가므로,
> 팀 합의 후 관리자가 적용하세요. 적용하면 이 안내문을 갱신해 주세요.

### 1) `main`, `dev` 브랜치 보호

`Settings → Branches → Add branch ruleset`(또는 Branch protection rules)에서
`main`과 `dev` 각각에 대해:

- Require a pull request before merging (직접 푸시 차단)
- Require approvals: 1 (다른 팀원 1명 승인)
- Require review from Code Owners
- Require branches to be up to date before merging
- Do not allow bypassing the above settings

gh CLI로도 설정할 수 있습니다(관리자 권한 필요):

```bash
gh api -X PUT repos/KADSA-OFFICIAL/Group-3/branches/main/protection \
  -H "Accept: application/vnd.github+json" \
  -f 'required_pull_request_reviews[required_approving_review_count]=1' \
  -f 'required_pull_request_reviews[require_code_owner_reviews]=true' \
  -F 'enforce_admins=true' \
  -F 'required_status_checks=null' \
  -F 'restrictions=null'
# dev 도 동일하게 branches/dev/protection 으로 반복
```

주의: `enforce_admins=true`를 켜면 관리자도 리뷰 없이 머지할 수 없습니다.
현재 팀원 전원이 admin이므로, 켜기 전에 리뷰해 줄 사람이 항상 있는지 확인하세요.

### 2) CODEOWNERS 확인

[.github/CODEOWNERS](../.github/CODEOWNERS)에 현재 팀원이 모두 들어 있는지 확인합니다.
멤버가 바뀌면 사용자명을 갱신합니다. 목록에 없는 사람의 변경에는 리뷰어가 자동 지정되지 않습니다.

### 3) PR 머지 방식

`Settings → General → Pull Requests`에서 "Allow squash merging"만 켜두면
`main` 히스토리가 깔끔하게 유지됩니다.
