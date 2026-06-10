"""
fetch_gold.py — STEPS 1 + 2 of the Lebanon Gold Tracker
========================================================
STEP 1 (ETL): Fetches the live gold spot price (USD per troy ounce) from
Yahoo Finance, converts it into per-gram prices for 24K / 21K / 18K gold
the way the Lebanese market quotes them (USD per gram + LBP equivalent),
and writes everything to gold_lebanon_data.json with a rolling daily history.

STEP 2 (ML signal): Backfills ~6 months of past daily prices, then computes
an UP / DOWN / NEUTRAL trend signal from two classic techniques:
  - SMA crossover: 5-day average vs 20-day average
  - Trend slope: least-squares line through the last 10 days
This is a trend-following heuristic — present it as a "market trend signal",
never as financial advice.

Run it manually with:  python fetch_gold.py
GitHub Actions runs it for us every day (Step 3).
"""

import json
import os
import sys
from datetime import datetime, timezone

import yfinance as yf

# ---------------------------------------------------------------------------
# Configuration — the only lines you should ever need to touch
# ---------------------------------------------------------------------------

GOLD_TICKER = "GC=F"            # COMEX Gold Futures: the standard live proxy for spot
TROY_OUNCE_TO_GRAM = 31.1034768 # exact conversion constant
USD_TO_LBP = 89_500             # Lebanese pound rate (stable since Feb 2023)

# Karat purity fractions: 24K is pure gold, 21K is 21/24 pure, 18K is 18/24 pure.
PURITIES = {
    "24k": 24 / 24,
    "21k": 21 / 24,
    "18k": 18 / 24,
}

OUTPUT_FILE = "gold_lebanon_data.json"
MAX_HISTORY_DAYS = 365          # keep at most one year of daily records

# --- Step 2 model parameters ---
SMA_SHORT = 5                   # short moving-average window (days)
SMA_LONG = 20                   # long moving-average window (days)
SLOPE_WINDOW = 10               # days used for trend-line fit
BACKFILL_PERIOD = "6mo"         # how much history to backfill on first run


# ---------------------------------------------------------------------------
# 1. EXTRACT — pull live spot price + historical daily closes
# ---------------------------------------------------------------------------

def fetch_price_frame():
    """Return a DataFrame of daily closes covering BACKFILL_PERIOD."""
    ticker = yf.Ticker(GOLD_TICKER)
    frame = ticker.history(period=BACKFILL_PERIOD, interval="1d")
    if frame.empty:
        raise RuntimeError(
            f"Yahoo Finance returned no data for {GOLD_TICKER}. "
            "Check your internet connection or try again in a minute."
        )
    return frame


def spot_from_frame(frame) -> float:
    """Most recent close in USD per troy ounce."""
    spot = float(frame["Close"].iloc[-1])
    if spot <= 0:
        raise RuntimeError(f"Got an invalid spot price: {spot}")
    return spot


# ---------------------------------------------------------------------------
# 2. TRANSFORM — convert to Lebanese-market per-gram prices
# ---------------------------------------------------------------------------

def build_price_table(spot_usd_per_ounce: float) -> dict:
    gram_24k_usd = spot_usd_per_ounce / TROY_OUNCE_TO_GRAM
    prices = {}
    for karat, purity in PURITIES.items():
        usd_per_gram = round(gram_24k_usd * purity, 2)
        prices[karat] = {
            "usd_per_gram": usd_per_gram,
            "lbp_per_gram": round(usd_per_gram * USD_TO_LBP),
        }
    return prices


def build_snapshot(spot_usd_per_ounce: float) -> dict:
    now_utc = datetime.now(timezone.utc)
    return {
        "last_updated_utc": now_utc.isoformat(timespec="seconds"),
        "source": GOLD_TICKER,
        "exchange_rate_usd_to_lbp": USD_TO_LBP,
        "spot_usd_per_ounce": round(spot_usd_per_ounce, 2),
        "prices_per_gram": build_price_table(spot_usd_per_ounce),
    }


# ---------------------------------------------------------------------------
# 3. HISTORY — backfill + merge today's entry
# ---------------------------------------------------------------------------

def load_existing_data() -> dict:
    if not os.path.exists(OUTPUT_FILE):
        return {"history": []}
    try:
        with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        data.setdefault("history", [])
        return data
    except (json.JSONDecodeError, OSError):
        print("Warning: existing JSON was unreadable, starting fresh.")
        return {"history": []}


def backfill_history(frame, history: list) -> list:
    """Merge ~6 months of Yahoo daily closes into history (no duplicates)."""
    known_dates = {h["date"] for h in history}
    for ts, row in frame.iterrows():
        date = ts.strftime("%Y-%m-%d")
        if date in known_dates:
            continue
        spot = float(row["Close"])
        if spot <= 0:
            continue
        history.append({
            "date": date,
            "spot_usd_per_ounce": round(spot, 2),
            "usd_per_gram_24k": round(spot / TROY_OUNCE_TO_GRAM, 2),
        })
        known_dates.add(date)
    history.sort(key=lambda h: h["date"])
    return history[-MAX_HISTORY_DAYS:]


def update_history(history: list, snapshot: dict) -> list:
    """Insert/replace today's entry from the live snapshot."""
    today = snapshot["last_updated_utc"][:10]
    entry = {
        "date": today,
        "spot_usd_per_ounce": snapshot["spot_usd_per_ounce"],
        "usd_per_gram_24k": snapshot["prices_per_gram"]["24k"]["usd_per_gram"],
    }
    history = [h for h in history if h.get("date") != today]
    history.append(entry)
    history.sort(key=lambda h: h["date"])
    return history[-MAX_HISTORY_DAYS:]


# ---------------------------------------------------------------------------
# 4. PREDICT — SMA crossover + trend slope  (STEP 2)
# ---------------------------------------------------------------------------

def sma(values: list, window: int) -> float:
    return sum(values[-window:]) / window


def trend_slope(values: list, window: int) -> float:
    """Least-squares slope (USD/day) of the last `window` values."""
    ys = values[-window:]
    n = len(ys)
    xs = list(range(n))
    mean_x = sum(xs) / n
    mean_y = sum(ys) / n
    num = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys))
    den = sum((x - mean_x) ** 2 for x in xs)
    return num / den if den else 0.0


def build_prediction(history: list) -> dict:
    closes = [h["spot_usd_per_ounce"] for h in history]

    if len(closes) < SMA_LONG + 1:
        return {
            "signal": "NEUTRAL",
            "confidence": 0.0,
            "reason": f"Not enough history ({len(closes)} days, need {SMA_LONG + 1}).",
            "sma_short": None,
            "sma_long": None,
            "slope_usd_per_day": None,
        }

    s_short = sma(closes, SMA_SHORT)
    s_long = sma(closes, SMA_LONG)
    slope = trend_slope(closes, SLOPE_WINDOW)

    sma_up = s_short > s_long
    slope_up = slope > 0

    # Confidence: how far apart the averages are, scaled (capped at 1.0)
    spread = abs(s_short - s_long) / s_long
    confidence = min(round(spread * 40, 2), 1.0)

    if sma_up and slope_up:
        signal, reason = "UP", "Short-term average above long-term and trend line rising."
    elif not sma_up and not slope_up:
        signal, reason = "DOWN", "Short-term average below long-term and trend line falling."
    else:
        signal = "NEUTRAL"
        reason = "Moving averages and trend slope disagree — no clear direction."
        confidence = round(confidence / 2, 2)

    return {
        "signal": signal,
        "confidence": confidence,
        "reason": reason,
        "sma_short": round(s_short, 2),
        "sma_long": round(s_long, 2),
        "slope_usd_per_day": round(slope, 3),
    }


# ---------------------------------------------------------------------------
# 5. LOAD — write the JSON "database"
# ---------------------------------------------------------------------------

def main() -> int:
    print(f"Fetching gold prices from Yahoo Finance ({GOLD_TICKER})...")
    frame = fetch_price_frame()
    spot = spot_from_frame(frame)
    print(f"  Spot price: ${spot:,.2f} per troy ounce")

    snapshot = build_snapshot(spot)
    data = load_existing_data()
    data.update(snapshot)
    data["history"] = backfill_history(frame, data["history"])
    data["history"] = update_history(data["history"], snapshot)
    data["prediction"] = build_prediction(data["history"])

    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    p = snapshot["prices_per_gram"]
    pred = data["prediction"]
    print(f"  24K: ${p['24k']['usd_per_gram']}/g  |  {p['24k']['lbp_per_gram']:,} LBP/g")
    print(f"  21K: ${p['21k']['usd_per_gram']}/g  |  {p['21k']['lbp_per_gram']:,} LBP/g")
    print(f"  18K: ${p['18k']['usd_per_gram']}/g  |  {p['18k']['lbp_per_gram']:,} LBP/g")
    print(f"  Signal: {pred['signal']} (confidence {pred['confidence']}) — {pred['reason']}")
    print(f"Wrote {OUTPUT_FILE} with {len(data['history'])} day(s) of history. Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
