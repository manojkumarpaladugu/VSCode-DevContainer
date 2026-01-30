@echo off
setlocal enabledelayedexpansion

REM ===========================================================================
REM Launcher Script - Windows Batch Version
REM Launch Editor Connected to Remote Host or Remote/Local Docker Container
REM ===========================================================================

REM Default Configuration
set "DEFAULT_HOST=Fusion"
set "DEFAULT_DEV_CONTAINER=/opt/workspace/dev-containers/zephyr"
set "DEFAULT_WORKSPACE=/opt/workspace"
set "DEFAULT_EDITOR=code"
set "SUPPORTED_EDITORS=code cursor"

REM Initialize variables
set "MODE="
set "HOST=%DEFAULT_HOST%"
set "DEV_CONTAINER=%DEFAULT_DEV_CONTAINER%"
set "WORKSPACE=%DEFAULT_WORKSPACE%"
set "EDITOR=%DEFAULT_EDITOR%"
set "DRY_RUN=0"
set "VERBOSE=0"
set "LOG_LEVEL=INFO"

REM ===========================================================================
REM Parse Command Line Arguments
REM ===========================================================================

if "%~1"=="" goto :show_help

set "MODE=%~1"
shift
if /i not "%MODE%"=="remote-host" if /i not "%MODE%"=="remote-container" if /i not "%MODE%"=="local-container" (
    echo [ERROR] Invalid mode: %MODE%
    goto :show_help
)

goto :parse_args
:parse_args
if "%~1"=="" goto :validate_args

if /i "%~1"=="--host" (
    set "HOST=%~2"
    shift
    shift
    goto :parse_args
)

if /i "%~1"=="--workspace" (
    set "WORKSPACE=%~2"
    shift
    shift
    goto :parse_args
)

if /i "%~1"=="--editor" (
    set "EDITOR=%~2"
    shift
    shift
    goto :parse_args
)

if /i "%~1"=="--dev-container" (
    set "DEV_CONTAINER=%~2"
    shift
    shift
    goto :parse_args
)

if /i "%~1"=="--dry-run" (
    set "DRY_RUN=1"
    shift
    goto :parse_args
)

if /i "%~1"=="--verbose" (
    set "VERBOSE=1"
    set "LOG_LEVEL=DEBUG"
    shift
    goto :parse_args
)

if /i "%~1"=="--help" goto :show_help
if /i "%~1"=="-h" goto :show_help
if /i "%~1"=="/?" goto :show_help

echo [ERROR] Unknown argument: %~1
goto :show_help

:validate_args
REM Validate editor
set "VALID_EDITOR=0"
for %%e in (%SUPPORTED_EDITORS%) do (
    if /i "%EDITOR%"=="%%e" set "VALID_EDITOR=1"
)

if "%VALID_EDITOR%"=="0" (
    echo [ERROR] Unsupported editor: %EDITOR%
    echo [ERROR] Supported editors: %SUPPORTED_EDITORS%
    pause
    exit /b 1
)

goto :main

REM ===========================================================================
REM Helper Functions
REM ===========================================================================

:log_info
echo [INFO] %~1
exit /b 0

:log_debug
if "%VERBOSE%"=="1" echo [DEBUG] %~1
exit /b 0

:log_error
echo [ERROR] %~1
exit /b 0

:log_warning
echo [WARNING] %~1
exit /b 0

:hex_encode
REM Hex encode a path for vscode-remote URI
set "INPUT_PATH=%~1"
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "$bytes = [System.Text.Encoding]::UTF8.GetBytes('%INPUT_PATH%'); -join ($bytes | ForEach-Object { $_.ToString('x2') })"`) do set "HEX_PATH=%%i"
exit /b 0

:run_command
REM Execute a command with dry-run and verbose support
if "%DRY_RUN%"=="1" (
    call :log_info "[Dry-Run] Would execute: !COMMAND_TO_RUN!"
    exit /b 0
)

call :log_debug "Executing command: !COMMAND_TO_RUN!"

!COMMAND_TO_RUN! >nul 2>&1
if errorlevel 1 (
    call :log_error "Command failed: !COMMAND_TO_RUN!"
    pause
    exit /b 1
)

exit /b 0

:verify_docker
REM Verify Docker is running
call :log_debug "Verifying Docker is running..."

set "COMMAND_TO_RUN=docker info"
call :run_command
if errorlevel 1 (
    call :log_error "Docker is not running or not accessible"
    pause
    exit /b 1
)

call :log_debug "Docker verified successfully"
exit /b 0

:show_help
echo.
echo Usage: %~nx0 MODE [OPTIONS]
echo.
echo Launch Editor Connected to Remote Host or Remote/Local Docker Container
echo.
echo Modes:
echo   remote-host         Connect to remote host via SSH
echo   remote-container    Connect to Docker container on remote host via SSH
echo   local-container     Connect to Docker container on local host
echo.
echo Options:
echo   --host HOST           Remote hostname for SSH connections
echo   --workspace PATH      Absolute path to workspace directory
echo   --editor EDITOR       Specify editor (code, cursor)
echo   --dev-container PATH  Absolute path to .devcontainer directory
echo   --dry-run             Print commands without executing
echo   --verbose             Enable verbose output
echo   --help, -h, /?        Show this help message
echo.
echo Examples:
echo   %~nx0 remote-host --host myserver
echo   %~nx0 remote-container --host myserver --dev-container /path/to/.devcontainer
echo   %~nx0 local-container --dev-container /path/to/.devcontainer
echo.
pause
exit /b 1

REM ===========================================================================
REM Main
REM ===========================================================================

:main

set "URI="

if /i "%MODE%"=="remote-host" goto :mode_remote_host
if /i "%MODE%"=="remote-container" goto :mode_remote_container
if /i "%MODE%"=="local-container" goto :mode_local_container

:mode_remote_host
set "URI=vscode-remote://ssh-remote+%HOST%%WORKSPACE%"
goto :launch_editor

:mode_remote_container
call :hex_encode "%DEV_CONTAINER%"
set "URI=vscode-remote://dev-container+!HEX_PATH!@ssh-remote+%HOST%%WORKSPACE%"
goto :launch_editor

:mode_local_container
call :verify_docker
if errorlevel 1 exit /b 1
call :hex_encode "%DEV_CONTAINER%"
set "URI=vscode-remote://dev-container+!HEX_PATH!@%WORKSPACE%"
goto :launch_editor

:launch_editor
REM Display launch parameters
echo ===========================================================================
call :log_info "Launching with the following parameters:"
echo ===========================================================================
call :log_info "Mode              : %MODE%"
if /i "%MODE%"=="remote-host" (
    call :log_info "Host              : %HOST%"
)
if /i "%MODE%"=="remote-container" (
    call :log_info "Host              : %HOST%"
    call :log_info "Dev Container     : %DEV_CONTAINER%"
)
if /i "%MODE%"=="local-container" (
    call :log_info "Dev Container     : %DEV_CONTAINER%"
)
call :log_info "Workspace         : %WORKSPACE%"
call :log_info "Editor            : %EDITOR%"
echo ===========================================================================

REM Launch the editor
set "COMMAND_TO_RUN=%EDITOR% --folder-uri %URI%"

if "%DRY_RUN%"=="1" (
    call :log_info "[Dry-Run] Would execute: !COMMAND_TO_RUN!"
    goto :end
)

call :log_debug "Executing command: !COMMAND_TO_RUN!"

<nul >nul 2>nul start /B "" call %EDITOR% --folder-uri "%URI%"
if errorlevel 1 (
    call :log_error "Failed to launch %EDITOR%"
    pause
    exit /b 1
)

:end
exit /b 0
