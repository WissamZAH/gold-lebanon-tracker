"""
fetch_gold.py — STEP 1 of the Lebanon Gold Tracker
====================================================
Fetches the live gold spot price (USD per troy ounce) from Yahoo Finance,
converts it into per-gram prices for 24K / 21K / 18K gold the way the
Lebanese market quotes them (USD per gram + LBP equivalent), and writes
everything to gold_lebanon_data.json.

The JSON keeps a rolling daily history so that:
  - Step 2 (ML signal) has past data to learn from
  - Step 5 (Flutter charts) has a time series to draw

Run it manually with:  python fetch_gold.py
Later, GitHub Actions will run it for us every day (Step 3).
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
USD_TO_LBP = 89_500             # Lebanese pound rate (stable since Feb 2023) — update here if it changes

# Karat purity fractions: 24K is pure gold, 21K is 21/24 pure, 18K is 18/24 pure.
PURITIES = {
    "24k": 24 / 24,
    "21k": 21 / 24,
    "18k": 18 / 24,
}

OUTPUT_FILE = "gold_lebanon_data.json"
MAX_HISTORY_DAYS = 365          # keep at most one year of daily records


# ---------------------------------------------------------------------------
# 1. EXTRACT — pull the live spot price
# ---------------------------------------------------------------------------

def fetch_spot_price_usd() -> float:
    """Return the most recent gold close price in USD per troy ounce."""
    ticker = yf.Ticker(GOLD_TICKER)
    # Ask for the last 5 days so weekends/holidays (no trading) still give us
    # at least one valid row to fall back on.
    frame = ticker.history(period="5d", interval="1d")

    if frame.empty:
        raise RuntimeError(
            f"Yahoo Finance returned no data for {GOLD_TICKER}. "
            "Check your internet connection or try again in a minute."
        )

    spot = float(frame["Close"].iloc[-1])
    if spot <= 0:
        raise RuntimeError(f"Got an invalid spot price: {spot}")
    return spot


# ---------------------------------------------------------------------------
# 2. TRANSFORM — convert ounce price into Lebanese-market gram prices
# ---------------------------------------------------------------------------

def build_price_table(spot_usd_per_ounce: float) -> dict:
    """Convert USD/ounce into per-gram prices for each karat, in USD and LBP."""
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
    """Assemble today's full data record."""
    now_utc = datetime.now(timezone.utc)
    return {
        "last_updated_utc": now_utc.isoformat(timespec="seconds"),
        "source": GOLD_TICKER,
        "exchange_rate_usd_to_lbp": USD_TO_LBP,
        "spot_usd_per_ounce": round(spot_usd_per_ounce, 2),
        "prices_per_gram": build_price_table(spot_usd_per_ounce),
    }


# ---------------------------------------------------------------------------
# 3. LOAD — merge with existing history and write the JSON file
# ---------------------------------------------------------------------------

def load_existing_data() -> dict:
    """Read the previous JSON file if it exists, otherwise start fresh."""
    if not os.path.exists(OUTPUT_FILE):
        return {"history": []}
    try:
        with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        data.setdefault("history", [])
        return data
    except (json.JSONDecodeError, OSError):
        # Corrupt or unreadable file — safer to rebuild than to crash daily.
        print("Warning: existing JSON was unreadable, starting a fresh history.")
        return {"history": []}


def update_history(history: list, snapshot: dict) -> list:
    """Append today's record, replacing any earlier record from the same date."""
    today = snapshot["last_updated_utc"][:10]  # "YYYY-MM-DD"

    entry = {
        "date": today,
        "spot_usd_per_ounce": snapshot["spot_usd_per_ounce"],
        "usd_per_gram_24k": snapshot["prices_per_gram"]["24k"]["usd_per_gram"],
    }

    # If the script runs twice in one day, overwrite instead of duplicating.
    history = [h for h in history if h.get("date") != today]
    history.append(entry)
    history.sort(key=lambda h: h["date"])

    return history[-MAX_HISTORY_DAYS:]


def main() -> int:
    print(f"Fetching gold spot price from Yahoo Finance ({GOLD_TICKER})...")
    spot = fetch_spot_price_usd()
    print(f"  Spot price: ${spot:,.2f} per troy ounce")

    snapshot = build_snapshot(spot)
    data = load_existing_data()

    # Today's full snapshot lives at the top level; the compact daily series
    # lives under "history".
    data.update(snapshot)
    data["history"] = update_history(data["history"], snapshot)

    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

    p = snapshot["prices_per_gram"]
    print(f"  24K: ${p['24k']['usd_per_gram']}/g  |  {p['24k']['lbp_per_gram']:,} LBP/g")
    print(f"  21K: ${p['21k']['usd_per_gram']}/g  |  {p['21k']['lbp_per_gram']:,} LBP/g")
    print(f"  18K: ${p['18k']['usd_per_gram']}/g  |  {p['18k']['lbp_per_gram']:,} LBP/g")
    print(f"Wrote {OUTPUT_FILE} with {len(data['history'])} day(s) of history. Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
