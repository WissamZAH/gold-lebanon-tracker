@echo off
REM Sets up VS Code for this Flutter project:
REM installs extensions + copies workspace settings, then opens the project.
REM Run AFTER VS Code is installed (https://code.visualstudio.com).
cd /d "%~dp0"

where code >nul 2>&1
if errorlevel 1 (
    echo VS Code's "code" command was not found.
    echo 1. Install VS Code from https://code.visualstudio.com
    echo 2. During install, keep "Add to PATH" checked.
    echo 3. Re-run this script.
    pause
    exit /b 1
)

echo Installing extensions...
call code --install-extension Dart-Code.dart-code
call code --install-extension Dart-Code.flutter
call code --install-extension usernamehw.errorlens
call code --install-extension eamodio.gitlens
call code --install-extension PKief.material-icon-theme

echo.
echo Copying workspace settings (Flutter SDK path, launch config)...
if not exist "gold_dashboard\.vscode" mkdir "gold_dashboard\.vscode"
copy /Y vscode_settings.json "gold_dashboard\.vscode\settings.json" >nul
copy /Y vscode_launch.json "gold_dashboard\.vscode\launch.json" >nul

echo.
echo Done! Opening the dashboard project in VS Code...
code "%~dp0gold_dashboard"
pause
