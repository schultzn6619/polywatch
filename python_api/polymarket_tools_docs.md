# polymarket_tools — Function Reference

## Overview

A toolkit for investigating Polymarket prediction markets. All functions make read-only calls to three public APIs:

| API | Base URL | Purpose |
|---|---|---|
| **Gamma** | `https://gamma-api.polymarket.com` | Market metadata, events, profiles, search |
| **CLOB** | `https://clob.polymarket.com` | Order book, price history |
| **Data** | `https://data-api.polymarket.com` | Trades, positions, holders, PnL |

---

## Key Identifiers

Understanding the difference between these is critical — they are not interchangeable.

| Identifier | Format | Example | Used by |
|---|---|---|---|
| **conditionId** | Hex string (`0x...`) | `0xa993...259f` | All statistical/trade functions, Data API `market` param |
| **questionId** | Large decimal number | `85191934...` | `get_market_by_question_id` only, Gamma `question_ids` param |
| **clobTokenId** | Large decimal number | `97390...008` | Order book, price history calls — one per outcome (YES/NO) |

`get_event_info` returns all three for every market. Use `conditionId` everywhere except `get_market_by_question_id`.

---

## Return Value Convention

Most functions return `(summary, raw)`:

- **`summary`** — a human-readable string ready to `print()`. Contains the key facts.
- **`raw`** — the full underlying data (list or dict) for further querying with the utility functions.

Functions that return only a string are noted individually.

---

## Function Reference

### ① Event Discovery

---

#### `get_event_info(slug)`

Fetches full event metadata by slug, including all nested markets. The starting point for any investigation — it gives you the `conditionId`, `questionId`, and `clobTokenIds` needed by every other function.

| Argument | Type | Required | Description |
|---|---|---|---|
| `slug` | str | ✓ | Event slug, e.g. `"us-x-iran-ceasefire-by"` |

**Returns:** `str` — event overview + one block per market showing all identifiers, prices, volume, and liquidity.

---

#### `search_events(query, limit=10)`

Full-text search across events, markets, and profiles. The only valid text-search endpoint in the Gamma API.

| Argument | Type | Required | Default | Description |
|---|---|---|---|---|
| `query` | str | ✓ | — | Search term (person, country, topic) |
| `limit` | int | | 10 | Max events returned |

**Returns:** `(summary, raw)` — summary lists matching events and tags; raw is `{ events[], tags[], profiles[], pagination }`.

---

#### `get_related_events(tag_slug, limit=10)`

Finds events sharing a specific tag slug. Useful for clustering related subjects.

| Argument | Type | Required | Default | Description |
|---|---|---|---|---|
| `tag_slug` | str | ✓ | — | Tag slug, e.g. `"iran"`, `"us-elections"` |
| `limit` | int | | 10 | Max events returned |

**Returns:** `(summary, raw)` — summary lists events with volume and liquidity; raw is a list of event objects.

---

### ② Market Analysis

---

#### `get_market_by_question_id(question_id)`

Fetches a specific market using its `questionId` (the large decimal number from `get_event_info`). Returns the market's `conditionId` and `clobTokenIds` needed for downstream functions.

| Argument | Type | Required | Description |
|---|---|---|---|
| `question_id` | str | ✓ | The decimal `questionId` from `get_event_info` output — NOT the hex conditionId |

**Returns:** `(summary, raw)` — summary shows all market fields including outcomes, prices, spread, volume; raw is the full market object.

---

#### `get_market_orderbook(clob_token_id)`

Fetches the live order book for one outcome token. A binary market has two tokens (YES and NO) — call once per outcome to compare both sides.

> **Note:** The `/book` endpoint closes when a market resolves. For closed markets, use `get_market_price_history` instead.

| Argument | Type | Required | Description |
|---|---|---|---|
| `clob_token_id` | str | ✓ | CLOB token ID for one outcome (from `get_event_info` `clobTokenIds`) |

**Returns:** `(summary, raw)` — summary shows best bid/ask, spread, top 5 bid/ask levels, and total depth; raw is `{ market, asset_id, bids[], asks[], last_trade_price }`.

---

#### `get_market_price_history(clob_token_id, interval="1w", fidelity=100)`

Historical price timeseries for one outcome token. Works for both open and closed markets — uses `/prices-history`, not `/book`.

| Argument | Type | Required | Default | Description |
|---|---|---|---|---|
| `clob_token_id` | str | ✓ | — | CLOB token ID for one outcome |
| `interval` | str | | `"1w"` | One of: `"1h"`, `"6h"`, `"1d"`, `"1w"`, `"1m"`, `"max"` |
| `fidelity` | int | | 100 | Resolution in minutes (lower = more granular) |

**Returns:** `(summary, raw)` — summary shows high/low/current price and trend direction; raw is `[ { "t": unix_ts, "p": price }, ... ]`.

---

#### `get_market_price_history_range(condition_id, start_ts, end_ts, outcome_index=0, fidelity=60)`

Historical price for a precise custom date range. Resolves the CLOB token internally from `conditionId`. Works on open and closed markets.

| Argument | Type | Required | Default | Description |
|---|---|---|---|---|
| `condition_id` | str | ✓ | — | Market conditionId (hex) |
| `start_ts` | float | ✓ | — | Window start as Unix timestamp |
| `end_ts` | float | ✓ | — | Window end as Unix timestamp |
| `outcome_index` | int | | 0 | 0 = first outcome (YES), 1 = second (NO) |
| `fidelity` | int | | 60 | Resolution in minutes |

**Returns:** `(summary, raw)` — summary shows open/close/high/low for the window; raw is the timeseries list.

---

### ③ Trade-Level Investigation

---

#### `get_market_trades(condition_id, limit=500, taker_only=False)`

All trades on a market. This is the primary data source for most trade-level analysis.

| Argument | Type | Required | Default | Description |
|---|---|---|---|---|
| `condition_id` | str | ✓ | — | Market conditionId (hex) |
| `limit` | int | | 500 | Max trades to fetch (Data API supports up to 10,000) |
| `taker_only` | bool | | False | If True, return only taker-side trades |

**Returns:** `(summary, raw)` — summary shows trade count, BUY/SELL split, unique wallets, top 5 wallets by volume; raw is the full trade list.

---

#### `get_large_trades(condition_id, min_size=1000.0, limit=500)`

Filters market trades above a size threshold. Surfaces whale activity without fetching a separate API call.

| Argument | Type | Required | Default | Description |
|---|---|---|---|---|
| `condition_id` | str | ✓ | — | Market conditionId (hex) |
| `min_size` | float | | 1000.0 | Minimum trade size in shares |
| `limit` | int | | 500 | Trades to pull before filtering |

**Returns:** `(summary, raw)` — summary shows large trade count, direction breakdown, top 10 large trades with timestamps and wallet; raw is filtered trade list sorted by size descending.

---

#### `get_pre_event_trades(condition_id, opening_hours=24.0, limit=1000)`

Returns trades from the first N hours of actual trading activity on the market. Anchors to the first recorded trade (not `startDate`), so it always contains data even when CLOB history begins days after market creation.

| Argument | Type | Required | Default | Description |
|---|---|---|---|---|
| `condition_id` | str | ✓ | — | Market conditionId (hex) |
| `opening_hours` | float | | 24.0 | Hours from first trade to include |
| `limit` | int | | 1000 | Max trades to pull |

**Returns:** `(summary, raw)` — summary shows count, BUY/SELL ratio, unique wallets, quartile timing distribution, top wallets by size; raw is filtered trades sorted by timestamp.

---

#### `get_pre_event_trades_at(condition_id, event_timestamp, lookback_hours=24.0, limit=1000)`

Returns trades in the N hours *before* a specific timestamp. Use for backward-looking analysis, e.g. trades before a known resolution or news event.

| Argument | Type | Required | Default | Description |
|---|---|---|---|---|
| `condition_id` | str | ✓ | — | Market conditionId (hex) |
| `event_timestamp` | float | ✓ | — | Unix timestamp of the reference moment |
| `lookback_hours` | float | | 24.0 | Hours before the reference time to include |
| `limit` | int | | 1000 | Max trades to pull |

**Returns:** `(summary, raw)` — same format as `get_pre_event_trades`.

---

### ④ Statistical & Anomaly Detection

---

#### `compute_price_run_up(condition_id, outcome_index=0, opening_hours=24.0, baseline_hours=72.0)`

Compares price in the first N hours of available price data to the subsequent baseline. Anchors to the first actual data point so both windows always contain data. Works on open and closed markets via `/prices-history`.

| Argument | Type | Required | Default | Description |
|---|---|---|---|---|
| `condition_id` | str | ✓ | — | Market conditionId (hex) |
| `outcome_index` | int | | 0 | 0 = YES/first outcome, 1 = NO/second outcome |
| `opening_hours` | float | | 24.0 | Length of the opening window |
| `baseline_hours` | float | | 72.0 | Length of the subsequent comparison period |

**Returns:** `str` — shows market start, first data point, both windows with avg/high/low, absolute drift, % drift, and up-tick fraction.

---

#### `compute_price_run_up_at(condition_id, clob_token_id, event_timestamp, baseline_hours=72.0, pre_event_hours=24.0)`

Measures price drift in the N hours *before* a specific timestamp vs a baseline period further back. Use for backward-looking analysis on a known event.

| Argument | Type | Required | Default | Description |
|---|---|---|---|---|
| `condition_id` | str | ✓ | — | Market conditionId (for labelling) |
| `clob_token_id` | str | ✓ | — | CLOB token ID for the outcome |
| `event_timestamp` | float | ✓ | — | Unix timestamp of the reference moment |
| `baseline_hours` | float | | 72.0 | Length of the baseline period ending at `pre_event_hours` before event |
| `pre_event_hours` | float | | 24.0 | Hours before event to define the pre-event window |

**Returns:** `str` — baseline avg, pre-event avg, absolute and % drift, up-tick fraction.

---

#### `compute_abnormal_volume(condition_id, opening_hours=24.0, baseline_hours=72.0, limit=2000)`

Compares trade volume (shares/hr) in the first N hours of actual trading to the subsequent baseline. Anchors to the first actual trade timestamp.

| Argument | Type | Required | Default | Description |
|---|---|---|---|---|
| `condition_id` | str | ✓ | — | Market conditionId (hex) |
| `opening_hours` | float | | 24.0 | Length of the opening window |
| `baseline_hours` | float | | 72.0 | Length of the subsequent baseline period |
| `limit` | int | | 2000 | Max trades to fetch |

**Returns:** `str` — market start, first trade, both windows with trade count/shares/rate/direction split, opening-to-baseline ratio.

---

#### `compute_abnormal_volume_at(condition_id, event_timestamp, baseline_hours=72.0, pre_event_hours=24.0, limit=2000)`

Compares trade volume in the N hours before a specific timestamp to a baseline period further back.

| Argument | Type | Required | Default | Description |
|---|---|---|---|---|
| `condition_id` | str | ✓ | — | Market conditionId (hex) |
| `event_timestamp` | float | ✓ | — | Unix timestamp of the reference moment |
| `baseline_hours` | float | | 72.0 | Baseline period length |
| `pre_event_hours` | float | | 24.0 | Pre-event window length |
| `limit` | int | | 2000 | Max trades to fetch |

**Returns:** `str` — same format as `compute_abnormal_volume`.

---

#### `find_synchronized_traders(condition_id, time_window_seconds=300, min_cluster_size=2, limit=1000)`

Identifies clusters of distinct wallets that traded in the same direction within a tight time window.

| Argument | Type | Required | Default | Description |
|---|---|---|---|---|
| `condition_id` | str | ✓ | — | Market conditionId (hex) |
| `time_window_seconds` | int | | 300 | Max gap between trades to be considered synchronized |
| `min_cluster_size` | int | | 2 | Minimum distinct wallets to form a cluster |
| `limit` | int | | 1000 | Max trades to fetch |

**Returns:** `(summary, raw)` — summary lists all clusters with direction, wallet count, total size, % of market volume, time since market open, and per-wallet trade breakdown with timestamps and tx hashes; raw is a list of cluster dicts.

**Cluster dict fields:** `direction`, `trades[]`, `wallets[]`, `total_size`, `avg_price`, `start_ts`, `end_ts`, `time_span`.

Wallets appearing in more than one cluster are marked with ★.

---

#### `score_trade_timing(wallet_address, condition_id)`

Scores each of a wallet's trades on a market by timing (how close to market `endDate`) and size. Reference time is automatically derived from the market's `endDate` via Gamma.

| Argument | Type | Required | Description |
|---|---|---|---|
| `wallet_address` | str | ✓ | Wallet address (EOA or proxy wallet) |
| `condition_id` | str | ✓ | Market conditionId (hex) |

**Returns:** `str` — reference time, number of trades scored, overall score (0.0–1.0), and a sorted table of individual trade scores.

**Scoring formula:** `score = recency_component × 0.7 + size_component × 0.3`

Recency bands: `< 0.5h → 0.0`, `0.5–24h → 0.9`, `24–72h → 0.7`, `72–168h → 0.4`, `> 168h → 0.15`. Size normalised against a 5,000-share ceiling.

---

#### `score_trade_timing_at(wallet_address, condition_id, event_timestamp)`

Same as `score_trade_timing` but with an explicit reference timestamp.

| Argument | Type | Required | Description |
|---|---|---|---|
| `wallet_address` | str | ✓ | Wallet address |
| `condition_id` | str | ✓ | Market conditionId (hex) |
| `event_timestamp` | float | ✓ | Unix timestamp of the reference moment |

**Returns:** `str` — same format as `score_trade_timing`.

---

### ⑤ Market Position Data

---

#### `get_market_movers(condition_id, limit=50)`

Wallets ranked by current position size on a market.

| Argument | Type | Required | Default | Description |
|---|---|---|---|---|
| `condition_id` | str | ✓ | — | Market conditionId (hex) |
| `limit` | int | | 50 | Max positions to fetch |

**Returns:** `(summary, raw)` — summary shows top 20 positions with wallet, outcome, size, avg entry price, cash PnL, and total PnL; raw is the full position list.

---

#### `get_market_top_holders(condition_id, min_balance=1, limit=20)`

Top token holders by current balance, grouped per outcome token.

| Argument | Type | Required | Default | Description |
|---|---|---|---|---|
| `condition_id` | str | ✓ | — | Market conditionId (hex) |
| `min_balance` | int | | 1 | Minimum balance to include |
| `limit` | int | | 20 | Max holders per token |

**Returns:** `(summary, raw)` — summary shows display name, proxy wallet address, balance, and outcome index per holder; raw is the full holders response.

---

#### `get_market_open_interest(condition_id)`

Current open interest (total value of outstanding positions) for a market.

| Argument | Type | Required | Description |
|---|---|---|---|
| `condition_id` | str | ✓ | Market conditionId (hex) |

**Returns:** `str` — open interest value in USD.

---

#### `get_live_event_volume(event_id)`

Live trading volume for an entire event (all nested markets combined).

| Argument | Type | Required | Description |
|---|---|---|---|
| `event_id` | int | ✓ | Integer event ID (from event metadata) |

**Returns:** `str` — total event volume and per-market breakdown.

---

### ⑥ Wallet Profiling

---

#### `get_wallet_profile(wallet_address)`

Public profile and trading summary for a wallet. Combines Gamma profile data with Data API trade and position history.

| Argument | Type | Required | Description |
|---|---|---|---|
| `wallet_address` | str | ✓ | Wallet address (EOA or proxy wallet) |

**Returns:** `str` — name, bio, X handle, verified status, proxy wallet, first/latest trade, markets traded, BUY/SELL counts, USDC volume, open positions snapshot.

---

#### `get_wallet_trade_history(wallet_address, limit=200, condition_id=None)`

Full trade history for a wallet across all markets. Automatically resolves the proxy wallet address — the Data API requires the proxy wallet, not the user's EOA.

| Argument | Type | Required | Default | Description |
|---|---|---|---|---|
| `wallet_address` | str | ✓ | — | Wallet address (EOA or proxy wallet) |
| `limit` | int | | 200 | Max trades to fetch |
| `condition_id` | str | | None | If provided, filter to trades on this market only |

**Returns:** `(summary, raw)` — summary shows time range, unique markets, BUY/SELL split, most traded markets, and last 5 trades; raw is the full trade list.

If `condition_id` is provided and returns empty, the function automatically retries without the filter to check whether the wallet exists but simply has no trades on that market.

---

#### `get_wallet_pnl(wallet_address)`

Profit and loss breakdown: open positions (unrealised) and closed positions (realised).

| Argument | Type | Required | Description |
|---|---|---|---|
| `wallet_address` | str | ✓ | Wallet address |

**Returns:** `str` — open position count/PnL, closed position count/realised PnL, total PnL, win rate, top 5 winners and losers by PnL.

---

#### `get_wallet_activity(wallet_address, limit=200)`

On-chain activity log for a wallet: trades, splits, merges, redeems, rewards, conversions.

| Argument | Type | Required | Default | Description |
|---|---|---|---|---|
| `wallet_address` | str | ✓ | — | Wallet address |
| `limit` | int | | 200 | Max activity events to fetch |

**Returns:** `(summary, raw)` — summary shows activity type breakdown (counts) and last 5 events with type, size, cash value, and market title; raw is the full activity list.

---

### ⑦ Querying & Filtering Utilities

Pure data manipulation — **no API calls**. Operate on the `raw` second return value from any function that returns `(summary, raw)`. Fetch once, then query freely.

---

#### `filter_trades(trades, wallet=None, side=None, min_size=None, max_size=None, start_ts=None, end_ts=None, outcome=None, min_price=None, max_price=None)`

Filters a trade list by any combination of fields. All parameters are optional and combinable.

| Argument | Type | Default | Description |
|---|---|---|---|
| `trades` | list | — | Raw trade list |
| `wallet` | str | None | Exact `proxyWallet` match |
| `side` | str | None | `"BUY"` or `"SELL"` |
| `min_size` | float | None | Minimum trade size in shares (inclusive) |
| `max_size` | float | None | Maximum trade size in shares (inclusive) |
| `start_ts` | float | None | Earliest Unix timestamp (inclusive) |
| `end_ts` | float | None | Latest Unix timestamp (inclusive) |
| `outcome` | str | None | Outcome label, e.g. `"Yes"` or `"No"` |
| `min_price` | float | None | Minimum price (inclusive) |
| `max_price` | float | None | Maximum price (inclusive) |

**Returns:** `(summary, raw)` — summary shows filters applied and BUY/SELL/size totals for matching trades; raw is filtered list sorted by timestamp ascending.

---

#### `sort_trades(trades, by="timestamp", ascending=True)`

Sorts a trade list by any field.

| Argument | Type | Default | Description |
|---|---|---|---|
| `trades` | list | — | Raw trade list |
| `by` | str | `"timestamp"` | Field to sort by: `"timestamp"`, `"size"`, `"price"`, `"usdcSize"` |
| `ascending` | bool | True | Sort direction |

**Returns:** `list` — sorted trade list (no summary).

---

#### `summarize_trades(trades, label="")`

Prints quick statistics for any trade list.

| Argument | Type | Default | Description |
|---|---|---|---|
| `trades` | list | — | Any trade list |
| `label` | str | `""` | Optional label shown in the header |

**Returns:** `str` — count, BUY/SELL split, unique wallets, size min/avg/max/total, USDC volume, price avg/min/max, time span.

---

#### `group_trades_by_wallet(trades)`

Groups a trade list by `proxyWallet`, sorted by total size descending.

| Argument | Type | Description |
|---|---|---|
| `trades` | list | Any trade list |

**Returns:** `(summary, raw)` — summary shows top 15 wallets with trade count, total size, BUY/SELL split, and USDC volume; raw is `{ proxyWallet: [trades] }`.

---

#### `cross_reference_wallets(trades_a, trades_b, label_a="A", label_b="B")`

Finds wallets that appear in both trade lists. Useful for detecting wallets that traded on two different markets, or in two different time windows.

| Argument | Type | Default | Description |
|---|---|---|---|
| `trades_a` | list | — | First trade list |
| `trades_b` | list | — | Second trade list |
| `label_a` | str | `"A"` | Label for first list (shown in summary) |
| `label_b` | str | `"B"` | Label for second list |

**Returns:** `(summary, raw)` — summary shows overlap count and per-wallet activity in each list; raw is a sorted list of overlapping `proxyWallet` addresses.

---

#### `filter_clusters(clusters, min_wallets=None, min_total_size=None, direction=None, max_time_span_seconds=None)`

Filters the cluster list from `find_synchronized_traders`.

| Argument | Type | Default | Description |
|---|---|---|---|
| `clusters` | list | — | Raw cluster list from `find_synchronized_traders` |
| `min_wallets` | int | None | Minimum distinct wallets per cluster |
| `min_total_size` | float | None | Minimum total shares traded in cluster |
| `direction` | str | None | `"BUY"` or `"SELL"` |
| `max_time_span_seconds` | int | None | Maximum cluster duration in seconds |

**Returns:** `(summary, raw)` — summary shows filters and match count; raw is filtered cluster list.

---

#### `trades_timeline(trades, max_entries=50)`

Formats a trade list as a chronological log, one line per trade.

| Argument | Type | Default | Description |
|---|---|---|---|
| `trades` | list | — | Any trade list |
| `max_entries` | int | 50 | Max lines shown (most recent if truncated) |

**Returns:** `str` — chronological table with timestamp, side, size, price, outcome, wallet address, and transaction hash.

---

#### `filter_events(events, active=None, closed=None, min_volume=None, max_volume=None, min_liquidity=None, tag_slug=None)`

Filters an event list from `search_events` or `get_related_events`.

| Argument | Type | Default | Description |
|---|---|---|---|
| `events` | list | — | Raw event list |
| `active` | bool | None | `True` = active only, `False` = inactive only |
| `closed` | bool | None | `True` = closed only, `False` = open only |
| `min_volume` | float | None | Minimum all-time volume |
| `max_volume` | float | None | Maximum all-time volume |
| `min_liquidity` | float | None | Minimum liquidity |
| `tag_slug` | str | None | Only events containing this tag slug |

**Returns:** `(summary, raw)` — summary shows filters and match count; raw is filtered event list.

---

## Example Workflow

```python
from tools import *

# Constants for "US x Iran ceasefire by May 31?"
CONDITION_ID = "0xa9937410f8aae98cc6440a7480ad832be5a1a998afcf5a6e77c6f5aa4c0f259f"
CLOB_YES     = "97390751868769233430161550786035197721004217118584051662030655361575807718008"

# 1. Orient: what markets exist?
print(get_event_info("us-x-iran-ceasefire-by"))

# 2. Pull all trades and early trades
_, all_trades  = get_market_trades(CONDITION_ID, limit=2000)
_, early_trades = get_pre_event_trades(CONDITION_ID, opening_hours=48)

# 3. Who were the biggest early buyers?
_, early_buys = filter_trades(early_trades, side="BUY", min_size=1000)
print(trades_timeline(early_buys))

# 4. Did any of those wallets also show up in synchronized clusters?
_, clusters = find_synchronized_traders(CONDITION_ID, time_window_seconds=120)
cluster_trades = [t for c in clusters for t in c["trades"]]
summary, shared_wallets = cross_reference_wallets(
    early_buys, cluster_trades, "early big buys", "clusters"
)
print(summary)

# 5. Profile each shared wallet
for wallet in shared_wallets:
    print(get_wallet_profile(wallet))

# 6. Score their timing
for wallet in shared_wallets:
    print(score_trade_timing(wallet, CONDITION_ID))

# 7. Check price movement over the first 24h vs next 72h
print(compute_price_run_up(CONDITION_ID, outcome_index=0, opening_hours=24, baseline_hours=72))

# 8. Check volume in the same windows
print(compute_abnormal_volume(CONDITION_ID, opening_hours=24, baseline_hours=72))
```
