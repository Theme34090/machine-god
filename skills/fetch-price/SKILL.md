---
name: fetch-price
description: Fetch real-time asset price data for US, Japanese, Korean equities and crypto
---

# fetch-price

Fetches current price, change, and basic stats for any ticker supported by Yahoo Finance. Covers US equities, Japanese equities (.T suffix), Korean equities (.KS/.KQ suffix), and crypto (e.g. BTC-USD).

## Usage

```bash
uv run --with yfinance skills/fetch-price/scripts/fetch.py <symbol>
```

## Input

- **Arg 1:** Yahoo Finance ticker symbol (e.g. `AAPL`, `7203.T`, `005930.KS`, `BTC-USD`)
- **Env:** None required

## Output

JSON to stdout:

```json
{
  "symbol": "7203.T",
  "name": "Toyota Motor Corporation",
  "price": 3730.0,
  "currency": "JPY",
  "change_percent": 0.62,
  "high": 3769.0,
  "low": 3719.0,
  "volume": 15050800,
  "price_usd": 24.16,
  "high_usd": 24.41,
  "low_usd": 24.09,
  "url": "https://finance.yahoo.com/quote/7203.T"
}
```

**Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `symbol` | string | Ticker symbol |
| `name` | string | Company/asset name |
| `price` | number | Current price in local currency |
| `currency` | string | ISO currency code (USD, JPY, KRW, etc.) |
| `change_percent` | number \| null | Percent change from previous close |
| `high` | number \| null | Day high in local currency |
| `low` | number \| null | Day low in local currency |
| `volume` | number \| null | Trading volume in shares |
| `price_usd` | number \| null | Price converted to USD (non-USD assets only) |
| `high_usd` | number \| null | Day high converted to USD (non-USD assets only) |
| `low_usd` | number \| null | Day low converted to USD (non-USD assets only) |
| `url` | string | Yahoo Finance quote page |

Non-zero exit on error, message on stderr.
