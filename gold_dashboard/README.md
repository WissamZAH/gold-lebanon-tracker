# Gold Dashboard (Flutter) — Steps 4 & 5

Flutter web/mobile dashboard for the Lebanon Gold Tracker. Reads
`gold_lebanon_data.json` directly from the GitHub raw URL — no backend.

## First-time setup

The repo keeps only the portable source (`lib/`, `pubspec.yaml`). Generate the
platform scaffolding once on your machine:

```cmd
cd gold_dashboard
flutter create . --platforms web,android
flutter pub get
```

## Run

```cmd
flutter run -d chrome      # web
flutter run                # connected Android device/emulator
```

## What's inside

- **Step 4 (data layer):** `fetchGoldData()` in `lib/main.dart` GETs the raw
  JSON from GitHub and parses prices, history, and the prediction block.
- **Step 5 (UI):** glassmorphism `GlassCard`s (blur + translucency), animated
  trend arrow with confidence bar, 24K/21K/18K price cards in USD + LBP,
  historical spot-price line chart (fl_chart), responsive layout
  (row of cards on desktop, stacked on mobile), pull-to-refresh.
