@echo off
rem ============================================================
rem  젤리 워즈 전용 서버 실행기 (이슈 #201)
rem
rem  더블클릭하면 방마다 콘솔 창 하나씩 열고 그 안에서 헤드리스 서버를 띄운다.
rem  띄우기 전에 원격 저장소와 게임 파일을 맞춘다 - 서버와 클라이언트의 파일이
rem  다르면 입장이 안 되기 때문이다. 자세한 내용은 아래 2번 단락.
rem  방 목록(포트)은 scripts/network.gd 의 ROOMS 에서 읽는다 -
rem  방 구성의 유일한 출처가 그곳이므로 이 파일에 포트를 적지 않는다.
rem  ROOMS 에 줄을 추가하면 이 스크립트를 고치지 않아도 그 방까지 함께 뜬다.
rem  서버를 띄우는 사람이 볼 문서는 docs/server.md.
rem
rem  === 고칠 때 지켜야 하는 것 (안 지키면 원인과 전혀 다른 모습으로 깨진다) ===
rem  이 파일은 CP949(ANSI 한국어) + CRLF 로 저장한다. cmd 의 배치 파서는 파일
rem  안의 위치를 바이트로 세는데, UTF-8 로 저장하면 한글 한 자가 3바이트라
rem  줄 위치가 어긋나서 줄 중간부터를 명령으로 실행한다. 한글 줄이 네다섯 줄만
rem  이어져도 재현되고, 오류는 엉뚱한 조각(예: "닙니다."가 명령이 아니라는 식)으로
rem  나와 원인을 짚기 어렵다. LF 만 있는 줄바꿈도 같은 증상을 만든다.
rem  - 메모장 등으로 열어 UTF-8 로 저장하지 말 것. .gitattributes 가 이 파일을
rem    변환 없이 그대로 넘기도록 표시해 두었다.
rem  - 한글 문구를 늘려도 되지만 저장 인코딩만은 건드리지 말 것.
rem  - chcp 는 이 창에서 부르지 않는다. 기본 코드페이지(949)로 두고, 서버를
rem    띄우는 새 창에서만 65001 로 바꾼다. Godot 로그가 UTF-8 이기 때문이다.
rem ============================================================
setlocal enabledelayedexpansion
title 젤리 워즈 서버 실행기

rem ---------- 0. 임시 폴더로 자신을 옮겨 실행 ----------
rem 아래 2번에서 원격과 파일을 맞출 때 이 파일 자신이 덮어써질 수 있다.
rem cmd 는 배치 파일을 "파일 안 몇 번째 바이트" 로 기억해 두고 한 줄 끝날 때마다
rem 다시 읽기 때문에, 실행 도중에 파일이 바뀌면 그 다음부터 줄 중간을 명령으로
rem 실행한다. 실제로 "echo LINE-B" 가 "B" 만 명령으로 실행되는 것을 확인했다.
rem 그래서 먼저 %TEMP% 로 자신을 복사해 그쪽에서 실행하고, 원본은 마음대로
rem 덮이게 둔다. 복사본의 %~dp0 는 %TEMP% 라서 못 쓰므로 원래 폴더를 인자로 넘긴다.
rem
rem %~dp0 는 끝에 \ 가 붙어 있다. 그대로 "..." 안에 넣으면 마지막 \ 가 닫는
rem 따옴표를 이스케이프해 버리므로 잘라낸다.
set "PROJECT_DIR=%~dp0"
set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"

if /i "%~1"=="--relaunched" goto :RELAUNCHED

set "SELF_COPY=%TEMP%\jellywars-run-server.bat"
copy /y "%~f0" "%SELF_COPY%" >nul 2>&1
if errorlevel 1 (
	echo.
	echo  [경고] 임시 폴더로 복사하지 못해 원본에서 그대로 실행합니다.
	echo         실행기 자신이 갱신되면 이 창이 이상하게 동작할 수 있습니다.
	echo         그럴 때는 창을 닫고 한 번 더 실행하면 됩니다.
	goto :RELAUNCHED
)

rem call 이 아니라 그냥 부른다. call 이면 끝나고 원본으로 돌아오려고 원본을
rem 계속 읽으므로 위험이 그대로 남는다. 이렇게 부르면 제어가 넘어가고 끝난다.
"%SELF_COPY%" --relaunched "%PROJECT_DIR%"

:RELAUNCHED
if /i "%~1"=="--relaunched" set "PROJECT_DIR=%~2"
set "NETWORK_GD=%PROJECT_DIR%\scripts\network.gd"

echo.
echo  ===== 젤리 워즈 서버 실행기 =====
echo.

rem ---------- 1. Godot 콘솔 바이너리 찾기 ----------
rem 우선순위: 환경변수 GODOT, 프로젝트 폴더, %USERPROFILE%\Downloads
set "GODOT_EXE="
if defined GODOT (
	if exist "%GODOT%" (
		set "GODOT_EXE=%GODOT%"
	) else (
		echo  [경고] GODOT 환경변수가 가리키는 파일이 없습니다: %GODOT%
		echo         다른 곳에서 찾아봅니다.
	)
)
if not defined GODOT_EXE (
	for /f "delims=" %%F in ('dir /b /s /o-n "%PROJECT_DIR%\Godot_*_console.exe" 2^>nul') do (
		if not defined GODOT_EXE set "GODOT_EXE=%%F"
	)
)
if not defined GODOT_EXE (
	rem 이름 역순(/o-n)으로 훑으므로 버전이 여러 개면 새 것이 먼저 걸린다.
	for /f "delims=" %%F in ('dir /b /s /o-n "%USERPROFILE%\Downloads\Godot_*_console.exe" 2^>nul') do (
		if not defined GODOT_EXE set "GODOT_EXE=%%F"
	)
)

if not defined GODOT_EXE (
	echo  [실패] Godot 콘솔 바이너리를 찾지 못했습니다.
	echo.
	echo   찾아본 곳
	echo     - 환경변수 GODOT
	echo     - %PROJECT_DIR%
	echo     - %USERPROFILE%\Downloads
	echo.
	echo   이름이 _console.exe 로 끝나는 실행 파일이 필요합니다.
	echo   [예: Godot_v4.6.2-stable_win64_console.exe]
	echo   위 폴더 중 하나에 두거나, 다음처럼 경로를 지정해 실행하세요.
	echo.
	echo     set GODOT=D:\godot\Godot_v4.6.2-stable_win64_console.exe
	echo     run-server.bat
	echo.
	pause
	exit /b 1
)

if not exist "%NETWORK_GD%" (
	echo  [실패] 방 목록을 읽을 파일이 없습니다.
	echo         %NETWORK_GD%
	echo         이 스크립트는 프로젝트 폴더 안에 두고 실행해야 합니다.
	echo.
	pause
	exit /b 1
)

echo  Godot    : %GODOT_EXE%
echo  프로젝트 : %PROJECT_DIR%
echo.

rem ---------- 2. 최신 게임 파일 받기 ----------
rem 서버가 옛 파일로 떠 있으면 최신 클라이언트가 접속해도 입장이 안 된다.
rem 그래서 띄우기 전에 원격과 강제로 맞춘다. 이 컴퓨터는 서버 전용이라
rem 여기서 게임 파일을 고칠 일이 없다는 전제다 - 고쳐야 하면 다른 컴퓨터에서
rem 고치고 push 한 뒤 이 스크립트를 다시 돌린다.
rem
rem merge(=git pull) 가 아니라 fetch + reset --hard 를 쓴다. Godot 이 .import
rem 파일을 LF 로 다시 쓰는데 저장소에는 CRLF 로 들어 있어서, 내용이 같아도
rem git 은 "수정됨" 으로 보고 merge 를 거부한다. 이 컴퓨터에서는 그 상태가
rem 상시라 merge 로는 거의 매번 막힌다.
rem
rem 인터넷이 안 되면 있는 파일로 그냥 띄운다 - 서버가 아예 안 뜨는 것보다 낫다.
rem GIT_TERMINAL_PROMPT=0 은 git 이 아이디/비밀번호를 물으며 창을 붙잡고
rem 멈추는 것을 막는다. 물어야 하는 상황이면 그냥 실패시키고 넘어간다.
set "GIT_TERMINAL_PROMPT=0"
set "GIT_SKIP="
where git >nul 2>&1
if errorlevel 1 set "GIT_SKIP=git 이 설치되어 있지 않습니다"
if not exist "%PROJECT_DIR%\.git" set "GIT_SKIP=이 폴더가 git 저장소가 아닙니다"

if defined GIT_SKIP (
	echo  [경고] 최신 파일 받기를 건너뜁니다 - !GIT_SKIP!
	echo         서버가 옛 파일로 떠서 클라이언트가 입장하지 못할 수 있습니다.
	echo.
	goto :SYNC_DONE
)

rem git 에 경로를 넘기지 않고 폴더로 들어가서 부른다. 프로젝트 경로에 한글이
rem 들어 있어도 cmd 가 알아서 처리하므로 인코딩 사고가 나지 않는다.
pushd "%PROJECT_DIR%"

set "HEAD_BEFORE="
for /f "delims=" %%H in ('git rev-parse HEAD 2^>nul') do set "HEAD_BEFORE=%%H"
set "BRANCH="
for /f "delims=" %%B in ('git rev-parse --abbrev-ref HEAD 2^>nul') do set "BRANCH=%%B"

if not defined BRANCH (
	echo  [경고] 현재 브랜치를 알 수 없어 최신 파일 받기를 건너뜁니다.
	echo.
	popd
	goto :SYNC_DONE
)

echo  최신 게임 파일을 받는 중... [브랜치 !BRANCH!]
git fetch --prune origin
if errorlevel 1 (
	echo.
	echo  [경고] 원격에서 받지 못했습니다. 인터넷 연결을 확인하세요.
	echo         지금 있는 파일로 띄웁니다 - 클라이언트와 버전이 다르면
	echo         입장이 안 될 수 있습니다.
	echo.
	popd
	goto :SYNC_DONE
)

git rev-parse --verify "origin/!BRANCH!" >nul 2>&1
if errorlevel 1 (
	echo  [경고] origin/!BRANCH! 가 없어 최신화를 건너뜁니다.
	echo.
	popd
	goto :SYNC_DONE
)

rem 여기서 이 폴더의 로컬 변경은 버려진다. 위에 적은 전제가 그래서 중요하다.
git reset --hard "origin/!BRANCH!"
if errorlevel 1 (
	echo.
	echo  [경고] 최신화에 실패했습니다. 지금 있는 파일로 띄웁니다.
	echo.
	popd
	goto :SYNC_DONE
)

set "HEAD_AFTER="
for /f "delims=" %%H in ('git rev-parse HEAD 2^>nul') do set "HEAD_AFTER=%%H"
popd

if "!HEAD_BEFORE!"=="!HEAD_AFTER!" (
	echo  이미 최신입니다.
	echo.
	goto :SYNC_DONE
)

rem class_name 이 붙은 스크립트가 새로 들어오면 .godot 의 클래스 캐시가 낡아서
rem "Could not find type ..." 파스 에러가 쏟아지고 서버가 제구실을 못 한다.
rem --import 는 캐시만 다시 만들고 추적 파일은 건드리지 않는다.
rem (--editor 로 열면 .tscn 의 uid 까지 다시 써서 저장소가 더러워진다.)
echo  게임 파일이 바뀌었습니다. Godot 캐시를 다시 만드는 중...
"%GODOT_EXE%" --headless --import --path "%PROJECT_DIR%" >nul 2>&1
echo  준비가 끝났습니다.
echo.

:SYNC_DONE

rem ---------- 3. scripts/network.gd 의 ROOMS 에서 포트 읽기 ----------
rem 포트만 읽고 방 이름은 읽지 않는다. network.gd 는 UTF-8 이고 이 창은 CP949
rem 라서 한글 방 이름을 그대로 가져오면 창 제목이 깨진다. 창은 ROOMS 의 몇 번째
rem 줄인지와 포트로 구분한다 - 포트가 곧 방이다.
set "ROOM_COUNT=0"
for /f "usebackq delims=" %%L in (`findstr /c:"\"port\":" "%NETWORK_GD%"`) do (
	set "line=%%L"
	rem ROOMS 항목은 { 로 시작한다. 주석에 "port": 가 들어가도 걸러진다.
	if not "!line!"=="!line:{=!" (
		rem "port" 뒤쪽만 남기고 숫자만 뽑는다. 키 순서가 바뀌어도 된다.
		set "rest=!line:*"port"=!"
		for /f "tokens=1 delims=:" %%A in ("!rest!") do set "port=%%A"
		set "port=!port: =!"
		set "port=!port:}=!"
		set "port=!port:,=!"
		echo !port!| findstr /r /c:"^[0-9][0-9]*$" >nul
		if errorlevel 1 (
			echo  [경고] 포트를 읽지 못해 건너뜁니다: !line!
		) else (
			set /a ROOM_COUNT+=1
			set "ROOM_PORT_!ROOM_COUNT!=!port!"
		)
	)
)

if "%ROOM_COUNT%"=="0" (
	echo  [실패] scripts/network.gd 의 ROOMS 에서 방을 하나도 읽지 못했습니다.
	echo         ROOMS 형식이 바뀌었는지 확인하세요.
	echo.
	pause
	exit /b 1
)

rem ---------- 4. 이미 쓰고 있는 포트가 없는지 미리 본다 ----------
rem 포트를 못 열면 서버는 일부러 죽는다(exit 1). 미리 알려주면 창을 안 뒤져도 된다.
for /l %%I in (1,1,%ROOM_COUNT%) do (
	netstat -ano -p UDP | findstr /c:":!ROOM_PORT_%%I! " >nul
	if not errorlevel 1 (
		echo  [경고] UDP !ROOM_PORT_%%I! 을 이미 누가 쓰고 있습니다.
		echo         그 방 서버가 이미 떠 있을 수 있습니다. 새로 뜨는 창은 곧 실패합니다.
		echo.
	)
)

rem ---------- 5. 방마다 창 하나씩 띄운다 ----------
rem cmd /k 라서 서버가 죽어도 창이 남는다. 실패 메시지를 읽을 수 있다.
rem 새 창에서 chcp 65001 을 하는 이유는 Godot 로그가 UTF-8 이기 때문이다.
echo  방 %ROOM_COUNT%개를 띄웁니다.
for /l %%I in (1,1,%ROOM_COUNT%) do (
	echo   - ROOMS %%I번째 방 [UDP !ROOM_PORT_%%I!]
	start "젤리 워즈 서버 - %%I번째 방 [UDP !ROOM_PORT_%%I!]" cmd /k "chcp 65001 >nul & "%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --port=!ROOM_PORT_%%I!"
)

echo.
echo  창마다 이런 줄이 찍혔는지 확인하세요.
echo    서버 시작 - [방 이름], 포트 [포트], 플레이어 2명 + 관전 4명
echo  이 줄이 없으면 서버가 뜬 게 아닙니다. docs/server.md 의 문제 해결을 보세요.
echo.
echo  서버를 끄려면 그 방의 창에서 Ctrl+C 를 누르거나 창을 닫으세요.
echo  이 창은 이제 닫아도 됩니다.
echo.
pause
exit /b 0
