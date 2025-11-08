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

echo ============================================
echo Claude Code Configuration Cleanup
echo ============================================
echo.
echo This script will remove symbolic links created by setup.bat
echo.

:: Целевые пути
set "TARGET_SETTINGS=%USERPROFILE%\.claude\settings.json"
set "TARGET_CLAUDE_MD=%USERPROFILE%\.claude\CLAUDE.md"
set "TARGET_COMMANDS=%USERPROFILE%\.claude\commands"
set "TARGET_AGENTS=%USERPROFILE%\.claude\agents"
set "TARGET_SKILLS=%USERPROFILE%\.claude\skills"

:: Подтверждение от пользователя
echo The following symbolic links will be removed:
echo - %TARGET_SETTINGS%
echo - %TARGET_CLAUDE_MD%
echo - %TARGET_COMMANDS%
echo - %TARGET_AGENTS%
echo - %TARGET_SKILLS%
echo.
set /p "CONFIRM=Are you sure you want to continue? (Y/N): "

if /i not "!CONFIRM!"=="Y" (
    echo.
    echo Operation cancelled.
    pause
    exit /b 0
)

echo.
echo Removing symbolic links...
echo.

set "ERROR_COUNT=0"

:: Удаление символической ссылки для settings.json
if exist "%TARGET_SETTINGS%" (
    echo Removing: %TARGET_SETTINGS%
    del "%TARGET_SETTINGS%" 2>nul
    if %errorlevel% neq 0 (
        echo WARNING: Failed to remove %TARGET_SETTINGS%
        set /a ERROR_COUNT+=1
    ) else (
        echo   - Removed successfully
    )
) else (
    echo Skipping: %TARGET_SETTINGS% (not found)
)

:: Удаление символической ссылки для CLAUDE.md
if exist "%TARGET_CLAUDE_MD%" (
    echo Removing: %TARGET_CLAUDE_MD%
    del "%TARGET_CLAUDE_MD%" 2>nul
    if %errorlevel% neq 0 (
        echo WARNING: Failed to remove %TARGET_CLAUDE_MD%
        set /a ERROR_COUNT+=1
    ) else (
        echo   - Removed successfully
    )
) else (
    echo Skipping: %TARGET_CLAUDE_MD% (not found)
)

:: Удаление символической ссылки для commands (директория)
if exist "%TARGET_COMMANDS%" (
    echo Removing: %TARGET_COMMANDS%
    rmdir "%TARGET_COMMANDS%" 2>nul
    if %errorlevel% neq 0 (
        echo WARNING: Failed to remove %TARGET_COMMANDS%
        set /a ERROR_COUNT+=1
    ) else (
        echo   - Removed successfully
    )
) else (
    echo Skipping: %TARGET_COMMANDS% (not found)
)

:: Удаление символической ссылки для agents (директория)
if exist "%TARGET_AGENTS%" (
    echo Removing: %TARGET_AGENTS%
    rmdir "%TARGET_AGENTS%" 2>nul
    if %errorlevel% neq 0 (
        echo WARNING: Failed to remove %TARGET_AGENTS%
        set /a ERROR_COUNT+=1
    ) else (
        echo   - Removed successfully
    )
) else (
    echo Skipping: %TARGET_AGENTS% (not found)
)

:: Удаление символической ссылки для skills (директория)
if exist "%TARGET_SKILLS%" (
    echo Removing: %TARGET_SKILLS%
    rmdir "%TARGET_SKILLS%" 2>nul
    if %errorlevel% neq 0 (
        echo WARNING: Failed to remove %TARGET_SKILLS%
        set /a ERROR_COUNT+=1
    ) else (
        echo   - Removed successfully
    )
) else (
    echo Skipping: %TARGET_SKILLS% (not found)
)

echo.
echo ============================================

if !ERROR_COUNT! equ 0 (
    echo SUCCESS: All symbolic links removed successfully!
) else (
    echo COMPLETED WITH WARNINGS: !ERROR_COUNT! item(s) could not be removed.
    echo Please check the messages above and remove them manually if needed.
)

echo ============================================
echo.
echo NOTE: The .claude directory itself was not removed.
echo If you want to remove it completely, delete it manually:
echo %USERPROFILE%\.claude
echo.
pause
exit /b 0
