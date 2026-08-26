#!/usr/bin/env python3
import json
import sys

import yfinance as yf

# Cache for exchange rates to avoid repeated fetches
FX_CACHE = {}


def get_usd_rate(currency):
    """Get conversion rate from currency to USD."""
    if currency == "USD":
        return 1.0
    if currency in FX_CACHE:
        return FX_CACHE[currency]

    try:
        # Yahoo Finance uses X suffix for forex pairs
        fx_ticker = yf.Ticker(f"{currency}USD=X")
        rate = fx_ticker.fast_info.last_price
        if rate:
            FX_CACHE[currency] = rate
            return rate
    except Exception:
        pass
    return None


def main():
    if len(sys.argv) < 2:
        print("usage: fetch.py <symbol>", file=sys.stderr)
        sys.exit(1)

    symbol = sys.argv[1].upper()
    ticker = yf.Ticker(symbol)

    try:
        fi = ticker.fast_info
        price = fi.last_price
        prev_close = fi.previous_close
        currency = (fi.currency or "USD").upper()
        day_high = fi.day_high
        day_low = fi.day_low
        volume = fi.last_volume
    except Exception as e:
        print(f"error fetching fast_info: {e}", file=sys.stderr)
        sys.exit(1)

    if price is None:
        print(f"no price data for {symbol}", file=sys.stderr)
        sys.exit(1)

    # name from info (slower but informative; fall back to symbol)
    name = symbol
    try:
        info = ticker.info
        name = info.get("longName") or info.get("shortName") or symbol
    except Exception:
        pass

    change_pct = None
    if prev_close:
        change_pct = (price - prev_close) / prev_close * 100

    # Convert to USD if different currency
    price_usd = None
    high_usd = None
    low_usd = None
    if currency != "USD":
        rate = get_usd_rate(currency)
        if rate:
            price_usd = price * rate
            high_usd = day_high * rate if day_high else None
            low_usd = day_low * rate if day_low else None

    result = {
        "symbol": symbol,
        "name": name,
        "price": round(price, 2),
        "currency": currency,
        "change_percent": round(change_pct, 2) if change_pct is not None else None,
        "high": round(day_high, 2) if day_high else None,
        "low": round(day_low, 2) if day_low else None,
        "volume": volume,
        "price_usd": round(price_usd, 2) if price_usd else None,
        "high_usd": round(high_usd, 2) if high_usd else None,
        "low_usd": round(low_usd, 2) if low_usd else None,
        "url": f"https://finance.yahoo.com/quote/{symbol}",
    }
    print(json.dumps(result))


if __name__ == "__main__":
    main()
