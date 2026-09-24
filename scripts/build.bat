@echo off
setlocal EnableExtensions

rem Builds the CalSnap backend and the Android app into dist\ at the repository root.
rem
rem Usage:  scripts\build.bat [debug|release] [all|server|android]
rem
rem   debug    Android debug APK; API_BASE_URL defaults to http://10.0.2.2:8080 (emulator).
rem   release  (default) Android release APKs split per ABI; API_BASE_URL must be an https:// URL.
rem
rem Environment variables (all optional except API_BASE_URL for release):
rem   API_BASE_URL         backend URL compiled into the app, e.g. https://calsnap.example.com
rem   PRIVACY_POLICY_URL   privacy policy URL shown in the app (release)
rem   VERSION              version stamped into the server and the app (default 0.0.0-dev)
rem
rem Server output: dist\calsnap-server-windows-amd64.exe and dist\calsnap-server-linux-amd64.
rem Release signing uses apps\client\android\key.properties when it exists.

set "ORIG=%CD%"
cd /d "%~dp0.." || goto fail
set "ROOT=%CD%"
set "DIST=%ROOT%\dist"

set "MODE=%~1"
if "%MODE%"=="" set "MODE=release"
set "TARGET=%~2"
if "%TARGET%"=="" set "TARGET=all"

if /i not "%MODE%"=="debug" if /i not "%MODE%"=="release" goto usage
if /i not "%TARGET%"=="all" if /i not "%TARGET%"=="server" if /i not "%TARGET%"=="android" goto usage

if "%VERSION%"=="" set "VERSION=0.0.0-dev"

if /i "%MODE%"=="debug" if "%API_BASE_URL%"=="" set "API_BASE_URL=http://10.0.2.2:8080"
if /i "%MODE%"=="release" if /i not "%TARGET%"=="server" goto check_release_url
goto url_ok

:check_release_url
if "%API_BASE_URL%"=="" (
    echo ERROR: API_BASE_URL is required for a release build, for example: set API_BASE_URL=https://calsnap.example.com
    goto fail
)
echo %API_BASE_URL%| findstr /b /i /c:"https://" >nul
if errorlevel 1 (
    echo ERROR: release builds require an https:// API_BASE_URL.
    goto fail
)

:url_ok
if not exist "%DIST%" mkdir "%DIST%"

if /i "%TARGET%"=="android" goto android

rem ---- Server ----------------------------------------------------------------
echo.
echo === Server %VERSION% ===
cd /d "%ROOT%\server" || goto fail
set "CGO_ENABLED=0"

set "GOOS=windows"
set "GOARCH=amd64"
go build -trimpath -ldflags "-s -w -X main.version=%VERSION%" -o "%DIST%\calsnap-server-windows-amd64.exe" .\cmd\calsnap-server
if errorlevel 1 goto fail

set "GOOS=linux"
set "GOARCH=amd64"
go build -trimpath -ldflags "-s -w -X main.version=%VERSION%" -o "%DIST%\calsnap-server-linux-amd64" .\cmd\calsnap-server
if errorlevel 1 goto fail

set "GOOS="
set "GOARCH="
set "CGO_ENABLED="

if /i "%TARGET%"=="server" goto done

rem ---- Android ---------------------------------------------------------------
:android
echo.
echo === Android app (%MODE%) ===
cd /d "%ROOT%\apps\client" || goto fail

call flutter pub get
if errorlevel 1 goto fail

if /i "%MODE%"=="debug" (
    call flutter build apk --debug --dart-define=API_BASE_URL=%API_BASE_URL% --dart-define=APP_VERSION=%VERSION%
    if errorlevel 1 goto fail
    copy /y "build\app\outputs\flutter-apk\app-debug.apk" "%DIST%\calsnap-debug.apk" >nul
    if errorlevel 1 goto fail
) else (
    if not exist "android\key.properties" echo WARNING: android\key.properties not found - the APKs are signed with the debug key and must not be published.
    call flutter build apk --release --split-per-abi --dart-define=API_BASE_URL=%API_BASE_URL% --dart-define=PRIVACY_POLICY_URL=%PRIVACY_POLICY_URL% --dart-define=APP_VERSION=%VERSION%
    if errorlevel 1 goto fail
    for %%F in ("build\app\outputs\flutter-apk\app-*-release.apk") do (
        copy /y "%%~fF" "%DIST%\calsnap-%%~nxF" >nul
        if errorlevel 1 goto fail
    )
)

:done
echo.
echo Build finished. Artifacts in %DIST%:
dir /b "%DIST%"
cd /d "%ORIG%"
endlocal
exit /b 0

:usage
echo Usage: %~nx0 [debug^|release] [all^|server^|android]
cd /d "%ORIG%"
endlocal
exit /b 2

:fail
echo.
echo BUILD FAILED.
cd /d "%ORIG%"
endlocal
exit /b 1
