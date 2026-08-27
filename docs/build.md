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
(4.6.2. `.tpz` 압축본이 1.17GB이고 한 번만 받으면 됩니다). 엔진 버전을 올리면 그 버전 템플릿을
다시 받아야 합니다.

이 컴퓨터에는 2026-08-28에 받아 두었습니다. Windows 내보내기에 실제로 쓰이는 것은 압축본 35개
항목 중 **두 개뿐**이라 그것만 꺼내 두었습니다.

```
C:\Users\<사용자>\AppData\Roaming\Godot\export_templates\4.6.2.stable\
  windows_release_x86_64.exe   (99.8 MB)
  windows_debug_x86_64.exe     (96.1 MB)
  version.txt
```

`--export-release`만 쓸 때도 **디버그 쪽까지 있어야 합니다** — Godot이 프리셋을 검사할 때 두 개를
다 확인하고, 하나만 없어도 내보내기를 거부합니다. 다른 팀원 컴퓨터에서 내보내려면 그 컴퓨터에도
같은 폴더를 만들어야 합니다(에디터의 템플릿 관리로 받는 것이 가장 쉽습니다).

## 내보내기 — 더블클릭 한 번 (권장)

프로젝트 폴더의 **[`build-exe.bat`](../build-exe.bat)을 더블클릭**하면 두 개를 차례로 내보내고
끝나면 `build` 폴더를 열어 줍니다. Godot 콘솔 바이너리는 `run-server.bat`과 같은 순서로 찾습니다
(환경변수 `GODOT` → 프로젝트 폴더 → `Downloads`).

> `build-exe.bat`은 `run-server.bat`과 같이 **CP949 + CRLF**로 저장해야 합니다.
> UTF-8로 저장하면 cmd가 줄 중간부터를 명령으로 실행합니다 — 이유는 파일 머리말에 적혀 있습니다.

## 내보내기 — 에디터에서

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

## 서버 주소는 빌드에 박힌다

접속 화면에 주소 입력칸이 없으므로(이슈 #198), 클라이언트는 **빌드에 박힌 주소**로만 붙습니다.
주소는 [`scripts/network.gd`](../scripts/network.gd)의 `DEFAULT_ADDRESS` 한 줄입니다.

**서버컴 주소가 바뀌면** 그 줄을 고치고 → 두 프리셋을 다시 내보내고 → 팀에 새 exe를 나눠 줘야
합니다. 옛 exe는 바뀐 서버에 못 붙습니다.

로컬 서버로 확인할 때는 다시 빌드하지 않고 `--address=127.0.0.1`을 붙여 실행하면 됩니다.

## 나눠 주기

**exe 하나만 보내면 됩니다.** 두 프리셋 다 `binary_format/embed_pck=true`라서 게임 데이터가
exe 안에 들어 있습니다(요청). 파일 하나가 약 104MB입니다.

- 팀원에게는 `JellyWars.exe`
- 관전 기기에는 `JellyWars-Observer.exe`

> 전에는 `embed_pck`가 꺼져 있어서 `.exe`와 `.pck`를 **짝지어** 보내야 했고, 한쪽만 받은 사람은
> "실행이 안 돼요"가 됐습니다. 팀에 나눠 주는 것이 주 용도라 파일 하나 쪽으로 바꿨습니다.
> 되돌리면 그 함정이 같이 돌아옵니다.

### 팀원이 처음 실행할 때 — 방화벽 허용

처음 켜면 Windows가 **"공용 및 프라이빗 네트워크에서 이 앱에 액세스하도록 허용하시겠습니까?"**를
묻습니다(게시자 `KADSA`, 앱 `젤리 워즈`). **허용**을 눌러야 서버에 붙습니다.
취소하면 접속 화면에서 "접속 중..."만 돌다가 8초 뒤 실패합니다(`Network.JOIN_TIMEOUT_SEC`).

미리 알려 주지 않으면 대개 습관적으로 취소를 누르고 "게임이 안 된다"고 합니다.

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
