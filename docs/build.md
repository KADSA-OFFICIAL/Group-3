**빌드는 Android(apk)로만 만듭니다**(이슈 #418). Windows 내보내기(`Windows Desktop` 프리셋·`build-exe.bat`)는
없앴습니다. PC 에서는 에디터 F5 로 확인합니다.

| 프리셋 | 산출물 | 쓰임 |
| --- | --- | --- |
| `Android` | `build/JellyWars.apk` | 실제로 하는 것 — 화면 조이스틱 + 궁극기 버튼 |

프리셋은 [`export_presets.cfg`](../export_presets.cfg)에 있고 저장소에 커밋되어 있습니다 —
산출물이 아니라 **빌드 방법**이기 때문입니다. `build/`와 `*.pck`는 `.gitignore`에 있으므로
산출물은 커밋되지 않습니다.

## 처음 한 번: 내보내기 템플릿 받기

에디터에서 `편집기(Editor)` → `내보내기 템플릿 관리...`를 열고 **현재 버전용 템플릿을 다운로드**합니다
(4.6.2. `.tpz` 압축본이 1.17GB이고 한 번만 받으면 됩니다). 엔진 버전을 올리면 그 버전 템플릿을
다시 받아야 합니다.

## 내보내기 (이슈 #322)

**템플릿 말고도 준비가 더 필요합니다.** Android 는 에디터 바깥의 도구가
있어야 합니다 — 에디터가 `편집기 설정 → 내보내기 → Android` 에서 이 셋의 경로를 묻습니다.

1. **Android SDK** (Android Studio 를 깔면 같이 들어옵니다)
2. **JDK 17**
3. **디버그 키스토어** — 에디터가 만들어 주거나, 직접 만든 것을 지정합니다

준비가 끝나면 `프로젝트 → 내보내기` 에서 `Android` 프리셋을 고르고 `build/JellyWars.apk` 로
내보냅니다. 명령줄로도 됩니다.

```bash
"<godot>" --headless --path . --export-debug "Android" build/JellyWars.apk
```

받은 사람은 apk 를 폰에 옮겨 설치합니다(스토어를 거치지 않으므로 **출처를 알 수 없는 앱 설치**를
한 번 허용해야 합니다). **기기를 가로로 놓고** 왼쪽 아래 조이스틱과 궁극기 버튼이 1P,
오른쪽 아래가 2P 입니다 — 화면 방향은 `project.godot` 에서 가로로 고정해 두었습니다.

> **릴리즈 키스토어가 없어 apk 는 `--export-debug`로 만듭니다**(`--export-release`는
> "릴리즈 키스토어를 찾을 수 없어" 실패합니다). 내보내기에는 `project.godot`의
> `textures/vram_compression/import_etc2_astc=true`가 있어야 합니다(이슈 #370).
