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

## Google Play 용 AAB (이슈 #478)

Play 스토어는 새 앱에 **AAB**(Android App Bundle)와 **출시용 서명**을 요구합니다. 그래서 프리셋이 둘입니다.

| 프리셋 | 산출물 | 서명 | 쓰임 |
| --- | --- | --- | --- |
| `Android` | `build/JellyWars.apk` | 디버그 키 (`--export-debug`) | 친구에게 바로 설치해 보게 할 때 |
| `Android (Play)` | `build/JellyWars.aab` | **업로드 키** (`--export-release`) | Play Console 에 올릴 때 |

`Android (Play)` 는 **Gradle 빌드**를 씁니다(Godot 은 Gradle 로만 AAB 를 만듭니다). 타깃 API 는
`gradle_build/target_sdk="36"`, 아키텍처는 arm64-v8a 만입니다. **올릴 때마다 `version/code` 를 1씩
올려야** Play 가 받아 줍니다(`version/name` 은 사람이 보는 번호).

### 처음 한 번 더 필요한 것

1. 내보내기 템플릿 안의 `android_source.zip` (Gradle 빌드 템플릿). 내보낼 때
   `--install-android-build-template` 를 붙이면 프로젝트의 `android/` 에 풀립니다(`.gitignore` 에 있음).
2. Android SDK 의 `platforms/android-35` (컴파일용)와 `build-tools/35.0.1`·`platform-tools`.
3. **업로드 키** — 저장소 밖에 둡니다. 절대 커밋하지 않습니다. 잃어버리면 Play Console 에서
   업로드 키 재설정을 요청해야 하므로 따로 백업합니다.

### 내보내기 (명령줄)

키 경로·별칭·비밀번호는 프리셋에 적지 않고 환경 변수로 넘깁니다.

```bash
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="<업로드 키 .keystore 경로>"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="<별칭>"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="<비밀번호>"
"<godot>" --headless --path . --install-android-build-template --export-release "Android (Play)" build/JellyWars.aab
```

> **`Godot_..._console.exe` 로 내보내면 끝나지 않을 수 있습니다.** Gradle 이 띄운 데몬(java)이 콘솔 래퍼의
> 출력 파이프를 물려받아, 래퍼가 그 파이프가 닫히기를 하염없이 기다립니다(AAB 는 이미 만들어져 있음).
> 명령줄에서는 콘솔 없는 `Godot_..._win64.exe` 를 쓰고, 끝나면 `android/build/gradlew --stop` 으로 데몬을 끕니다.

### dl.google.com 이 막힌 네트워크

학교·회사망처럼 `dl.google.com` 이 막혀 있으면 Gradle 이 Google Maven 의존성을 못 받습니다.
같은 파일을 주는 Google 공식 별칭 `dl-ssl.google.com` 으로 돌리는 init 스크립트가
[`tools/android/dl-ssl.init.gradle`](../tools/android/dl-ssl.init.gradle) 입니다. 내보내기 전에
Gradle 홈을 따로 잡고 그 `init.d/` 에 넣어 둡니다(평소 Gradle 설정은 건드리지 않습니다).

```bash
export GRADLE_USER_HOME="<아무 빈 폴더>"
mkdir -p "$GRADLE_USER_HOME/init.d" && cp tools/android/dl-ssl.init.gradle "$GRADLE_USER_HOME/init.d/"
```

SDK 부품도 `https://dl-ssl.google.com/android/repository/<파일 이름>` 에서 받을 수 있습니다
(파일 이름·SHA-1 은 같은 곳의 `repository2-3.xml`).

## 앱 아이콘 (이슈 #478)

`assets/icon/` 의 그림을 두 프리셋의 `launcher_icons/*` 가 씁니다 — 기본 런처 192px, 적응형 앞·뒤 판
432px, Play 스토어 등록용 `play_512.png`. **타이틀 배경(`assets/ui/cover.png`)의 가운데 정사각형**을 그대로 쓰고(적응형은 뒤판에 깔고 앞판은 비움 — 런처에서는 가운데 약 2/3 만 보인다), 다시 만들려면:

```bash
"<godot>" --headless --path . --script res://tools/make_icons.gd
```
