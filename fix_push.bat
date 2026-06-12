@echo off
REM Clears the old saved GitHub token and pushes again.
REM When prompted: username = WissamZAH, password = your NEW token.
cd /d "%~dp0"

echo Removing the old saved GitHub credential...
cmdkey /delete:git:https://github.com >nul 2>&1
cmdkey /delete:LegacyGeneric:target=git:https://github.com >nul 2>&1

echo.
echo Pushing to GitHub (paste your NEW token when asked for a password)...
git push -u origin main
if errorlevel 1 (
    echo.
    echo Push failed again - make sure the new token has BOTH "repo" and "workflow" scopes.
    pause
    exit /b 1
)

echo.
echo Success! Check: https://github.com/WissamZAH/gold-lebanon-tracker
pause
