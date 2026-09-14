
젤리 워즈의 실행 파일은 **하나**입니다 — `build/JellyWars.exe`. 한 기기에서 둘이 하는
오프라인 게임이라(이슈 #320) 접속도 서버도 관전 빌드도 없고, 프리셋도 `Windows Desktop`
하나뿐입니다.

| 프리셋 | 산출물 |
| --- | --- |
| `Windows Desktop` | `build/JellyWars.exe` |

프리셋은 [`export_presets.cfg`](../export_presets.cfg)에 있고 저장소에 커밋되어 있습니다 —
산출물이 아니라 **빌드 방법**이기 때문입니다.

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

프로젝트 폴더의 **[`build-exe.bat`](../build-exe.bat)을 더블클릭**하면 내보내고 끝나면
`build` 폴더를 열어 줍니다. Godot 콘솔 바이너리는 환경변수 `GODOT` → 프로젝트 폴더 →
`Downloads` 순으로 찾습니다.

> `build-exe.bat`은 **CP949 + CRLF**로 저장해야 합니다.
> UTF-8로 저장하면 cmd가 줄 중간부터를 명령으로 실행합니다 — 이유는 파일 머리말에 적혀 있습니다.

## 내보내기 — 에디터에서

에디터에서 `프로젝트(Project)` → `내보내기(Export...)`를 열면 프리셋 하나가 보입니다.

1. `Windows Desktop`을 고르고 `프로젝트 내보내기` → `build/JellyWars.exe`로 저장.
2. `디버그로 내보내기` 체크는 **끕니다**(배포본은 릴리스로).

명령줄로도 됩니다(템플릿을 받은 뒤).

```bash
"Godot_v4.6.2-stable_win64_console.exe" --headless --path . --export-release "Windows Desktop" build/JellyWars.exe
```

`build/`와 `*.exe`·`*.pck`는 `.gitignore`에 있으므로 산출물은 커밋되지 않습니다.
`export_presets.cfg`는 산출물이 아니라 **빌드 방법**이라 커밋합니다.

## 나눠 주기

**exe 하나만 보내면 됩니다.** 프리셋이 `binary_format/embed_pck=true`라서 게임 데이터가
exe 안에 들어 있습니다(요청). 파일 하나가 약 104MB입니다.

> 전에는 `embed_pck`가 꺼져 있어서 `.exe`와 `.pck`를 **짝지어** 보내야 했고, 한쪽만 받은 사람은
> "실행이 안 돼요"가 됐습니다. 팀에 나눠 주는 것이 주 용도라 파일 하나 쪽으로 바꿨습니다.
> 되돌리면 그 함정이 같이 돌아옵니다.

### 받은 사람이 할 일

`JellyWars.exe`를 더블클릭하면 끝입니다 — 접속도 방화벽 허용도 없습니다(이슈 #320).
한 키보드에 둘이 앉아 **1P는 `WASD`+왼쪽 `Shift`, 2P는 방향키+`Space`**로 합니다.
