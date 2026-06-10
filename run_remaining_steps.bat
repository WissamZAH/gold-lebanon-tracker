@echo off
REM ============================================================
REM  Lebanon Gold Tracker - Steps 2-5 runner
REM  Runs the upgraded script, then commits each step to GitHub
REM  (one commit per step, each message marking the feature).
REM ============================================================
cd /d "%~dp0"

echo.
echo [1/6] Activating venv and installing dependencies...
call venv\Scripts\activate.bat
pip install -r requirements.txt -q

echo.
echo [2/6] Running fetch_gold.py (Step 2: backfill + trend signal)...
del gold_lebanon_data.json 2>nul
python fetch_gold.py
if errorlevel 1 (
    echo ERROR: fetch_gold.py failed. Fix the error above and re-run.
    pause
    exit /b 1
)

echo.
echo [3/6] Linking this folder to the GitHub repo...
if not exist .git (
    git init
    git branch -M main
    git remote add origin https://github.com/WissamZAH/gold-lebanon-tracker.git
    git fetch origin
    git reset --mixed origin/main
)

REM Make sure git knows who you are (needed for commits)
git config user.email >nul 2>&1 || git config --global user.email "masrimoemen2004@gmail.com"
git config user.name  >nul 2>&1 || git config --global user.name "WissamZAH"

echo.
echo [4/6] Committing each step...
git add fetch_gold.py gold_lebanon_data.json
git commit -m "Step 2: ML trend prediction signal (SMA crossover + slope) with 6-month history backfill"

git add .github/workflows/update_gold.yml
git commit -m "Step 3: GitHub Actions workflow - runs fetch_gold.py daily at 06:00 UTC and auto-commits fresh JSON"

git add gold_dashboard/pubspec.yaml gold_dashboard/.gitignore gold_dashboard/analysis_options.yaml gold_dashboard/README.md
git commit -m "Step 4: Flutter project init - data layer reading the raw GitHub JSON URL"

git add gold_dashboard/lib/main.dart
git commit -m "Step 5: Flutter glassmorphism dashboard - trend arrow, USD/LBP karat cards, history chart, responsive layout"

git add README.md
git commit -m "docs: README marking all 5 steps and what each feature does"

git add run_remaining_steps.bat
git commit -m "chore: add steps 2-5 runner script"

echo.
echo [5/6] Pushing to GitHub...
git push -u origin main
if errorlevel 1 (
    echo.
    echo Push failed. If asked for a password, use a Personal Access Token.
    pause
    exit /b 1
)

echo.
echo [6/6] Done! Verify here:
echo   https://github.com/WissamZAH/gold-lebanon-tracker
echo   https://raw.githubusercontent.com/WissamZAH/gold-lebanon-tracker/main/gold_lebanon_data.json
echo.
echo Then enable the daily workflow: GitHub repo -^> Actions tab -^> enable workflows,
echo and test it with the "Run workflow" button on "Update Gold Data".
pause
