@echo off
rem ============================================================
rem  배포본(exe) 만들기 - 더블클릭 한 번으로 두 개를 내보낸다 (요청)
rem
rem  플레이어용 build\JellyWars.exe 와 관전용 build\JellyWars-Observer.exe 를
rem  차례로 내보낸다. 프리셋은 export_presets.cfg 에 들어 있고 이 스크립트는
rem  그것을 이름으로 부르기만 한다 - 프리셋을 고치면 여기는 손댈 필요가 없다.
rem  자세한 설명과 나눠 주는 방법은 docs/build.md.
rem
rem  === 고칠 때 지켜야 하는 것 (run-server.bat 과 같은 이유) ===
rem  이 파일은 CP949(ANSI 한국어) + CRLF 로 저장한다. cmd 의 배치 파서는 파일
rem  안 위치를 바이트로 세기 때문에, UTF-8 로 저장하면 한글 한 자가 3바이트라
rem  줄 위치가 어긋나 줄 중간부터를 명령으로 실행한다. .gitattributes 가
rem  *.bat 의 줄끝을 CRLF 로 지켜 주지만 인코딩은 사람이 지켜야 한다.
rem ============================================================
setlocal enabledelayedexpansion
title 젤리 워즈 배포본 만들기

set "PROJECT_DIR=%~dp0"
set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"

echo.
echo  ===== 젤리 워즈 배포본 만들기 =====
echo.

rem ---------- 1. Godot 콘솔 바이너리 찾기 ----------
rem run-server.bat 과 같은 순서로 찾는다: 환경변수 GODOT, 프로젝트 폴더, Downloads.
set "GODOT_EXE="
if defined GODOT (
	if exist "%GODOT%" set "GODOT_EXE=%GODOT%"
)
if not defined GODOT_EXE (
	for /f "delims=" %%F in ('dir /b /s /o-n "%PROJECT_DIR%\Godot_*_console.exe" 2^>nul') do (
		if not defined GODOT_EXE set "GODOT_EXE=%%F"
	)
)
if not defined GODOT_EXE (
	for /f "delims=" %%F in ('dir /b /s /o-n "%USERPROFILE%\Downloads\Godot_*_console.exe" 2^>nul') do (
		if not defined GODOT_EXE set "GODOT_EXE=%%F"
	)
)

if not defined GODOT_EXE (
	echo  [실패] Godot 콘솔 바이너리를 찾지 못했습니다.
	echo         이름이 _console.exe 로 끝나는 실행 파일이 필요합니다.
	echo         [예: Godot_v4.6.2-stable_win64_console.exe]
	echo         프로젝트 폴더나 Downloads 에 두거나 경로를 지정하세요.
	echo.
	echo           set GODOT=D:\godot\Godot_v4.6.2-stable_win64_console.exe
	echo           build-exe.bat
	echo.
	pause
	exit /b 1
)

echo  Godot    : %GODOT_EXE%
echo  프로젝트 : %PROJECT_DIR%
echo.

if not exist "%PROJECT_DIR%\build" mkdir "%PROJECT_DIR%\build"

rem ---------- 2. 두 프리셋을 차례로 내보내기 ----------
rem 릴리스로 내보낸다. 디버그 빌드는 팀에 주는 것이 아니다.
set "FAILED="

call :EXPORT "Windows Desktop" "build\JellyWars.exe" "플레이어용"
call :EXPORT "Windows Desktop (Observer)" "build\JellyWars-Observer.exe" "관전용"

echo.
if defined FAILED (
	echo  ===== 실패한 것이 있습니다 =====
	echo.
	echo  위에 찍힌 오류를 보세요. 가장 흔한 원인은 내보내기 템플릿이 없는 것입니다.
	echo  그때는 에디터에서 [편집기] - [내보내기 템플릿 관리...] 로 4.6.2 템플릿을
	echo  받으면 됩니다. 자세한 것은 docs/build.md.
	echo.
	pause
	exit /b 1
)

echo  ===== 다 됐습니다 =====
echo.
echo  만들어진 파일
for %%F in ("%PROJECT_DIR%\build\JellyWars.exe" "%PROJECT_DIR%\build\JellyWars-Observer.exe") do (
	if exist "%%~F" echo    - %%~nxF  [%%~zF 바이트]
)
echo.
echo  나눠 줄 때
echo    - 팀원에게는 JellyWars.exe 하나만 보내면 됩니다.
echo      게임 데이터가 exe 안에 들어 있어 pck 를 따로 보낼 필요가 없습니다.
echo    - 관전 기기에는 JellyWars-Observer.exe 를 보냅니다.
echo    - 서버컴 주소가 바뀌면 scripts\network.gd 의 DEFAULT_ADDRESS 를 고치고
echo      다시 내보내야 합니다. 옛 exe 는 바뀐 서버에 못 붙습니다.
echo.
echo  build 폴더를 엽니다.
start "" "%PROJECT_DIR%\build"
echo.
pause
exit /b 0

rem ---------- 내보내기 한 번 ----------
rem %1 프리셋 이름, %2 산출물 상대경로, %3 화면에 적을 이름
:EXPORT
echo  [%~3] %~2 내보내는 중...
"%GODOT_EXE%" --headless --path "%PROJECT_DIR%" --export-release %1 "%PROJECT_DIR%\%~2"
if errorlevel 1 (
	echo  [실패] %~3 내보내기가 실패했습니다.
	set "FAILED=1"
	goto :eof
)
rem Godot 은 내보내기가 실패해도 종료 코드를 0 으로 주는 경우가 있다 -
rem 파일이 실제로 생겼는지로 한 번 더 확인한다.
if not exist "%PROJECT_DIR%\%~2" (
	echo  [실패] %~3 내보내기가 끝났다고 하는데 파일이 없습니다.
	set "FAILED=1"
	goto :eof
)
echo  [완료] %~2
echo.
goto :eof
