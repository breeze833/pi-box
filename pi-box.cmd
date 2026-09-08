@echo off
setlocal enabledelayedexpansion

:: Resolve directory of this script
set "SCRIPT_DIR=%~dp0"
set "WORKDIR=%CD%"
set "FORCE_BUILD=0"
set "FORCE_PULL=0"
set "IMAGE_NAME=ghcr.io/breeze833/pi-box:latest"
if defined PI_BOX_IMAGE set "IMAGE_NAME=%PI_BOX_IMAGE%"

:: Parse CLI arguments
set "EXTRA_ARGS="
:parse_args
if "%~1"=="" goto end_args

if /i "%~1"=="-h" goto show_help
if /i "%~1"=="--help" goto show_help

if /i "%~1"=="-w" (
    if "%~2"=="" (
        echo Error: -w requires a directory argument. >&2
        exit /b 1
    )
    set "WORKDIR=%~f2"
    shift
    shift
    goto parse_args
)

if /i "%~1"=="--workdir" (
    if "%~2"=="" (
        echo Error: --workdir requires a directory argument. >&2
        exit /b 1
    )
    set "WORKDIR=%~f2"
    shift
    shift
    goto parse_args
)

if /i "%~1"=="-p" (
    set "FORCE_PULL=1"
    shift
    goto parse_args
)
if /i "%~1"=="--pull" (
    set "FORCE_PULL=1"
    shift
    goto parse_args
)

if /i "%~1"=="-b" (
    set "FORCE_BUILD=1"
    shift
    goto parse_args
)
if /i "%~1"=="--build" (
    set "FORCE_BUILD=1"
    shift
    goto parse_args
)

if /i "%~1"=="-i" (
    if "%~2"=="" (
        echo Error: -i requires an image name. >&2
        exit /b 1
    )
    set "IMAGE_NAME=%~2"
    shift
    shift
    goto parse_args
)
if /i "%~1"=="--image" (
    if "%~2"=="" (
        echo Error: --image requires an image name. >&2
        exit /b 1
    )
    set "IMAGE_NAME=%~2"
    shift
    shift
    goto parse_args
)

if "%~1"=="--" (
    shift
    goto gather_remaining
)

:: Any other arguments are passed through to pi
set "EXTRA_ARGS=!EXTRA_ARGS! %1"
shift
goto parse_args

:gather_remaining
if "%~1"=="" goto end_args
set "EXTRA_ARGS=!EXTRA_ARGS! %1"
shift
goto gather_remaining

:end_args

:: Detect container engine (docker or podman)
set "CONTAINER_BIN="
if defined CONTAINER_ENGINE (
    set "CONTAINER_BIN=%CONTAINER_ENGINE%"
) else (
    where docker >nul 2>&1
    if !errorlevel! equ 0 (
        set "CONTAINER_BIN=docker"
    ) else (
        where podman >nul 2>&1
        if !errorlevel! equ 0 (
            set "CONTAINER_BIN=podman"
        )
    )
)

if not defined CONTAINER_BIN (
    echo Error: Neither 'docker' nor 'podman' found in PATH. Please install one of them. >&2
    exit /b 1
)

:: Ensure persistent scope directories exist
set "PI_AGENT_DIR=%WORKDIR%\pi-agent"
set "WORKSPACE_DIR=%WORKDIR%\workspace"

if not exist "%PI_AGENT_DIR%" mkdir "%PI_AGENT_DIR%"
if not exist "%WORKSPACE_DIR%" mkdir "%WORKSPACE_DIR%"

:: Check if image exists locally
set "IMAGE_EXISTS=0"
%CONTAINER_BIN% image inspect "%IMAGE_NAME%" >nul 2>&1
if !errorlevel! equ 0 set "IMAGE_EXISTS=1"

:: Build, pull, or auto-fetch image
if "%FORCE_BUILD%"=="1" (
    echo Building container image '%IMAGE_NAME%' from '%SCRIPT_DIR%'...
    %CONTAINER_BIN% build -t "%IMAGE_NAME%" -f "%SCRIPT_DIR%Dockerfile" "%SCRIPT_DIR%"
    if !errorlevel! neq 0 (
        echo Error: Failed to build image '%IMAGE_NAME%'. >&2
        exit /b !errorlevel!
    )
) else if "%FORCE_PULL%"=="1" (
    echo Pulling latest container image '%IMAGE_NAME%' from registry...
    %CONTAINER_BIN% pull "%IMAGE_NAME%"
    if !errorlevel! neq 0 (
        echo Error: Failed to pull image '%IMAGE_NAME%'. >&2
        exit /b !errorlevel!
    )
) else if "%IMAGE_EXISTS%"=="0" (
    echo Image '%IMAGE_NAME%' not found locally. Pulling from registry...
    %CONTAINER_BIN% pull "%IMAGE_NAME%"
    if !errorlevel! neq 0 (
        echo Error: Failed to pull image '%IMAGE_NAME%' from registry. >&2
        if exist "%SCRIPT_DIR%Dockerfile" (
            echo Tip: You can build it locally using: pi-box.cmd --build >&2
        )
        exit /b !errorlevel!
    )
)

:: Prepare environment variables
set "ENV_FLAGS=-e HOST_UID=1000 -e HOST_GID=1000 -e TERM=xterm-256color"

if exist "%WORKDIR%\.env" (
    set "ENV_FLAGS=!ENV_FLAGS! --env-file \"%WORKDIR%\.env\""
) else if exist "%SCRIPT_DIR%.env" (
    set "ENV_FLAGS=!ENV_FLAGS! --env-file "%SCRIPT_DIR%.env""
)

if defined ANTHROPIC_API_KEY set "ENV_FLAGS=!ENV_FLAGS! -e ANTHROPIC_API_KEY"
if defined OPENAI_API_KEY set "ENV_FLAGS=!ENV_FLAGS! -e OPENAI_API_KEY"
if defined GEMINI_API_KEY set "ENV_FLAGS=!ENV_FLAGS! -e GEMINI_API_KEY"
if defined OPENROUTER_API_KEY set "ENV_FLAGS=!ENV_FLAGS! -e OPENROUTER_API_KEY"
if defined GROQ_API_KEY set "ENV_FLAGS=!ENV_FLAGS! -e GROQ_API_KEY"
if defined MISTRAL_API_KEY set "ENV_FLAGS=!ENV_FLAGS! -e MISTRAL_API_KEY"

:: Determine container command arguments
set "CMD_ARGS="
if defined EXTRA_ARGS (
    for /f "tokens=1*" %%a in ("!EXTRA_ARGS!") do (
        set "FIRST_TOKEN=%%a"
        if /i "!FIRST_TOKEN!"=="bash" (
            set "CMD_ARGS=!EXTRA_ARGS!"
        ) else if /i "!FIRST_TOKEN!"=="sh" (
            set "CMD_ARGS=!EXTRA_ARGS!"
        ) else if /i "!FIRST_TOKEN!"=="pi" (
            set "CMD_ARGS=!EXTRA_ARGS!"
        ) else (
            set "CMD_ARGS=pi !EXTRA_ARGS!"
        )
    )
)

:: Run interactive container
%CONTAINER_BIN% run --rm -it --init ^
    !ENV_FLAGS! ^
    -v "%PI_AGENT_DIR%:/home/node/.pi" ^
    -v "%WORKSPACE_DIR%:/home/node/workspace" ^
    --workdir /home/node/workspace ^
    "%IMAGE_NAME%" ^
    !CMD_ARGS!

exit /b %errorlevel%

:show_help
echo Usage: pi-box.cmd [OPTIONS] [-- ADDITIONAL_ARGS...]
echo.
echo Run the pi coding agent inside an isolated Debian container with transparent
echo host user file permissions and persistent state.
echo.
echo Options:
echo   -w, --workdir ^<DIR^>    Set persistent directory scope containing "pi-agent" and "workspace"
echo                          (default: current working directory)
echo   -p, --pull              Pull the latest container image from registry
echo   -b, --build             Build container image locally from Dockerfile
echo   -i, --image ^<NAME^>     Custom container image name (default: ghcr.io/breeze833/pi-box:latest)
echo   -h, --help              Show this help message and exit
echo.
echo Environment Variables:
echo   CONTAINER_ENGINE        Specify container runtime binary (docker or podman)
echo   PI_BOX_IMAGE            Override default image name
echo   ANTHROPIC_API_KEY       Forwarded automatically if set
echo   OPENAI_API_KEY          Forwarded automatically if set
echo   GEMINI_API_KEY          Forwarded automatically if set
echo   OPENROUTER_API_KEY      Forwarded automatically if set
exit /b 0
