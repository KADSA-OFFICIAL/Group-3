# 배포본 만들기

젤리 워즈의 실행 파일은 **두 종류**입니다. 서버 실행 방법은 [server.md](server.md)를 보세요.

| 프리셋 | 산출물 | 하는 일 |
|---|---|---|
| `Windows Desktop` | `build/JellyWars.exe` | 플레이어용. 접속하면 플레이어 자리에 앉습니다. |
| `Windows Desktop (Observer)` | `build/JellyWars-Observer.exe` | **관전용.** 접속하면 항상 관전자가 됩니다. |

두 프리셋은 [`export_presets.cfg`](../export_presets.cfg)에 들어 있어 저장소를 받으면 그대로 보입니다.
같은 프로젝트에서 나오는 같은 게임이고, 다른 점은 관전 프리셋에 박힌 **기능 태그 `observer`** 하나입니다.
그 태그가 있으면 `Lobby`가 역할을 관전으로 고정합니다 — 화면에서 역할을 고르는 곳은 없습니다.

## 처음 한 번: 내보내기 템플릿 받기

템플릿이 없으면 내보내기가 이 오류로 멈춥니다.

```
예상된 경로에서 찾은 내보내기 템플릿이 없습니다:
.../export_templates/4.6.2.stable/windows_release_x86_64.exe
```

에디터에서 `편집기(Editor)` → `내보내기 템플릿 관리...`를 열고 **현재 버전용 템플릿을 다운로드**합니다
(4.6.2. 약 1GB이고 한 번만 받으면 됩니다). 엔진 버전을 올리면 그 버전 템플릿을 다시 받아야 합니다.

## 내보내기

에디터에서 `프로젝트(Project)` → `내보내기(Export...)`를 열면 프리셋 두 개가 보입니다.

1. `Windows Desktop`을 고르고 `프로젝트 내보내기` → `build/JellyWars.exe`로 저장.
2. `Windows Desktop (Observer)`를 고르고 `프로젝트 내보내기` → `build/JellyWars-Observer.exe`로 저장.
3. `디버그로 내보내기` 체크는 **끕니다**(배포본은 릴리스로).

명령줄로도 됩니다(템플릿을 받은 뒤).

```bash
"Godot_v4.6.2-stable_win64_console.exe" --headless --path . --export-release "Windows Desktop" build/JellyWars.exe
```

```bash
"Godot_v4.6.2-stable_win64_console.exe" --headless --path . --export-release "Windows Desktop (Observer)" build/JellyWars-Observer.exe
```

`build/`와 `*.exe`·`*.pck`는 `.gitignore`에 있으므로 산출물은 커밋되지 않습니다.
`export_presets.cfg`는 산출물이 아니라 **빌드 방법**이라 커밋합니다.

## 나눠 주기

내보낸 폴더에서 `.exe`와 같이 나온 `.pck`를 **함께** 전달해야 실행됩니다(`embed_pck`를 끈 상태).
관전 기기에는 `JellyWars-Observer.exe`만 주면 됩니다.

## 관전 기기 확인

관전 빌드를 실행하면 접속 화면에서 바로 알아볼 수 있습니다.

- 부제가 `JELLY WARS — 관전 모드`(라벤더)
- 접속 버튼이 `관전으로 접속`
- 창 제목이 `젤리 워즈 — 관전`

플레이어 빌드는 지금까지와 같습니다. 겉모습이 같으면 관전 기기로 플레이하려다 헤매게 되므로
**표시를 지우지 마세요.**

## 빌드 없이 관전 켜기 (개발용)

에디터나 명령줄에서 확인할 때는 `--observe` 인자로 같은 효과를 냅니다.

```bash
"Godot_v4.6.2-stable_win64_console.exe" --path . --observe
```

에디터의 F5로 켜려면 `프로젝트 설정` → `편집기` → `실행 인자(Main Run Args)`에 `--observe`를 넣습니다.
**이건 개발용 경로입니다** — 팀에 나눠 줄 때는 관전 빌드를 쓰세요.
