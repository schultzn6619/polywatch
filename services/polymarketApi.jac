"""Polymarket API toolkit — Gamma, CLOB, and Data API client for PolyWatch.

Covers event discovery, market analysis, trade investigation,
anomaly detection, and wallet profiling.
"""

import json;
import requests;
import from datetime { datetime, timezone }

glob GAMMA: str = "https://gamma-api.polymarket.com";
glob CLOB: str = "https://clob.polymarket.com";
glob DATA: str = "https://data-api.polymarket.com";


# ══════════════════════════════════════════════════════════════════
# Internal helpers
# ══════════════════════════════════════════════════════════════════

def _get(url: str, params: dict = None, timeout: int = 15) -> any {
    try {
        if params {
            r = requests.get(url, timeout=timeout, params=params);
        } else {
            r = requests.get(url, timeout=timeout);
        }
        r.raise_for_status();
        return r.json();
    } except Exception as e {
        print("[HTTP ERROR] " + url + "\n  -> " + str(e));
        return None;
    }
}


def _find_event_by_slug(slug: str) -> list {
    data = _get(GAMMA + "/events?slug=" + slug);
    return data if data else [];
}


def _parse_json_field(value: any, fallback: any = None) -> any {
    if value is None {
        return fallback if fallback is not None else [];
    }
    if isinstance(value, list) or isinstance(value, dict) {
        return value;
    }
    try {
        return json.loads(value);
    } except Exception {
        return fallback if fallback is not None else [];
    }
}


def _ts(unix: float) -> str {
    return datetime.fromtimestamp(unix, tz=timezone.utc).strftime("%Y-%m-%d %H:%M UTC");
}


def _divider(char: str = "-", width: int = 64) -> str {
    return char * width;
}


def _get_market_meta(condition_id: str) -> dict {
    data = _get(GAMMA + "/markets", params={"condition_ids": condition_id});
    if not data {
        raise Exception(
            "No market found for conditionId: " + condition_id + "\n"
            + "  Ensure you are passing the hex conditionId (0x...).\n"
            + "  Use get_market_by_question_id() if you only have the questionId."
        );
    }
    return data[0];
}


def _market_end_timestamp(condition_id: str) -> float {
    market = _get_market_meta(condition_id);
    end_date = market.get("endDate");
    if not end_date {
        raise Exception("No endDate found for conditionId: " + condition_id);
    }
    for fmt in ["%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S.%fZ", "%Y-%m-%dT%H:%M:%S"] {
        try {
            end_ts = datetime.strptime(end_date, fmt).replace(tzinfo=timezone.utc).timestamp();
            now_ts = datetime.now(tz=timezone.utc).timestamp();
            return min(end_ts, now_ts);
        } except ValueError {
            continue;
        }
    }
    raise Exception("Could not parse endDate '" + end_date + "'");
}


def _market_start_timestamp(condition_id: str) -> float {
    market = _get_market_meta(condition_id);
    start_date = market.get("startDate");
    if not start_date {
        raise Exception("No startDate found for conditionId: " + condition_id);
    }
    for fmt in ["%Y-%m-%dT%H:%M:%S.%fZ", "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S"] {
        try {
            return datetime.strptime(start_date, fmt).replace(tzinfo=timezone.utc).timestamp();
        } except ValueError {
            continue;
        }
    }
    raise Exception("Could not parse startDate '" + start_date + "'");
}


def _clob_token_for_outcome(condition_id: str, outcome_index: int = 0) -> str {
    market = _get_market_meta(condition_id);
    token_ids = _parse_json_field(market.get("clobTokenIds"));
    outcomes  = _parse_json_field(market.get("outcomes"));
    if not token_ids {
        raise Exception("No clobTokenIds found for conditionId: " + condition_id);
    }
    if outcome_index >= len(token_ids) {
        raise Exception(
            "outcome_index " + str(outcome_index) + " out of range — "
            + "market has " + str(len(token_ids)) + " outcome(s): " + str(outcomes)
        );
    }
    return token_ids[outcome_index];
}


def _resolve_proxy_wallet(wallet_address: str) -> str {
    try {
        r = requests.get(GAMMA + "/public-profile", params={"address": wallet_address}, timeout=10);
        if r.status_code == 200 {
            data = r.json();
            if data and data.get("proxyWallet") {
                return data["proxyWallet"];
            }
        }
    } except Exception {
        0;
    }
    return wallet_address;
}


def _wallet_size_map(trades: list) -> dict {
    # Replacement for defaultdict(float) — sums trade sizes by wallet
    wallets: dict = {};
    for t in trades {
        w = t.get("proxyWallet", "?");
        wallets[w] = wallets.get(w, 0.0) + float(t.get("size", 0));
    }
    return wallets;
}


def _sorted_wallet_items(wallets: dict) -> list {
    # Return list of (wallet, size) tuples sorted by size descending
    items = list(wallets.items());
    items.sort(key=lambda x: x[1], reverse=True);
    return items;
}


# ══════════════════════════════════════════════════════════════════
# Event Discovery
# ══════════════════════════════════════════════════════════════════

def get_event_info(slug: str) -> str {
    events = _find_event_by_slug(slug);
    if not events {
        raise Exception("No event found for slug: '" + slug + "'");
    }

    event = events[0];
    meta  = event.get("eventMetadata") or {};
    tags  = event.get("tags") or [];
    tag_slugs = ", ".join(t.get("slug", "") for t in tags) or "none";

    lines = [
        'Event: "' + str(event.get("title", event.get("slug"))) + '"',
        _divider(),
        "Slug:              " + str(event.get("slug")),
        "Description:       " + str(event.get("description")),
        "AI Context:        " + str(meta.get("context_description")),
        "AI Context Date:   " + str(meta.get("context_updated_at")),
        "Today:             " + str(datetime.now().strftime("%Y-%m-%d %H:%M")),
        "Start Date:        " + str(event.get("startDate")),
        "End Date:          " + str(event.get("endDate")),
        "Active:            " + str(event.get("active")),
        "Closed:            " + str(event.get("closed")),
        "Tags:              " + tag_slugs,
        _divider("."),
        "Volume (all-time): $" + str(event.get("volume")),
        "Volume 24h:        $" + str(event.get("volume24hr")),
        "Volume 1wk:        $" + str(event.get("volume1wk")),
        "Volume 1mo:        $" + str(event.get("volume1mo")),
        "Volume 1yr:        $" + str(event.get("volume1yr")),
        "Liquidity:         $" + str(event.get("liquidity")),
        "Liquidity (CLOB):  $" + str(event.get("liquidityClob")),
        "Open Interest:     $" + str(event.get("openInterest")),
        "",
    ];

    markets = event.get("markets") or [];
    if not markets {
        raise Exception("No markets found for event.");
    }

    lines.append("Markets (" + str(len(markets)) + "):");
    lines.append(_divider());

    for _idx in range(len(markets)) {
        i = _idx + 1;
        m = markets[_idx];
        outcomes   = _parse_json_field(m.get("outcomes"));
        prices     = _parse_json_field(m.get("outcomePrices"));
        token_ids  = _parse_json_field(m.get("clobTokenIds"));

        outcome_parts: list = [];
        for _oi in range(len(outcomes)) {
            outcome_parts.append(outcomes[_oi] + ": " + str(round(float(prices[_oi]), 3)));
        }
        outcome_pairs = "  |  ".join(outcome_parts) if outcomes else "N/A";

        token_parts: list = [];
        for _ti in range(min(len(outcomes), len(token_ids))) {
            token_parts.append(outcomes[_ti] + ": " + token_ids[_ti]);
        }
        token_pairs = "  |  ".join(token_parts) if token_ids else "N/A";

        lines += [
            "[" + str(i) + "] " + str(m.get("question")),
            "     conditionId:      " + str(m.get("conditionId")),
            "     questionId:       " + str(m.get("questionID")),
            "     Active/Closed:    " + str(m.get("active")) + " / " + str(m.get("closed")),
            "     Accepting Orders: " + str(m.get("acceptingOrders")),
            "     Start -> End:     " + str(m.get("startDate")) + " -> " + str(m.get("endDate")),
            "     Outcome Prices:   " + outcome_pairs,
            "     Best Bid/Ask:     " + str(m.get("bestBid")) + " / " + str(m.get("bestAsk")),
            "     Spread:           " + str(m.get("spread")),
            "     Last Trade Price: " + str(m.get("lastTradePrice")),
            "     24h Price Change: " + str(m.get("oneDayPriceChange")),
            "     1wk Price Change: " + str(m.get("oneWeekPriceChange")),
            "     Volume (all):     $" + str(m.get("volume")),
            "     Volume 24h:       $" + str(m.get("volume24hr")),
            "     Volume 1mo:       $" + str(m.get("volume1mo")),
            "     Liquidity:        $" + str(m.get("liquidity")),
            "     clobTokenIds:     " + token_pairs,
            "",
        ];
    }
    return "\n".join(lines);
}


def search_events(query: str, limit: int = 10) -> tuple {
    data = _get(GAMMA + "/public-search", params={"q": query, "limit_per_type": limit});
    if not data {
        raise Exception("No search results for: '" + query + "'");
    }

    events     = data.get("events") or [];
    tags       = data.get("tags") or [];
    profiles   = data.get("profiles") or [];
    pagination = data.get("pagination") or {};

    lines = [
        "Search: '" + query + "'",
        "Results: " + str(len(events)) + " event(s)  " + str(len(tags)) + " tag(s)  " + str(len(profiles)) + " profile(s)",
        "Has More: " + str(pagination.get("hasMore")) + "   Total: " + str(pagination.get("totalResults")),
        _divider(),
    ];
    for _idx in range(len(events)) {
        i = _idx + 1;
        ev = events[_idx];
        tag_slugs = ", ".join(t.get("slug", "") for t in (ev.get("tags") or []));
        active_str = "Active" if ev.get("active") else "Closed";
        lines += [
            "[" + str(i) + "] " + str(ev.get("title", "Untitled")),
            "     Slug:       " + str(ev.get("slug")),
            "     Status:     " + active_str,
            "     End Date:   " + str(ev.get("endDate")),
            "     Volume:     $" + str(ev.get("volume")) + "   Vol 24h: $" + str(ev.get("volume24hr")),
            "     Liquidity:  $" + str(ev.get("liquidity")),
            "     Markets:    " + str(len(ev.get("markets") or [])),
            "     Tags:       " + tag_slugs,
            "",
        ];
    }
    if tags {
        lines.append("Matching Tags:");
        for t in tags {
            lines.append("  * " + str(t.get("label")) + " (slug: " + str(t.get("slug")) + ", events: " + str(t.get("event_count")) + ")");
        }
    }
    return ("\n".join(lines), data);
}


def search_events_structured(query: str) -> list {
    # Structured search returning list of dicts for frontend cards
    data = _get(GAMMA + "/public-search", params={"q": query, "limit_per_type": 10});
    if not data {
        return [];
    }
    events = data.get("events") or [];
    results: list = [];
    for ev in events {
        ev_markets = ev.get("markets") or [];
        has_active = False;
        for m in ev_markets {
            if m.get("active", False) {
                has_active = True;
            }
        }
        results.append({
            "title": ev.get("title", ""),
            "slug": ev.get("slug", ""),
            "volume": ev.get("volume", "0"),
            "liquidity": ev.get("liquidity", "0"),
            "markets_count": len(ev_markets),
            "active": has_active
        });
    }
    return results;
}


def get_related_events(tag_slug: str, limit: int = 10) -> tuple {
    data = _get(GAMMA + "/events", params={"tag_slug": tag_slug, "limit": limit});
    if not data {
        raise Exception("No events for tag_slug: '" + tag_slug + "'");
    }
    lines = [
        "Events tagged '" + tag_slug + "'  [" + str(len(data)) + " returned]",
        _divider(),
    ];
    for _idx in range(len(data)) {
        i = _idx + 1;
        ev = data[_idx];
        active_str = "Active" if ev.get("active") else "Closed";
        lines += [
            "[" + str(i) + "] " + str(ev.get("title", "Untitled")),
            "     Slug:       " + str(ev.get("slug")),
            "     Status:     " + active_str,
            "     End Date:   " + str(ev.get("endDate")),
            "     Volume:     $" + str(ev.get("volume")) + "   Vol 24h: $" + str(ev.get("volume24hr")),
            "     Liquidity:  $" + str(ev.get("liquidity")),
            "     Open Int:   $" + str(ev.get("openInterest")),
            "     Markets:    " + str(len(ev.get("markets") or [])),
            "",
        ];
    }
    return ("\n".join(lines), data);
}


# ══════════════════════════════════════════════════════════════════
# Market Analysis
# ══════════════════════════════════════════════════════════════════

def get_market_by_question_id(question_id: str) -> tuple {
    data = _get(GAMMA + "/markets", params={"question_ids": question_id});
    if not data {
        raise Exception("No market found for questionId: " + question_id);
    }
    m = data[0];
    outcomes  = _parse_json_field(m.get("outcomes"));
    prices    = _parse_json_field(m.get("outcomePrices"));
    token_ids = _parse_json_field(m.get("clobTokenIds"));
    tags      = ", ".join(t.get("slug", "") for t in (m.get("tags") or [])) or "none";

    outcome_parts2: list = [];
    for _oi in range(min(len(outcomes), len(prices), len(token_ids))) {
        outcome_parts2.append(outcomes[_oi] + ": " + str(round(float(prices[_oi]), 4)) + " [tokenId: " + token_ids[_oi] + "]");
    }
    outcome_str = "  |  ".join(outcome_parts2) if outcomes else "N/A";

    lines = [
        "Market: " + str(m.get("question")),
        _divider(),
        "conditionId:         " + str(m.get("conditionId")),
        "Slug:                " + str(m.get("slug")),
        "Active:              " + str(m.get("active")) + "   Closed: " + str(m.get("closed")),
        "Accepting Orders:    " + str(m.get("acceptingOrders")),
        "Start -> End:        " + str(m.get("startDate")) + " -> " + str(m.get("endDate")),
        "Tags:                " + tags,
        _divider("."),
        "Outcomes & Prices:   " + outcome_str,
        "Best Bid / Ask:      " + str(m.get("bestBid")) + " / " + str(m.get("bestAsk")),
        "Spread:              " + str(m.get("spread")),
        "Last Trade Price:    " + str(m.get("lastTradePrice")),
        "24h Price Change:    " + str(m.get("oneDayPriceChange")),
        "1wk Price Change:    " + str(m.get("oneWeekPriceChange")),
        _divider("."),
        "Volume (all-time):   $" + str(m.get("volume")),
        "Volume 24h:          $" + str(m.get("volume24hr")),
        "Volume 1wk:          $" + str(m.get("volume1wk")),
        "Volume 1mo:          $" + str(m.get("volume1mo")),
        "Volume 1yr:          $" + str(m.get("volume1yr")),
        "Liquidity (total):   $" + str(m.get("liquidity")),
        "Liquidity (CLOB):    $" + str(m.get("liquidityClob")),
        "Tick Size:           " + str(m.get("orderPriceMinTickSize")),
        "Min Order Size:      " + str(m.get("orderMinSize")),
    ];
    return ("\n".join(lines), m);
}


def get_market_orderbook(clob_token_id: str) -> tuple {
    data = _get(CLOB + "/book", params={"token_id": clob_token_id});
    if not data {
        raise Exception("No order book for token_id: " + clob_token_id);
    }
    bids = data.get("bids") or [];
    asks = data.get("asks") or [];
    best_bid = bids[0] if bids else None;
    best_ask = asks[0] if asks else None;
    spread = round(float(best_ask["price"]) - float(best_bid["price"]), 4) if best_bid and best_ask else "N/A";
    bid_liq = sum(float(b["size"]) for b in bids);
    ask_liq = sum(float(a["size"]) for a in asks);

    def _fmt(levels: list, n: int = 5) -> str {
        return "\n".join(
            "       " + str(lv.get("price")) + "  x  " + str(lv.get("size")) for lv in levels[:n]
        ) or "       (empty)";
    }

    lines = [
        "Order Book - token_id: " + clob_token_id,
        "conditionId (market): " + str(data.get("market")),
        "Last Trade Price:     " + str(data.get("last_trade_price")),
        _divider(),
        "Best Bid:  " + (str(best_bid["price"]) if best_bid else "N/A") + "  (size: " + (str(best_bid["size"]) if best_bid else "N/A") + ")",
        "Best Ask:  " + (str(best_ask["price"]) if best_ask else "N/A") + "  (size: " + (str(best_ask["size"]) if best_ask else "N/A") + ")",
        "Spread:    " + str(spread),
        _divider("."),
        "Top Bids:\n" + _fmt(bids),
        "Top Asks:\n" + _fmt(asks),
        _divider("."),
        "Total bid levels: " + str(len(bids)) + "   Total bid liquidity: " + str(round(bid_liq, 2)),
        "Total ask levels: " + str(len(asks)) + "   Total ask liquidity: " + str(round(ask_liq, 2)),
    ];
    return ("\n".join(lines), data);
}


def get_market_price_history(clob_token_id: str, interval: str = "1w", fidelity: int = 100) -> tuple {
    valid = ["1h", "6h", "1d", "1w", "1m", "max"];
    if interval not in valid {
        raise Exception("interval must be one of " + str(valid) + ", got '" + interval + "'");
    }
    data = _get(CLOB + "/prices-history", params={"market": clob_token_id, "interval": interval, "fidelity": fidelity});
    if not data {
        raise Exception("No price history for token_id: " + clob_token_id);
    }
    history = data.get("history") or [];
    if not history {
        raise Exception("Price history is empty.");
    }
    prices = [float(pt["p"]) for pt in history];
    times  = [pt["t"] for pt in history];
    cur = prices[-1];
    hi  = max(prices);
    lo  = min(prices);
    mid_idx = len(prices) // 2;
    first_half_avg = sum(prices[:mid_idx]) / max(mid_idx, 1);
    second_half_avg = sum(prices[mid_idx:]) / max(len(prices) - mid_idx, 1);
    trend = "Rising" if second_half_avg > first_half_avg else "Falling";

    lines = [
        "Price History - token_id: " + clob_token_id,
        "Interval: " + interval + "   Fidelity: " + str(fidelity) + " min/point   Points: " + str(len(history)),
        "Period:   " + _ts(times[0]) + "  ->  " + _ts(times[-1]),
        _divider(),
        "Current:  " + str(round(cur, 4)),
        "High:     " + str(round(hi, 4)),
        "Low:      " + str(round(lo, 4)),
        "Range:    " + str(round(hi - lo, 4)),
        "Trend:    " + trend,
    ];
    return ("\n".join(lines), history);
}


def get_market_price_history_range(condition_id: str, start_ts: float, end_ts: float, outcome_index: int = 0, fidelity: int = 60) -> tuple {
    clob_token_id = _clob_token_for_outcome(condition_id, outcome_index);
    data = _get(CLOB + "/prices-history", params={
        "market": clob_token_id,
        "startTs": int(start_ts),
        "endTs": int(end_ts),
        "fidelity": fidelity,
    });
    if not data {
        raise Exception("No price history for conditionId: " + condition_id);
    }
    history = data.get("history") or [];
    if not history {
        raise Exception("Price history returned empty for the requested window.");
    }
    prices = [float(pt["p"]) for pt in history];
    lines = [
        "Price History (custom range) - conditionId: " + condition_id,
        "CLOB token:  " + clob_token_id,
        "Window:      " + _ts(start_ts) + "  ->  " + _ts(end_ts),
        "Fidelity:    " + str(fidelity) + " min/point   Points: " + str(len(history)),
        "Actual span: " + _ts(history[0]["t"]) + "  ->  " + _ts(history[-1]["t"]),
        _divider(),
        "Open:    " + str(round(prices[0], 4)),
        "Close:   " + str(round(prices[-1], 4)),
        "High:    " + str(round(max(prices), 4)),
        "Low:     " + str(round(min(prices), 4)),
        "Range:   " + str(round(max(prices) - min(prices), 4)),
    ];
    return ("\n".join(lines), history);
}


# ══════════════════════════════════════════════════════════════════
# Trade-Level Investigation
# ══════════════════════════════════════════════════════════════════

def get_market_trades(condition_id: str, limit: int = 500, taker_only: bool = False) -> tuple {
    data = _get(DATA + "/trades", params={"market": condition_id, "limit": limit, "takerOnly": str(taker_only).lower()});
    if data is None {
        raise Exception("Failed to fetch trades for market: " + condition_id);
    }
    if not data {
        return ("No trades found for market: " + condition_id, []);
    }
    buys  = [t for t in data if t.get("side") == "BUY"];
    sells = [t for t in data if t.get("side") == "SELL"];
    wallets = _wallet_size_map(data);
    times = sorted([t.get("timestamp", 0) for t in data if t.get("timestamp")]);
    top_wallets = _sorted_wallet_items(wallets)[:5];

    lines = [
        "Market Trades - conditionId: " + condition_id,
        "Fetched: " + str(len(data)) + " trade(s)  (limit=" + str(limit) + ")",
        ("Time range: " + _ts(times[0]) + "  ->  " + _ts(times[-1])) if times else "Time range: N/A",
        _divider(),
        "BUY trades:   " + str(len(buys)),
        "SELL trades:  " + str(len(sells)),
        "Buy/Sell ratio: " + str(round(len(buys) / max(len(sells), 1), 2)),
        "Unique wallets: " + str(len(wallets)),
        _divider("."),
        "Top 5 wallets by trade volume (shares):",
    ];
    for pair in top_wallets {
        w = pair[0];
        sz = pair[1];
        lines.append("  " + w + "  ->  " + str(round(sz, 2)) + " shares");
    }
    return ("\n".join(lines), data);
}


def get_large_trades(condition_id: str, min_size: float = 1000.0, limit: int = 500) -> tuple {
    (_, all_trades) = get_market_trades(condition_id, limit=limit);
    large = sorted(
        [t for t in all_trades if float(t.get("size", 0)) >= min_size],
        key=lambda t: float(t.get("size", 0)),
        reverse=True
    );
    if not large {
        return ("No trades >= " + str(min_size) + " shares found on market: " + condition_id, []);
    }
    buys  = [t for t in large if t.get("side") == "BUY"];
    sells = [t for t in large if t.get("side") == "SELL"];
    total_buy_size  = sum(float(t.get("size", 0)) for t in buys);
    total_sell_size = sum(float(t.get("size", 0)) for t in sells);
    lines = [
        "Large Trades (>= " + str(min_size) + " shares) - conditionId: " + condition_id,
        "Found: " + str(len(large)) + " large trade(s) out of " + str(len(all_trades)) + " total",
        _divider(),
        "BUY  trades: " + str(len(buys)) + "   total size: " + str(round(total_buy_size, 2)),
        "SELL trades: " + str(len(sells)) + "   total size: " + str(round(total_sell_size, 2)),
        _divider("."),
        "Top 10 large trades:",
    ];
    for t in large[:10] {
        ts = _ts(t["timestamp"]) if t.get("timestamp") else "?";
        lines.append(
            "  [" + ts + "] " + str(t.get("side", "?")) + "  size: " + str(round(float(t.get("size", 0)), 2))
            + "  @ " + str(t.get("price")) + "  outcome: " + str(t.get("outcome"))
            + "  wallet: " + str(t.get("proxyWallet"))
        );
    }
    return ("\n".join(lines), large);
}


def get_pre_event_trades(condition_id: str, opening_hours: float = 24.0, limit: int = 1000) -> tuple {
    # Trades from the first N hours of actual trading activity
    (_, all_trades) = get_market_trades(condition_id, limit=limit);
    timed = sorted(
        [t for t in all_trades if t.get("timestamp")],
        key=lambda t: t["timestamp"]
    );
    if not timed {
        return ("No timestamped trades available for conditionId: " + condition_id, []);
    }
    actual_start = timed[0]["timestamp"];
    opening_end  = actual_start + opening_hours * 3600;
    market_start = _market_start_timestamp(condition_id);
    data_gap     = (actual_start - market_start) / 3600;

    window_trades = sorted(
        [t for t in timed if actual_start <= t["timestamp"] <= opening_end],
        key=lambda t: t["timestamp"]
    );
    if not window_trades {
        return ("No trades in opening " + str(opening_hours) + "h window.", []);
    }
    buys    = [t for t in window_trades if t.get("side") == "BUY"];
    sells   = [t for t in window_trades if t.get("side") == "SELL"];
    wallets = _wallet_size_map(window_trades);

    span = opening_end - actual_start;
    q    = span / 4;
    buckets = [0, 0, 0, 0];
    for t in window_trades {
        buckets[min(int((t["timestamp"] - actual_start) // q), 3)] += 1;
    }

    label = "Opening Window (" + str(opening_hours) + "h from first trade";
    if data_gap > 1 {
        label += " — first trade was " + str(round(data_gap, 1)) + "h after market start";
    }
    label += ")";

    lines = [
        "Trades - conditionId: " + condition_id,
        label,
        "Window:         " + _ts(actual_start) + "  ->  " + _ts(opening_end),
        _divider(),
        "Total trades:   " + str(len(window_trades)),
        "BUY:            " + str(len(buys)) + "   SELL: " + str(len(sells)),
        "Buy/Sell ratio: " + str(round(len(buys) / max(len(sells), 1), 2)),
        "Unique wallets: " + str(len(wallets)),
        _divider("."),
        "Timing distribution (Q1-Q4):",
        "  " + str(buckets),
        _divider("."),
        "Top wallets by total size in window:",
    ];
    for pair in _sorted_wallet_items(wallets)[:8] {
        w = pair[0];
        sz = pair[1];
        lines.append("  " + w + "  ->  " + str(round(sz, 2)) + " shares");
    }
    return ("\n".join(lines), window_trades);
}


def _trades_in_window(condition_id: str, window_start: float, window_end: float, label: str = "Window", limit: int = 1000) -> tuple {
    (_, all_trades) = get_market_trades(condition_id, limit=limit);
    trades_in = sorted(
        [t for t in all_trades if t.get("timestamp") and window_start <= t["timestamp"] <= window_end],
        key=lambda t: t["timestamp"]
    );
    if not trades_in {
        return ("No trades found in window: " + _ts(window_start) + "  ->  " + _ts(window_end), []);
    }
    buys    = [t for t in trades_in if t.get("side") == "BUY"];
    sells   = [t for t in trades_in if t.get("side") == "SELL"];
    wallets = _wallet_size_map(trades_in);

    span = window_end - window_start;
    q    = span / 4;
    buckets = [0, 0, 0, 0];
    for t in trades_in {
        offset = t["timestamp"] - window_start;
        buckets[min(int(offset // q), 3)] += 1;
    }
    lines = [
        "Trades - conditionId: " + condition_id,
        label,
        "Window:         " + _ts(window_start) + "  ->  " + _ts(window_end),
        _divider(),
        "Total trades:   " + str(len(trades_in)),
        "BUY:            " + str(len(buys)) + "   SELL: " + str(len(sells)),
        "Buy/Sell ratio: " + str(round(len(buys) / max(len(sells), 1), 2)),
        "Unique wallets: " + str(len(wallets)),
        _divider("."),
        "Timing distribution (Q1-Q4):",
        "  " + str(buckets),
        _divider("."),
        "Top wallets by total size in window:",
    ];
    for pair in _sorted_wallet_items(wallets)[:8] {
        w = pair[0];
        sz = pair[1];
        lines.append("  " + w + "  ->  " + str(round(sz, 2)) + " shares");
    }
    return ("\n".join(lines), trades_in);
}


def get_pre_event_trades_at(condition_id: str, event_timestamp: float, lookback_hours: float = 24.0, limit: int = 1000) -> tuple {
    # Trades placed within a window ending at a specific timestamp
    window_start = event_timestamp - lookback_hours * 3600;
    return _trades_in_window(
        condition_id, window_start, event_timestamp,
        label="Pre-Event Window (" + str(lookback_hours) + "h before " + _ts(event_timestamp) + ")",
        limit=limit
    );
}


# ══════════════════════════════════════════════════════════════════
# Statistical & Anomaly Detection
# ══════════════════════════════════════════════════════════════════

def compute_price_run_up(condition_id: str, outcome_index: int = 0, opening_hours: float = 24.0, baseline_hours: float = 72.0) -> str {
    clob_token_id = _clob_token_for_outcome(condition_id, outcome_index);
    market_start  = _market_start_timestamp(condition_id);
    (_, history) = get_market_price_history(clob_token_id, interval="max", fidelity=60);
    if not history {
        raise Exception("No price history for token_id: " + clob_token_id);
    }
    actual_start = history[0]["t"];
    opening_end  = actual_start + opening_hours * 3600;
    baseline_end = opening_end  + baseline_hours * 3600;
    opening_pts  = [pt for pt in history if actual_start <= pt["t"] < opening_end];
    baseline_pts = [pt for pt in history if opening_end <= pt["t"] <= baseline_end];
    data_gap_hours = (actual_start - market_start) / 3600;

    lines = [
        "Price Run-Up Analysis - conditionId: " + condition_id,
        "CLOB token:          " + clob_token_id,
        "Market start:        " + _ts(market_start),
        "First data point:    " + _ts(actual_start) + (" (" + str(round(data_gap_hours, 1)) + "h after market start)" if data_gap_hours > 1 else ""),
        "Opening window:      " + _ts(actual_start) + "  ->  " + _ts(opening_end) + "  (" + str(opening_hours) + "h)",
        "Baseline window:     " + _ts(opening_end) + "  ->  " + _ts(baseline_end) + "  (" + str(baseline_hours) + "h)",
        _divider(),
    ];

    opening_avg = None;
    baseline_avg = None;

    if opening_pts {
        opening_prices = [float(p["p"]) for p in opening_pts];
        opening_avg    = sum(opening_prices) / len(opening_pts);
        lines += [
            "Opening avg price:   " + str(round(opening_avg, 4)) + "  (" + str(len(opening_pts)) + " points)",
            "Opening high/low:    " + str(round(max(opening_prices), 4)) + " / " + str(round(min(opening_prices), 4)),
        ];
    } else {
        lines.append("Opening window:      no data");
    }

    if baseline_pts {
        baseline_prices = [float(p["p"]) for p in baseline_pts];
        baseline_avg    = sum(baseline_prices) / len(baseline_pts);
        lines += [
            "Baseline avg price:  " + str(round(baseline_avg, 4)) + "  (" + str(len(baseline_pts)) + " points)",
            "Baseline high/low:   " + str(round(max(baseline_prices), 4)) + " / " + str(round(min(baseline_prices), 4)),
        ];
    } else {
        lines.append("Baseline window:     no data");
    }

    if opening_avg is not None and baseline_avg is not None {
        drift     = opening_avg - baseline_avg;
        drift_pct = (drift / baseline_avg * 100) if baseline_avg else 0;
        prices    = [float(p["p"]) for p in opening_pts];
        up_ticks  = sum(1 for i in range(1, len(prices)) if prices[i] > prices[i - 1]);
        up_pct    = up_ticks / max(len(prices) - 1, 1) * 100;
        lines += [
            _divider("."),
            "Opening vs baseline drift: " + str(round(drift, 4)),
            "Opening vs baseline drift %: " + str(round(drift_pct, 2)) + "%",
            "Up-tick fraction (opening): " + str(round(up_pct, 1)) + "%",
        ];
    }
    return "\n".join(lines);
}


def compute_price_run_up_at(condition_id: str, clob_token_id: str, event_timestamp: float, baseline_hours: float = 72.0, pre_event_hours: float = 24.0) -> str {
    (_, history) = get_market_price_history(clob_token_id, interval="max", fidelity=60);
    if not history {
        raise Exception("No price history for token_id: " + clob_token_id);
    }
    baseline_start = event_timestamp - (baseline_hours + pre_event_hours) * 3600;
    pre_start      = event_timestamp - pre_event_hours * 3600;
    baseline_pts = [pt for pt in history if baseline_start <= pt["t"] < pre_start];
    pre_pts      = [pt for pt in history if pre_start <= pt["t"] <= event_timestamp];

    if not baseline_pts or not pre_pts {
        return ("Insufficient data to compute run-up.\n"
            + "  Baseline points: " + str(len(baseline_pts)) + "   Pre-event points: " + str(len(pre_pts)));
    }
    baseline_avg = sum(float(p["p"]) for p in baseline_pts) / len(baseline_pts);
    pre_avg      = sum(float(p["p"]) for p in pre_pts) / len(pre_pts);
    run_up       = pre_avg - baseline_avg;
    run_up_pct   = (run_up / baseline_avg * 100) if baseline_avg else 0;
    pre_prices = [float(p["p"]) for p in pre_pts];
    up_ticks   = sum(1 for i in range(1, len(pre_prices)) if pre_prices[i] > pre_prices[i-1]);
    up_pct     = up_ticks / max(len(pre_prices) - 1, 1) * 100;

    lines = [
        "Price Run-Up Analysis - conditionId: " + condition_id,
        "CLOB token:          " + clob_token_id,
        "Reference time:      " + _ts(event_timestamp),
        "Baseline window:     " + _ts(baseline_start) + "  ->  " + _ts(pre_start),
        "Pre-event window:    " + _ts(pre_start) + "  ->  " + _ts(event_timestamp),
        _divider(),
        "Baseline avg price:  " + str(round(baseline_avg, 4)) + "  (" + str(len(baseline_pts)) + " points)",
        "Pre-event avg price: " + str(round(pre_avg, 4)) + "  (" + str(len(pre_pts)) + " points)",
        "Run-up (absolute):   " + str(round(run_up, 4)),
        "Run-up (%):          " + str(round(run_up_pct, 2)) + "%",
        "Up-tick fraction:    " + str(round(up_pct, 1)) + "%",
    ];
    return "\n".join(lines);
}


def compute_abnormal_volume(condition_id: str, opening_hours: float = 24.0, baseline_hours: float = 72.0, limit: int = 2000) -> str {
    market_start = _market_start_timestamp(condition_id);
    (_, all_trades) = get_market_trades(condition_id, limit=limit);
    if not all_trades {
        return "No trades available for conditionId: " + condition_id;
    }
    timed = [t for t in all_trades if t.get("timestamp")];
    if not timed {
        return "All fetched trades are missing timestamps for conditionId: " + condition_id;
    }
    actual_start = min(t["timestamp"] for t in timed);
    opening_end  = actual_start + opening_hours * 3600;
    baseline_end = opening_end  + baseline_hours * 3600;
    opening_trades  = [t for t in timed if actual_start <= t["timestamp"] < opening_end];
    baseline_trades = [t for t in timed if opening_end <= t["timestamp"] <= baseline_end];
    opening_size  = sum(float(t.get("size", 0)) for t in opening_trades);
    baseline_size = sum(float(t.get("size", 0)) for t in baseline_trades);
    opening_rate  = opening_size / max(opening_hours, 1);
    baseline_rate = baseline_size / max(baseline_hours, 1);
    ratio         = opening_rate / max(baseline_rate, 0.001);

    lines = [
        "Volume Analysis - conditionId: " + condition_id,
        "Market start:        " + _ts(market_start),
        "First trade:         " + _ts(actual_start),
        "Opening window:      " + _ts(actual_start) + "  ->  " + _ts(opening_end) + "  (" + str(opening_hours) + "h)",
        "Baseline window:     " + _ts(opening_end) + "  ->  " + _ts(baseline_end) + "  (" + str(baseline_hours) + "h)",
        _divider(),
        "Opening:   " + str(len(opening_trades)) + " trades   " + str(round(opening_size, 2)) + " shares   " + str(round(opening_rate, 2)) + " shares/hr",
        "Baseline:  " + str(len(baseline_trades)) + " trades   " + str(round(baseline_size, 2)) + " shares   " + str(round(baseline_rate, 2)) + " shares/hr",
        "Opening/baseline ratio: " + str(round(ratio, 2)) + "x",
    ];
    return "\n".join(lines);
}


def compute_abnormal_volume_at(condition_id: str, event_timestamp: float, baseline_hours: float = 72.0, pre_event_hours: float = 24.0, limit: int = 2000) -> str {
    (_, all_trades) = get_market_trades(condition_id, limit=limit);
    if not all_trades {
        return "No trades available for conditionId: " + condition_id;
    }
    baseline_start  = event_timestamp - (baseline_hours + pre_event_hours) * 3600;
    pre_start       = event_timestamp - pre_event_hours * 3600;
    baseline_trades = [t for t in all_trades if baseline_start <= (t.get("timestamp") or 0) < pre_start];
    pre_trades      = [t for t in all_trades if pre_start <= (t.get("timestamp") or 0) <= event_timestamp];
    baseline_size = sum(float(t.get("size", 0)) for t in baseline_trades);
    pre_size      = sum(float(t.get("size", 0)) for t in pre_trades);
    baseline_rate = baseline_size / max(baseline_hours, 1);
    pre_rate      = pre_size / max(pre_event_hours, 1);
    ratio         = pre_rate / max(baseline_rate, 0.001);

    lines = [
        "Volume Analysis - conditionId: " + condition_id,
        "Reference time:      " + _ts(event_timestamp),
        "Baseline window:     " + _ts(baseline_start) + "  ->  " + _ts(pre_start),
        "Pre-event window:    " + _ts(pre_start) + "  ->  " + _ts(event_timestamp),
        _divider(),
        "Baseline:            " + str(len(baseline_trades)) + " trades   " + str(round(baseline_size, 2)) + " shares   " + str(round(baseline_rate, 2)) + " shares/hr",
        "Pre-event:           " + str(len(pre_trades)) + " trades   " + str(round(pre_size, 2)) + " shares   " + str(round(pre_rate, 2)) + " shares/hr",
        "Pre/baseline ratio:  " + str(round(ratio, 2)) + "x",
    ];
    return "\n".join(lines);
}


def find_synchronized_traders(condition_id: str, time_window_seconds: int = 300, min_cluster_size: int = 2, limit: int = 1000) -> tuple {
    (_, all_trades) = get_market_trades(condition_id, limit=limit);
    if not all_trades {
        return ("No trades available for conditionId: " + condition_id, []);
    }
    timed = sorted([t for t in all_trades if t.get("timestamp")], key=lambda t: t["timestamp"]);
    clusters: list = [];
    i = 0;
    while i < len(timed) {
        anchor = timed[i];
        group  = [anchor];
        j = i + 1;
        while j < len(timed) {
            if (timed[j]["timestamp"] - anchor["timestamp"]) <= time_window_seconds {
                group.append(timed[j]);
                j += 1;
            } else {
                break;
            }
        }
        for direction in ["BUY", "SELL"] {
            dir_group = [t for t in group if t.get("side") == direction];
            wallets   = list({t.get("proxyWallet") for t in dir_group});
            if len(wallets) >= min_cluster_size {
                sizes  = [float(t.get("size", 0)) for t in dir_group];
                prices = [float(t.get("price", 0)) for t in dir_group if t.get("price")];
                clusters.append({
                    "direction":  direction,
                    "trades":     dir_group,
                    "wallets":    wallets,
                    "time_span":  dir_group[-1]["timestamp"] - dir_group[0]["timestamp"],
                    "start_ts":   dir_group[0]["timestamp"],
                    "end_ts":     dir_group[-1]["timestamp"],
                    "total_size": sum(sizes),
                    "avg_price":  sum(prices) / len(prices) if prices else None,
                });
            }
        }
        i = j if j > i else i + 1;
    }
    clusters.sort(key=lambda c: len(c["wallets"]), reverse=True);
    if not clusters {
        return ("No synchronized trading clusters found for conditionId: " + condition_id, []);
    }
    total_market_size = sum(float(t.get("size", 0)) for t in all_trades);

    lines = [
        "Synchronized Trader Analysis - conditionId: " + condition_id,
        "Trades scanned:  " + str(len(timed)),
        "Time window:     " + str(time_window_seconds) + "s   Min wallets: " + str(min_cluster_size),
        "Clusters found:  " + str(len(clusters)),
        _divider(),
    ];
    top_clusters = clusters[:10];
    for _ci in range(len(top_clusters)) {
        idx = _ci + 1;
        cl = top_clusters[_ci];
        avg_p = str(round(cl["avg_price"], 4)) if cl["avg_price"] is not None else "N/A";
        span_str = str(round(cl["time_span"])) + "s" if cl["time_span"] > 0 else "<1s";
        vol_pct = (cl["total_size"] / total_market_size * 100) if total_market_size else 0;
        lines += [
            "Cluster [" + str(idx) + "]  " + cl["direction"],
            "  Start:         " + _ts(cl["start_ts"]),
            "  End:           " + _ts(cl["end_ts"]),
            "  Time span:     " + span_str,
            "  Wallets:       " + str(len(cl["wallets"])),
            "  Trades:        " + str(len(cl["trades"])),
            "  Total size:    " + str(round(cl["total_size"], 2)) + " shares (" + str(round(vol_pct, 2)) + "% of market)",
            "  Avg price:     " + avg_p,
            "",
        ];
    }
    return ("\n".join(lines), clusters);
}


def get_market_movers(condition_id: str, limit: int = 50) -> tuple {
    data = _get(DATA + "/v1/market-positions", params={"market": condition_id, "limit": limit, "sortBy": "TOKENS", "sortDirection": "DESC"});
    if not data {
        raise Exception("No position data for market: " + condition_id);
    }
    all_positions: list = [];
    for token_bucket in data {
        token = token_bucket.get("token", "?");
        for pos in (token_bucket.get("positions") or []) {
            pos["_token"] = token;
            all_positions.append(pos);
        }
    }
    all_positions.sort(key=lambda p: float(p.get("size", 0)), reverse=True);
    lines = [
        "Market Movers - conditionId: " + condition_id,
        "Top " + str(min(limit, len(all_positions))) + " positions by size",
        _divider(),
    ];
    for p in all_positions[:20] {
        lines.append(
            "  " + str(p.get("proxyWallet")) + "  |  outcome: " + str(p.get("outcome"))
            + "  |  size: " + str(round(float(p.get("size", 0)), 2))
            + "  |  avgPrice: " + str(p.get("avgPrice"))
            + "  |  cashPnl: " + str(round(float(p.get("cashPnl", 0)), 2))
            + "  totalPnl: " + str(round(float(p.get("totalPnl", 0)), 2))
        );
    }
    return ("\n".join(lines), all_positions);
}


def get_market_top_holders(condition_id: str, min_balance: int = 1, limit: int = 20) -> tuple {
    data = _get(DATA + "/holders", params={"market": condition_id, "limit": limit, "minBalance": min_balance});
    if not data {
        raise Exception("No holder data for market: " + condition_id);
    }
    lines = ["Top Holders - conditionId: " + condition_id, _divider()];
    for bucket in data {
        token = bucket.get("token", "?");
        holders = bucket.get("holders") or [];
        lines.append("Token: " + token + "  (" + str(len(holders)) + " holders)");
        for h in holders[:10] {
            name = h.get("name") or h.get("pseudonym") or "Anonymous";
            lines.append(
                "   " + name + "  (" + str(h.get("proxyWallet", "?")) + ")"
                + "  |  balance: " + str(h.get("amount"))
                + "  |  outcome: " + str(h.get("outcomeIndex"))
            );
        }
        lines.append("");
    }
    return ("\n".join(lines), data);
}


# ══════════════════════════════════════════════════════════════════
# Wallet Profiling
# ══════════════════════════════════════════════════════════════════

def get_wallet_profile(wallet_address: str) -> str {
    profile  = _get(GAMMA + "/public-profile", params={"address": wallet_address}) or {};
    trades   = _get(DATA + "/trades", params={"user": wallet_address, "limit": 500}) or [];
    positions = _get(DATA + "/positions", params={"user": wallet_address, "limit": 50}) or [];

    name = profile.get("name") or profile.get("pseudonym") or profile.get("displayUsernamePublic") or "Anonymous";
    markets_traded = len({t.get("conditionId") for t in trades});
    buys  = [t for t in trades if t.get("side") == "BUY"];
    sells = [t for t in trades if t.get("side") == "SELL"];
    total_vol = sum(float(t.get("usdcSize", 0)) for t in trades);

    earliest = min((t.get("timestamp", float("inf")) for t in trades), default=None);
    latest   = max((t.get("timestamp", 0) for t in trades), default=None);

    open_pos = len(positions);
    total_cur_val = sum(float(p.get("currentValue", 0)) for p in positions);
    total_cash_pnl = sum(float(p.get("cashPnl", 0)) for p in positions);

    lines = [
        "Wallet Profile: " + wallet_address,
        _divider(),
        "Name:            " + name,
        "Bio:             " + str(profile.get("bio", "N/A")),
        "X (Twitter):     " + str(profile.get("xUsername", "N/A")),
        "Verified:        " + str(profile.get("verifiedBadge", False)),
        "Proxy Wallet:    " + str(profile.get("proxyWallet", wallet_address)),
        _divider("."),
        "Trade History (last " + str(len(trades)) + " fetched):",
        "  First trade:     " + (_ts(earliest) if earliest else "N/A"),
        "  Latest trade:    " + (_ts(latest) if latest else "N/A"),
        "  Markets traded:  " + str(markets_traded),
        "  BUY trades:      " + str(len(buys)),
        "  SELL trades:     " + str(len(sells)),
        "  Total USDC vol:  $" + str(round(total_vol, 2)),
        _divider("."),
        "Open Positions (" + str(open_pos) + "):",
        "  Total cur. value: $" + str(round(total_cur_val, 2)),
        "  Total cash PnL:   $" + str(round(total_cash_pnl, 2)),
    ];
    for p in positions[:5] {
        lines.append(
            "  * " + str(p.get("title", str(p.get("conditionId", "?"))[:20]))
            + "  outcome: " + str(p.get("outcome")) + "  size: " + str(p.get("size"))
            + "  cashPnl: " + str(round(float(p.get("cashPnl", 0)), 2))
        );
    }
    return "\n".join(lines);
}


def get_wallet_trade_history(wallet_address: str, limit: int = 200, condition_id: str = None) -> tuple {
    proxy = _resolve_proxy_wallet(wallet_address);
    params: dict = {"user": proxy, "limit": limit};
    if condition_id {
        params["market"] = condition_id;
    }
    data = _get(DATA + "/trades", params=params) or [];
    if not data {
        return ("No trade history found for wallet: " + wallet_address, []);
    }
    buys  = [t for t in data if t.get("side") == "BUY"];
    sells = [t for t in data if t.get("side") == "SELL"];
    times = sorted([t.get("timestamp", 0) for t in data if t.get("timestamp")]);
    markets_hit: dict = {};
    for t in data {
        key = t.get("title") or t.get("conditionId", "?");
        markets_hit[key] = markets_hit.get(key, 0) + 1;
    }
    lines = [
        "Trade History - wallet: " + wallet_address,
        "Fetched: " + str(len(data)) + " trade(s)",
        ("Period: " + _ts(times[0]) + "  ->  " + _ts(times[-1])) if len(times) >= 2 else "",
        _divider(),
        "BUY trades:   " + str(len(buys)),
        "SELL trades:  " + str(len(sells)),
        "Unique markets: " + str(len(markets_hit)),
        _divider("."),
        "Most traded markets:",
    ];
    sorted_markets = sorted(markets_hit.items(), key=lambda x: x[1], reverse=True);
    for pair in sorted_markets[:8] {
        lines.append("  [" + str(pair[1]) + "x]  " + str(pair[0])[:60]);
    }
    return ("\n".join(lines), data);
}


def get_wallet_pnl(wallet_address: str) -> str {
    open_pos   = _get(DATA + "/positions", params={"user": wallet_address, "limit": 500, "sortBy": "CASHPNL"}) or [];
    closed_pos = _get(DATA + "/closed-positions", params={"user": wallet_address, "limit": 50, "sortBy": "REALIZEDPNL"}) or [];

    open_pnl     = sum(float(p.get("cashPnl", 0)) for p in open_pos);
    realised_pnl = sum(float(p.get("realizedPnl", 0)) for p in closed_pos);
    total_pnl    = open_pnl + realised_pnl;
    wins  = [p for p in closed_pos if float(p.get("realizedPnl", 0)) > 0];
    losses = [p for p in closed_pos if float(p.get("realizedPnl", 0)) < 0];
    win_rate = len(wins) / max(len(closed_pos), 1) * 100;

    lines = [
        "Wallet PnL - " + wallet_address,
        _divider(),
        "Open positions:    " + str(len(open_pos)),
        "Open PnL:          $" + str(round(open_pnl, 2)),
        "Closed positions:  " + str(len(closed_pos)),
        "Realised PnL:      $" + str(round(realised_pnl, 2)),
        "Total PnL:         $" + str(round(total_pnl, 2)),
        _divider("."),
        "Win rate (closed): " + str(round(win_rate, 1)) + "%  (" + str(len(wins)) + " wins / " + str(len(losses)) + " losses)",
    ];
    if closed_pos {
        lines.append("Top 5 closed positions by realised PnL:");
        sorted_closed = sorted(closed_pos, key=lambda p: float(p.get("realizedPnl", 0)), reverse=True);
        for p in sorted_closed[:5] {
            lines.append(
                "  " + str(p.get("title", str(p.get("conditionId", "?"))[:50]))
                + "  outcome: " + str(p.get("outcome"))
                + "  realizedPnl: $" + str(round(float(p.get("realizedPnl", 0)), 2))
            );
        }
    }
    return "\n".join(lines);
}


def score_trade_timing(wallet_address: str, condition_id: str) -> str {
    event_timestamp = _market_end_timestamp(condition_id);
    return score_trade_timing_at(wallet_address, condition_id, event_timestamp);
}


def score_trade_timing_at(wallet_address: str, condition_id: str, event_timestamp: float) -> str {
    (_, wallet_trades) = get_wallet_trade_history(wallet_address, condition_id=condition_id);
    if not wallet_trades {
        return "No trades by " + wallet_address + " on market " + condition_id;
    }
    pre_trades = [t for t in wallet_trades if (t.get("timestamp") or 0) <= event_timestamp];
    if not pre_trades {
        return "Wallet " + wallet_address + " placed no trades before " + _ts(event_timestamp);
    }
    scored: list = [];
    for t in pre_trades {
        ts = t.get("timestamp", 0);
        hours_before = (event_timestamp - ts) / 3600;
        if hours_before < 0.5 {
            recency = 0.0;
        } elif hours_before <= 24 {
            recency = 0.9;
        } elif hours_before <= 72 {
            recency = 0.7;
        } elif hours_before <= 168 {
            recency = 0.4;
        } else {
            recency = 0.15;
        }
        size = float(t.get("size", 0));
        size_score = min(size / 5000, 1.0);
        score = round(recency * 0.7 + size_score * 0.3, 3);
        scored.append((t, score, hours_before));
    }
    overall = sum(item[1] for item in scored) / len(scored);
    lines = [
        "Trade Timing Score - wallet: " + wallet_address,
        "conditionId:        " + condition_id,
        "Reference time:     " + _ts(event_timestamp),
        _divider(),
        "Pre-event trades:   " + str(len(scored)),
        "Overall score:      " + str(round(overall, 3)) + "  (0.0 = lowest, 1.0 = max)",
        _divider("."),
        "Individual trade scores (sorted by score desc):",
    ];
    scored.sort(key=lambda x: x[1], reverse=True);
    for item in scored {
        t = item[0];
        score = item[1];
        hrs = item[2];
        ts_str = _ts(t["timestamp"]) if t.get("timestamp") else "?";
        lines.append(
            "  score=" + str(score) + "  [" + ts_str + "]  " + str(t.get("side", "?"))
            + "  size=" + str(round(float(t.get("size", 0)), 2))
            + "  " + str(round(hrs, 1)) + "h before ref"
        );
    }
    return "\n".join(lines);
}


def get_wallet_activity(wallet_address: str, limit: int = 200) -> tuple {
    data = _get(DATA + "/activity", params={"user": wallet_address, "limit": limit}) or [];
    if not data {
        return ("No activity found for wallet: " + wallet_address, []);
    }
    type_counts: dict = {};
    for a in data {
        atype = a.get("type", "UNKNOWN");
        type_counts[atype] = type_counts.get(atype, 0) + 1;
    }
    times = sorted([a.get("timestamp", 0) for a in data if a.get("timestamp")]);
    lines = [
        "Wallet Activity - " + wallet_address,
        "Fetched: " + str(len(data)) + " events",
        ("Period: " + _ts(times[0]) + "  ->  " + _ts(times[-1])) if len(times) >= 2 else "",
        _divider(),
        "Activity breakdown:",
    ];
    sorted_types = sorted(type_counts.items(), key=lambda x: x[1], reverse=True);
    for pair in sorted_types {
        lines.append("  " + str(pair[0]) + ": " + str(pair[1]));
    }
    lines += [_divider("."), "Last 5 activity events:"];
    sorted_data = sorted(data, key=lambda x: x.get("timestamp", 0), reverse=True);
    for a in sorted_data[:5] {
        ts = _ts(a["timestamp"]) if a.get("timestamp") else "?";
        lines.append(
            "  [" + ts + "]  " + str(a.get("type", "?"))
            + "  size: " + str(a.get("size")) + "  cash: " + str(a.get("usdcSize"))
            + "  " + str(a.get("title", ""))[:40]
        );
    }
    return ("\n".join(lines), data);
}


# ══════════════════════════════════════════════════════════════════
# Market OI & Live Volume
# ══════════════════════════════════════════════════════════════════

def get_market_open_interest(condition_id: str) -> str {
    data = _get(DATA + "/oi", params={"market": condition_id});
    if not data {
        raise Exception("No open interest data for: " + condition_id);
    }
    lines = ["Open Interest - conditionId: " + condition_id, _divider()];
    for item in data {
        lines.append("  Market: " + str(item.get("market")) + "   OI: $" + str(item.get("value")));
    }
    return "\n".join(lines);
}


def get_live_event_volume(event_id: int) -> str {
    data = _get(DATA + "/live-volume", params={"id": event_id});
    if not data {
        raise Exception("No live volume data for event_id: " + str(event_id));
    }
    item = data[0] if data else {};
    total = item.get("total", 0);
    markets = item.get("markets") or [];
    lines = [
        "Live Volume - event_id: " + str(event_id),
        "Total volume: $" + str(total),
        _divider(),
        "Per-market breakdown:",
    ];
    for m in markets {
        lines.append("  conditionId: " + str(m.get("market")) + "   volume: $" + str(m.get("value")));
    }
    return "\n".join(lines);
}
