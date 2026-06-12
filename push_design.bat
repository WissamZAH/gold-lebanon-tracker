@echo off
REM Commits and pushes the Step 6 dashboard redesign.
cd /d "%~dp0"

git add gold_dashboard README.md push_design.bat setup_vscode.bat fix_push.bat install_flutter.ps1 setup_environment.bat vscode_settings.json vscode_launch.json
git commit -m "Step 6: professional animated dashboard - living gold-dust background that follows the trend signal, cursor-reactive particles, glow orbs, shimmer title, LIVE badge, stats strip, count-up prices, hover-glow cards, auto-refresh"
git push

if errorlevel 1 (
    echo Push failed - check your internet or token, then run this again.
    pause
    exit /b 1
)
echo.
echo Pushed! See it at https://github.com/WissamZAH/gold-lebanon-tracker
pause
