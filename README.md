# 🇱🇧 Lebanon Gold Tracker

Real-time gold price tracking and trend prediction for the Lebanese market.
**Python · GitHub Actions · Flutter** — zero servers, zero hosting costs.

**Live data:** `https://raw.githubusercontent.com/WissamZAH/gold-lebanon-tracker/main/gold_lebanon_data.json`

## How it works

A Python script runs daily on GitHub's servers, writes `gold_lebanon_data.json`
into this repo, and the Flutter app reads that raw URL directly. The repo is
the database.

## Features by step

### ✅ Step 1 — Python ETL (`fetch_gold.py`)
Fetches the live gold spot price (USD/troy oz) from Yahoo Finance (`GC=F`),
converts it to per-gram prices for 24K, 21K, and 18K purity, adds LBP
equivalents at the 89,500 rate, and writes `gold_lebanon_data.json` with a
rolling 365-day history (one entry per day, no duplicates).

### ✅ Step 2 — ML trend signal (`fetch_gold.py`)
Backfills ~6 months of daily prices, then computes an `UP` / `DOWN` /
`NEUTRAL` signal from two techniques: SMA crossover (5-day vs 20-day moving
average) and least-squares trend slope over the last 10 days. Agreement
between both = high-confidence signal; disagreement = NEUTRAL with halved
confidence. Output is added to the JSON as a `prediction` block.
*A trend-following heuristic — not financial advice.*

### ✅ Step 3 — Daily automation (`.github/workflows/update_gold.yml`)
GitHub Actions workflow that runs the script every day at 06:00 UTC
(09:00 Beirut), commits the refreshed JSON back to the repo, and can also be
triggered manually from the Actions tab. Free, no computer needed.

### ✅ Step 4 — Flutter data layer (`gold_dashboard/lib/main.dart`)
Flutter project that HTTP-GETs the raw GitHub JSON URL and parses prices,
history, and prediction into typed Dart models.

### ✅ Step 5 — Flutter dashboard (`gold_dashboard/`)
Glassmorphism cards (blur + translucency), animated trend arrow with a
confidence bar, 24K/21K/18K price cards in USD and LBP, historical
spot-price line chart, responsive desktop/mobile layout, pull-to-refresh.

## Run locally

```cmd
:: Python script
venv\Scripts\activate
pip install -r requirements.txt
python fetch_gold.py

:: Flutter dashboard (first time: flutter create . --platforms web,android)
cd gold_dashboard
flutter pub get
flutter run -d chrome
```

## Project structure

```
gold-lebanon-tracker/
├── .github/workflows/update_gold.yml   ← Step 3: daily automation
├── fetch_gold.py                       ← Steps 1+2: ETL + trend signal
├── requirements.txt
├── gold_lebanon_data.json              ← auto-generated "database"
└── gold_dashboard/                     ← Steps 4+5: Flutter app
    ├── pubspec.yaml
    └── lib/main.dart
```
