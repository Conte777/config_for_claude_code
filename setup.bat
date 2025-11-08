@echo off
setlocal enabledelayedexpansion

:: Проверка прав администратора
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ERROR: This script requires administrator privileges.
    echo Please run as administrator.
    pause
    exit /b 1
)

:: Получение пути к директории скрипта
set "REPO_DIR=%~dp0"
set "SRC_DIR=%REPO_DIR%src"

echo ============================================
echo Claude Code Configuration Setup
echo ============================================
echo.
echo Repository path: %REPO_DIR%
echo.

:: Целевые пути
set "TARGET_CLAUDE_DIR=%USERPROFILE%\.claude"
set "TARGET_SETTINGS=%TARGET_CLAUDE_DIR%\settings.json"
set "TARGET_CLAUDE_MD=%TARGET_CLAUDE_DIR%\CLAUDE.md"
set "TARGET_COMMANDS=%TARGET_CLAUDE_DIR%\commands"
set "TARGET_AGENTS=%TARGET_CLAUDE_DIR%\agents"
set "TARGET_SKILLS=%TARGET_CLAUDE_DIR%\skills"

:: Проверка существующих файлов и директорий
set "CONFLICT=0"

if exist "%TARGET_SETTINGS%" (
    echo WARNING: File already exists: %TARGET_SETTINGS%
    set "CONFLICT=1"
)

if exist "%TARGET_CLAUDE_MD%" (
    echo WARNING: File already exists: %TARGET_CLAUDE_MD%
    set "CONFLICT=1"
)

if exist "%TARGET_COMMANDS%" (
    echo WARNING: Directory already exists: %TARGET_COMMANDS%
    set "CONFLICT=1"
)

if exist "%TARGET_AGENTS%" (
    echo WARNING: Directory already exists: %TARGET_AGENTS%
    set "CONFLICT=1"
)

if exist "%TARGET_SKILLS%" (
    echo WARNING: Directory already exists: %TARGET_SKILLS%
    set "CONFLICT=1"
)

if !CONFLICT! equ 1 (
    echo.
    echo ERROR: One or more target files/directories already exist.
    echo Please manually backup or remove existing files before running this script.
    echo.
    echo You can use cleanup.bat to remove symbolic links if they were created by this script.
    pause
    exit /b 1
)

:: Создание директории .claude если не существует
if not exist "%TARGET_CLAUDE_DIR%" (
    echo Creating directory: %TARGET_CLAUDE_DIR%
    mkdir "%TARGET_CLAUDE_DIR%"
)

:: Проверка наличия исходных файлов
echo.
echo Checking source files...
echo.
set "SOURCE_MISSING=0"

if not exist "%SRC_DIR%\settings.json" (
    echo ERROR: Source file not found: %SRC_DIR%\settings.json
    set "SOURCE_MISSING=1"
)

if not exist "%SRC_DIR%\CLAUDE.md" (
    echo ERROR: Source file not found: %SRC_DIR%\CLAUDE.md
    set "SOURCE_MISSING=1"
)

if not exist "%SRC_DIR%\commands" (
    echo ERROR: Source directory not found: %SRC_DIR%\commands
    set "SOURCE_MISSING=1"
)

if not exist "%SRC_DIR%\agents" (
    echo ERROR: Source directory not found: %SRC_DIR%\agents
    set "SOURCE_MISSING=1"
)

if not exist "%SRC_DIR%\skills" (
    echo ERROR: Source directory not found: %SRC_DIR%\skills
    set "SOURCE_MISSING=1"
)

if !SOURCE_MISSING! equ 1 (
    echo.
    echo ERROR: One or more source files/directories are missing.
    echo Please ensure all required files exist in: %SRC_DIR%
    echo.
    pause
    exit /b 1
)

echo All source files found.

:: Создание символических ссылок
echo.
echo Creating symbolic links...
echo.

:: Символическая ссылка для settings.json (файл)
echo Creating: %TARGET_SETTINGS% -^> %SRC_DIR%\settings.json
mklink "%TARGET_SETTINGS%" "%SRC_DIR%\settings.json"
if %errorlevel% neq 0 (
    echo ERROR: Failed to create symlink for settings.json
    goto :cleanup_on_error
)

:: Символическая ссылка для CLAUDE.md (файл)
echo Creating: %TARGET_CLAUDE_MD% -^> %SRC_DIR%\CLAUDE.md
mklink "%TARGET_CLAUDE_MD%" "%SRC_DIR%\CLAUDE.md"
if %errorlevel% neq 0 (
    echo ERROR: Failed to create symlink for CLAUDE.md
    goto :cleanup_on_error
)

:: Символическая ссылка для commands (директория)
echo Creating: %TARGET_COMMANDS% -^> %SRC_DIR%\commands
mklink /D "%TARGET_COMMANDS%" "%SRC_DIR%\commands"
if %errorlevel% neq 0 (
    echo ERROR: Failed to create symlink for commands directory
    goto :cleanup_on_error
)

:: Символическая ссылка для agents (директория)
echo Creating: %TARGET_AGENTS% -^> %SRC_DIR%\agents
mklink /D "%TARGET_AGENTS%" "%SRC_DIR%\agents"
if %errorlevel% neq 0 (
    echo ERROR: Failed to create symlink for agents directory
    goto :cleanup_on_error
)

:: Символическая ссылка для skills (директория)
echo Creating: %TARGET_SKILLS% -^> %SRC_DIR%\skills
mklink /D "%TARGET_SKILLS%" "%SRC_DIR%\skills"
if %errorlevel% neq 0 (
    echo ERROR: Failed to create symlink for skills directory
    goto :cleanup_on_error
)

echo.
echo ============================================
echo SUCCESS: All symbolic links created successfully!
echo ============================================
echo.
echo Claude Code will now use configuration from:
echo %REPO_DIR%
echo.
pause
exit /b 0

:cleanup_on_error
echo.
echo Cleaning up partial installation...
if exist "%TARGET_SETTINGS%" del "%TARGET_SETTINGS%" 2>nul
if exist "%TARGET_CLAUDE_MD%" del "%TARGET_CLAUDE_MD%" 2>nul
if exist "%TARGET_COMMANDS%" rmdir "%TARGET_COMMANDS%" 2>nul
if exist "%TARGET_AGENTS%" rmdir "%TARGET_AGENTS%" 2>nul
if exist "%TARGET_SKILLS%" rmdir "%TARGET_SKILLS%" 2>nul
echo.
echo Setup failed. Please check the error messages above.
pause
exit /b 1
