"""PolyWatch — All 26 investigation tools + ToolRegistry.

Sections:
  1. Helpers
  2. Market Analysis (6 tools)
  3. Statistical Anomaly (6 tools)
  4. News Correlation (6 tools)
  5. Wallet Profiling (5 tools) — V11: derive from trade data
  6. Network / Fund Flow (3 tools) — V11: co-occurrence analysis
  7. Tool Registry
"""

import time;
import math;
import os;
import re;
import json;
import datetime;
import hashlib;
import traceback;
import xml.etree.ElementTree as ET;
import requests;
import email.utils;

import from services.api {
    resolve_market as _resolve_market_raw,
    get_all_trades as _get_all_trades_raw,
    get_price_history as _get_price_history_raw
}

# ═══════════════════════════════════════════════════════════════════
# 1. HELPERS
# ═══════════════════════════════════════════════════════════════════

# ── Per-investigation cache ────────────────────────────────────
# Caches expensive API results so they are fetched once per market
# per investigation run. Call clear_investigation_cache() between runs.
glob _investigation_cache: dict = {};

def clear_investigation_cache() {
    """Reset cache between investigation runs.""";
    _investigation_cache.clear();
}

def _cached_resolve_market(market_id: str) -> dict {
    key = ("resolve_market", market_id);
    if key in _investigation_cache {
        return _investigation_cache[key];
    }
    result = _resolve_market_raw(market_id);
    _investigation_cache[key] = result;
    return result;
}

def _cached_get_all_trades(condition_id: str, max_trades: int = 200) -> list {
    key = ("get_all_trades", condition_id, max_trades);
    if key in _investigation_cache {
        return _investigation_cache[key];
    }
    result = _get_all_trades_raw(condition_id, max_trades=max_trades);
    _investigation_cache[key] = result;
    return result;
}

def _cached_get_price_history(condition_id: str, fidelity: int = 60) -> list {
    key = ("get_price_history", condition_id, fidelity);
    if key in _investigation_cache {
        return _investigation_cache[key];
    }
    result = _get_price_history_raw(condition_id, fidelity=fidelity);
    _investigation_cache[key] = result;
    return result;
}

# Convenience aliases used by the rest of the file
def resolve_market(market_id: str) -> dict {
    return _cached_resolve_market(market_id);
}

def get_all_trades(condition_id: str, max_trades: int = 200) -> list {
    return _cached_get_all_trades(condition_id, max_trades=max_trades);
}

def get_price_history(condition_id: str, fidelity: int = 60) -> list {
    return _cached_get_price_history(condition_id, fidelity=fidelity);
}

def _parse_ts(ts_str: str | None) -> float | None {
    """Parse timestamp to unix epoch seconds.
    Accepts: ISO 8601 strings, unix epoch seconds (int or str), unix millis.""";
    if not ts_str { return None; }
    s = str(ts_str).strip();
    # Try pure numeric first (unix epoch seconds or milliseconds)
    try {
        val = float(s);
        if val > 1e12 {
            # Milliseconds — convert to seconds
            return val / 1000.0;
        }
        if val > 1e8 {
            # Seconds — valid unix epoch
            return val;
        }
    } except (ValueError, TypeError) {
        0;
    }
    # Try ISO 8601
    try {
        dt = datetime.datetime.fromisoformat(s.replace("Z", "+00:00"));
        return dt.timestamp();
    } except (ValueError, TypeError) {
        return None;
    }
}

def _resolve_condition_id(market_id: str) -> str {
    info = resolve_market(market_id);
    return info.get("condition_id", market_id);
}

# ═══════════════════════════════════════════════════════════════════
# 2. MARKET ANALYSIS TOOLS
# ═══════════════════════════════════════════════════════════════════

def get_market_info(market_id: str) -> dict {
    """Fetch real market metadata from the Gamma API. Cached per investigation.""";
    cache_key = ("get_market_info", market_id);
    if cache_key in _investigation_cache {
        return _investigation_cache[cache_key];
    }
    info = resolve_market(market_id);
    if not info.get("resolved") {
        info = {"market_id": market_id, "title": f"Unknown market: {market_id}", "resolved": False};
    }
    prices_raw = info.get("outcome_prices", "");
    if isinstance(prices_raw, str) and prices_raw {
        try { prices_list = json.loads(prices_raw); }
        except Exception { prices_list = []; }
    } elif isinstance(prices_raw, list) {
        prices_list = prices_raw;
    } else {
        prices_list = [];
    }
    yes_price = float(prices_list[0]) if len(prices_list) > 0 else None;
    no_price = float(prices_list[1]) if len(prices_list) > 1 else None;
    data = {
        "market_id": market_id,
        "title": info.get("title", ""),
        "slug": info.get("slug", ""),
        "outcomes": info.get("outcomes", ["Yes", "No"]),
        "end_date": info.get("end_date", ""),
        "active": info.get("active", False),
        "closed": info.get("closed", False),
        "current_prices": {"YES": yes_price, "NO": no_price},
        "total_volume_usdc": float(info.get("volume", 0) or 0),
        "volume_24h_usdc": float(info.get("volume_24h", 0) or 0),
        "liquidity_usdc": float(info.get("liquidity", 0) or 0),
        "best_bid": info.get("best_bid"),
        "best_ask": info.get("best_ask"),
        "last_trade_price": info.get("last_trade_price"),
        "condition_id": info.get("condition_id", "")
    };
    status = "active" if data["active"] else ("closed" if data["closed"] else "unknown");
    summary = (
        f"Market '{data['title']}' ({status}). "
        f"Current YES price: {yes_price}. "
        f"Total volume: ${data['total_volume_usdc']:,.0f}. "
        f"Liquidity: ${data['liquidity_usdc']:,.0f}."
    );
    result = {"data": data, "summary": summary};
    _investigation_cache[cache_key] = result;
    return result;
}

def get_market_price_history(market_id: str, start_time: str | None = None,
                             end_time: str | None = None) -> dict {
    """Fetch real price history from CLOB API.""";
    info = resolve_market(market_id);
    clob_ids_raw = info.get("clob_token_ids", []);
    # Gamma API may return clobTokenIds as a JSON string
    if isinstance(clob_ids_raw, str) {
        try { clob_ids_raw = json.loads(clob_ids_raw); }
        except Exception { clob_ids_raw = []; }
    }
    raw = [];
    if clob_ids_raw {
        raw = get_price_history(clob_ids_raw[0], fidelity=60);
    }
    if not raw {
        # Fallback: try condition_id then market_id
        condition_id = info.get("condition_id", market_id);
        raw = get_price_history(condition_id, fidelity=60);
        if not raw and market_id != condition_id {
            raw = get_price_history(market_id, fidelity=60);
        }
    }
    prices = [];
    for point in raw {
        ts = point.get("t");
        p = point.get("p");
        if ts is not None and p is not None {
            prices.append({"timestamp": ts, "price_yes": round(float(p), 4),
                           "price_no": round(1 - float(p), 4)});
        }
    }
    if not prices {
        summary = f"No price history available for {market_id} from CLOB API.";
    } else {
        first_p = prices[0]["price_yes"];
        last_p = prices[-1]["price_yes"];
        summary = (
            f"Price history for {market_id}: {len(prices)} data points. "
            f"First: {first_p:.4f} YES. Latest: {last_p:.4f} YES. "
            f"Change: {last_p - first_p:+.4f}."
        );
    }
    return {"data": prices, "summary": summary};
}

def get_market_trades(market_id: str, start_time: str | None = None,
                      end_time: str | None = None) -> dict {
    """Fetch real trades from the Data API. Results cached per investigation.""";
    cache_key = ("get_market_trades", market_id);
    if cache_key in _investigation_cache {
        return _investigation_cache[cache_key];
    }
    condition_id = _resolve_condition_id(market_id);
    raw_trades = get_all_trades(condition_id, max_trades=200);
    trades = [];
    for (i, t) in enumerate(raw_trades) {
        side = t.get("side", "");
        outcome = t.get("outcome", "");
        if side == "BUY" and outcome == "Yes" { direction = "BUY_YES"; }
        elif side == "BUY" and outcome == "No" { direction = "BUY_NO"; }
        elif side == "SELL" and outcome == "Yes" { direction = "SELL_YES"; }
        elif side == "SELL" and outcome == "No" { direction = "SELL_NO"; }
        else { direction = f"{side}_{outcome}".upper(); }
        ts_epoch = t.get("timestamp", 0);
        size = float(t.get("size", 0));
        price = float(t.get("price", 0));
        size_usdc = round(size * price, 2);
        trades.append({
            "trade_id": t.get("transactionHash", f"trade_{i:04d}"),
            "wallet": t.get("proxyWallet", "unknown"),
            "direction": direction, "size": round(size, 4),
            "price": round(price, 4), "size_usdc": size_usdc,
            "timestamp": ts_epoch, "outcome": outcome, "side": side
        });
    }
    trades.sort(key=lambda x: x["timestamp"]);
    wallets = {t["wallet"] for t in trades};
    yes_trades = sum(1 for t in trades if "YES" in t["direction"]);
    total_vol = sum(t["size_usdc"] for t in trades);
    n = len(trades);
    summary = (
        f"{n} trades on {market_id}. {len(wallets)} unique wallets. "
        f"{yes_trades}/{n} ({yes_trades/max(n,1)*100:.0f}%) in YES direction. "
        f"Total volume: ${total_vol:,.0f} USDC."
    );
    result = {"data": trades, "summary": summary};
    _investigation_cache[cache_key] = result;
    return result;
}

def get_large_trades(market_id: str, size_threshold: float) -> dict {
    all_result = get_market_trades(market_id);
    all_trades = all_result["data"];
    large = [t for t in all_trades if t["size_usdc"] >= size_threshold];
    wallets = {t["wallet"] for t in large};
    total_vol = sum(t["size_usdc"] for t in large);
    summary = (
        f"{len(large)} trades above ${size_threshold:,.0f} USDC on {market_id}. "
        f"Wallets involved: {len(wallets)}. "
        f"Total volume in large trades: ${total_vol:,.0f} USDC."
    );
    return {"data": large, "summary": summary};
}

def get_pre_event_trades(market_id: str, event_timestamp: str,
                         lookback_hours: float = 24.0) -> dict {
    event_epoch = _parse_ts(event_timestamp);
    if event_epoch is None {
        return {"data": [], "summary": f"Could not parse event_timestamp: {event_timestamp}"};
    }
    all_result = get_market_trades(market_id);
    all_trades = all_result["data"];
    cutoff = event_epoch - (lookback_hours * 3600);
    pre = [];
    for t in all_trades {
        ts = t.get("timestamp", 0);
        if isinstance(ts, str) { ts = _parse_ts(ts) or 0; }
        if cutoff <= ts <= event_epoch {
            hours_before = (event_epoch - ts) / 3600;
            t["hours_before_resolution"] = round(hours_before, 2);
            pre.append(t);
        }
    }
    wallets = {t["wallet"] for t in pre};
    yes_count = sum(1 for t in pre if "YES" in t.get("direction", ""));
    total_vol = sum(t["size_usdc"] for t in pre);
    wallet_volumes: dict = {};
    for t in pre {
        wallet_volumes.setdefault(t["wallet"], 0);
        wallet_volumes[t["wallet"]] += t["size_usdc"];
    }
    suspicious = sorted(wallet_volumes, key=lambda w: wallet_volumes[w], reverse=True)[:3];
    summary = (
        f"{len(pre)} trades in the {lookback_hours}h pre-event window on {market_id}. "
        f"{len(wallets)} unique wallets. "
        f"{yes_count}/{len(pre)} ({yes_count/max(len(pre),1)*100:.0f}%) in YES direction. "
        f"Total pre-event volume: ${total_vol:,.0f} USDC. "
        f"Top wallets by volume: {suspicious[:3]}."
    );
    return {"data": pre, "summary": summary};
}

def get_market_movers(market_id: str, time_window: str = "24h") -> dict {
    all_result = get_market_trades(market_id);
    all_trades = all_result["data"];
    wallet_data: dict = {};
    for t in all_trades {
        w = t["wallet"];
        if w not in wallet_data {
            wallet_data[w] = {"wallet": w, "net_position_change_usdc": 0.0,
                              "trade_count": 0, "buy_yes_vol": 0, "buy_no_vol": 0};
        }
        wallet_data[w]["trade_count"] += 1;
        if "YES" in t.get("direction", "") and "BUY" in t.get("direction", "") {
            wallet_data[w]["net_position_change_usdc"] += t["size_usdc"];
            wallet_data[w]["buy_yes_vol"] += t["size_usdc"];
        } elif "NO" in t.get("direction", "") and "BUY" in t.get("direction", "") {
            wallet_data[w]["net_position_change_usdc"] -= t["size_usdc"];
            wallet_data[w]["buy_no_vol"] += t["size_usdc"];
        }
    }
    movers = list(wallet_data.values());
    for m in movers {
        m["direction"] = "YES" if m["net_position_change_usdc"] > 0 else "NO";
        m["net_position_change_usdc"] = round(m["net_position_change_usdc"], 2);
    }
    movers.sort(key=lambda m: abs(m["net_position_change_usdc"]), reverse=True);
    top = movers[:3] if movers else [{"wallet": "none", "net_position_change_usdc": 0, "direction": "N/A"}];
    summary = (
        f"Top market movers on {market_id} ({len(movers)} wallets total). "
        f"Largest mover: {top[0]['wallet'][:12]}... "
        f"with ${top[0]['net_position_change_usdc']:,.0f} net change in {top[0]['direction']} direction."
    );
    return {"data": movers[:20], "summary": summary};
}

# ═══════════════════════════════════════════════════════════════════
# 3. STATISTICAL ANOMALY TOOLS
# ═══════════════════════════════════════════════════════════════════

def compute_abnormal_volume(market_id: str, event_timestamp: str) -> dict {
    event_epoch = _parse_ts(event_timestamp);
    all_result = get_market_trades(market_id);
    trades = all_result["data"];
    if not trades or event_epoch is None {
        return {"data": {"market_id": market_id, "suspicion_level": "UNKNOWN",
                         "error": "No trades or bad timestamp"},
                "summary": f"No trade data available for {market_id}."};
    }
    pre_start = event_epoch - 48 * 3600;
    pre_trades = [t for t in trades if pre_start <= t.get("timestamp", 0) <= event_epoch];
    baseline_trades = [t for t in trades if t.get("timestamp", 0) < pre_start];
    pre_volume = sum(t["size_usdc"] for t in pre_trades);
    baseline_volume = sum(t["size_usdc"] for t in baseline_trades);
    if baseline_trades {
        ts_sorted = sorted(t.get("timestamp", 0) for t in baseline_trades);
        baseline_span_h = max((ts_sorted[-1] - ts_sorted[0]) / 3600, 1);
        baseline_48h_equiv = baseline_volume * (48 / baseline_span_h);
    } else {
        baseline_48h_equiv = max(pre_volume * 0.3, 1);
    }
    ratio = pre_volume / max(baseline_48h_equiv, 1);
    z_score = (ratio - 1.0) / 0.3 if ratio > 1 else 0;
    p_value = max(0.0001, math.exp(-0.5 * z_score)) if z_score > 0 else 1.0;
    suspicion = "HIGH" if ratio > 4.0 else ("MEDIUM" if ratio > 2.0 else "LOW");
    data = {
        "market_id": market_id, "event_timestamp": event_timestamp,
        "baseline_volume_usdc": round(baseline_48h_equiv, 2),
        "pre_event_volume_usdc": round(pre_volume, 2),
        "abnormal_volume_ratio": round(ratio, 3),
        "z_score": round(z_score, 3), "p_value": round(p_value, 6),
        "suspicion_level": suspicion,
        "pre_event_trade_count": len(pre_trades),
        "baseline_trade_count": len(baseline_trades)
    };
    summary = (
        f"Abnormal volume analysis for {market_id}: pre-event volume was {ratio:.1f}x the baseline "
        f"(z={z_score:.2f}, p={p_value:.4f}). Suspicion level: {suspicion}. "
        f"Pre-event: ${pre_volume:,.0f} ({len(pre_trades)} trades), "
        f"Baseline 48h equiv: ${baseline_48h_equiv:,.0f} ({len(baseline_trades)} trades)."
    );
    return {"data": data, "summary": summary};
}

def compute_price_run_up(market_id: str, event_timestamp: str,
                         baseline_window: str | None = "7d") -> dict {
    event_epoch = _parse_ts(event_timestamp);
    all_result = get_market_trades(market_id);
    trades = all_result["data"];
    if not trades or event_epoch is None {
        return {"data": {"market_id": market_id, "suspicion_level": "UNKNOWN"},
                "summary": f"No trade data for price run-up analysis on {market_id}."};
    }
    windows = [
        ("7d_to_3d", 7 * 24, 3 * 24),
        ("3d_to_1d", 3 * 24, 1 * 24),
        ("24h_to_6h", 24, 6),
        ("6h_to_1h", 6, 1),
        ("1h_to_0h", 1, 0)
    ];
    drift_buckets = {};
    prev_price = None;
    cumulative = 0.0;
    for (name, start_h, end_h) in windows {
        t_start = event_epoch - start_h * 3600;
        t_end = event_epoch - end_h * 3600;
        window_trades = [t for t in trades if t_start <= t.get("timestamp", 0) <= t_end];
        avg_p = sum(t["price"] for t in window_trades) / len(window_trades) if window_trades else None;
        if avg_p is not None and prev_price is not None {
            drift = avg_p - prev_price;
            cumulative += drift;
            drift_buckets[name] = {"window_drift": round(drift, 4),
                                   "cumulative_drift": round(cumulative, 4),
                                   "avg_price": round(avg_p, 4)};
        } elif avg_p is not None {
            drift_buckets[name] = {"window_drift": 0.0,
                                   "cumulative_drift": 0.0,
                                   "avg_price": round(avg_p, 4)};
        }
        if avg_p is not None { prev_price = avg_p; }
    }
    total_drift = cumulative;
    suspicion = "HIGH" if total_drift > 0.25 else ("MEDIUM" if total_drift > 0.10 else "LOW");
    data = {
        "market_id": market_id, "event_timestamp": event_timestamp,
        "baseline_window": baseline_window, "drift_by_window": drift_buckets,
        "total_pre_event_drift": round(total_drift, 4), "suspicion_level": suspicion
    };
    summary = (
        f"Price run-up analysis for {market_id}: total pre-event drift = {total_drift:+.1%}. "
        f"Suspicion: {suspicion}. Windows analyzed: {len(drift_buckets)}."
    );
    if "6h_to_1h" in drift_buckets {
        summary += f" Final 6h drift: {drift_buckets['6h_to_1h']['window_drift']:+.1%}.";
    }
    return {"data": data, "summary": summary};
}

def score_trade_timing(wallet_address: str, market_id: str,
                       event_timestamp: str) -> dict {
    event_epoch = _parse_ts(event_timestamp);
    all_result = get_market_trades(market_id);
    trades = all_result["data"];
    if event_epoch is None {
        return {"data": {"wallet": wallet_address, "suspicion_level": "UNKNOWN"},
                "summary": "Could not parse event timestamp."};
    }
    wallet_trades = [t for t in trades if t.get("wallet", "").lower() == wallet_address.lower()];
    if not wallet_trades {
        return {"data": {"wallet": wallet_address, "market_id": market_id,
                         "trades_before_event": 0, "timing_score": 0,
                         "suspicion_level": "LOW"},
                "summary": f"No trades found for {wallet_address[:12]}... on {market_id}."};
    }
    before_event = [t for t in wallet_trades if t.get("timestamp", 0) <= event_epoch];
    after_event = [t for t in wallet_trades if t.get("timestamp", 0) > event_epoch];
    if before_event {
        hours_before = [(event_epoch - t.get("timestamp", 0)) / 3600 for t in before_event];
        avg_hours = sum(hours_before) / len(hours_before);
        min_hours = min(hours_before);
    } else {
        avg_hours = 999;
        min_hours = 999;
    }
    raw_score = 100 * (1 - min(avg_hours / 48, 1));
    timing_score = max(0, min(100, raw_score));
    suspicion = "HIGH" if timing_score > 70 else ("MEDIUM" if timing_score > 40 else "LOW");
    data = {
        "wallet": wallet_address, "market_id": market_id,
        "trades_before_event": len(before_event),
        "trades_after_event": len(after_event),
        "avg_hours_before_resolution": round(avg_hours, 2),
        "earliest_trade_hours_before": round(min_hours, 2),
        "timing_score": round(timing_score, 1),
        "suspicion_level": suspicion
    };
    summary = (
        f"Trade timing for {wallet_address[:12]}...: {timing_score:.0f}/100. "
        f"{len(before_event)} trades before event, avg {avg_hours:.1f}h before. "
        f"Suspicion: {suspicion}."
    );
    return {"data": data, "summary": summary};
}

def compare_trader_to_peers(wallet_address: str, market_id: str) -> dict {
    all_result = get_market_trades(market_id);
    trades = all_result["data"];
    target_trades = [t for t in trades if t.get("wallet", "").lower() == wallet_address.lower()];
    other_wallets: dict = {};
    for t in trades {
        w = t.get("wallet", "");
        if w.lower() != wallet_address.lower() {
            other_wallets.setdefault(w, []).append(t);
        }
    }
    if not target_trades {
        return {"data": {"wallet": wallet_address, "suspicion_level": "UNKNOWN"},
                "summary": f"No trades for {wallet_address[:12]}... on this market."};
    }
    target_yes = sum(1 for t in target_trades if "YES" in t.get("direction", ""));
    target_winrate = target_yes / max(len(target_trades), 1);
    target_avg_size = sum(t["size_usdc"] for t in target_trades) / max(len(target_trades), 1);
    peer_winrates = [];
    peer_avg_sizes = [];
    for (w, w_trades) in other_wallets.items() {
        w_yes = sum(1 for t in w_trades if "YES" in t.get("direction", ""));
        peer_winrates.append(w_yes / max(len(w_trades), 1));
        peer_avg_sizes.append(sum(t["size_usdc"] for t in w_trades) / max(len(w_trades), 1));
    }
    peer_avg_wr = sum(peer_winrates) / max(len(peer_winrates), 1);
    peer_avg_sz = sum(peer_avg_sizes) / max(len(peer_avg_sizes), 1);
    behavioral_delta = target_winrate - peer_avg_wr;
    size_ratio = target_avg_size / max(peer_avg_sz, 0.01);
    suspicion = "HIGH" if behavioral_delta > 0.2 and size_ratio > 3 else ("MEDIUM" if behavioral_delta > 0.1 else "LOW");
    data = {
        "wallet": wallet_address, "market_id": market_id,
        "win_rate_this_market": round(target_winrate, 3),
        "peer_average_win_rate": round(peer_avg_wr, 3),
        "behavioral_discontinuity": round(behavioral_delta, 3),
        "peer_outperformance": round(behavioral_delta, 3),
        "this_market_avg_size_usdc": round(target_avg_size, 2),
        "peer_avg_size_usdc": round(peer_avg_sz, 2),
        "size_ratio": round(size_ratio, 1),
        "target_trade_count": len(target_trades),
        "peer_count": len(other_wallets),
        "suspicion_level": suspicion
    };
    summary = (
        f"Peer comparison for {wallet_address[:12]}...: "
        f"YES rate = {target_winrate:.0%} vs peer avg {peer_avg_wr:.0%} "
        f"(delta: {behavioral_delta:+.0%}). Size ratio: {size_ratio:.1f}x. "
        f"Suspicion: {suspicion}."
    );
    return {"data": data, "summary": summary};
}

def score_top_suspicious_wallets(market_id: str, event_timestamp: str,
                                 top_n: int = 5,
                                 news_timestamp: str | None = None) -> dict {
    event_epoch = _parse_ts(event_timestamp);
    all_result = get_market_trades(market_id);
    trades = all_result["data"];
    if not trades or event_epoch is None {
        return {"data": {"market_id": market_id, "wallet_scores": [],
                         "suspicion_level": "UNKNOWN"},
                "summary": f"No trades available for multi-wallet timing on {market_id}."};
    }
    news_epoch = _parse_ts(news_timestamp) if news_timestamp else None;
    pre_event_trades = [t for t in trades if t.get("timestamp", 0) <= event_epoch];
    using_all_trades = False;
    if pre_event_trades { source_trades = pre_event_trades; }
    else { source_trades = trades; using_all_trades = True; }
    wallet_volumes: dict = {};
    wallet_trade_times: dict = {};
    wallet_directions: dict = {};
    for t in source_trades {
        w = t.get("wallet", "");
        wallet_volumes[w] = wallet_volumes.get(w, 0) + t.get("size_usdc", 0);
        wallet_trade_times.setdefault(w, []).append(t.get("timestamp", 0));
        wallet_directions.setdefault(w, []).append(t.get("side", ""));
    }
    top_wallets = sorted(wallet_volumes, key=lambda w: wallet_volumes[w], reverse=True)[:top_n];
    wallet_scores = [];
    for w in top_wallets {
        times = sorted(wallet_trade_times.get(w, []));
        if not times { continue; }
        first_trade_ts = times[0];
        last_trade_ts = times[-1];
        first_trade_vs_event_delta = first_trade_ts - event_epoch;
        if using_all_trades {
            directions = wallet_directions.get(w, []);
            yes_pct = sum(1 for d in directions if d.lower() in ("buy", "yes")) / max(len(directions), 1);
            vol_pct = wallet_volumes[w] / max(sum(wallet_volumes.values()), 1) * 100;
            timing_score = min(100, vol_pct * 3 + (yes_pct * 40 if yes_pct > 0.8 else 0));
            avg_hours_before = abs(first_trade_vs_event_delta) / 3600;
        } else {
            avg_hours_before = sum((event_epoch - t) / 3600 for t in times) / len(times);
            raw_score = 100 * (1 - min(avg_hours_before / 48, 1));
            timing_score = max(0, min(100, raw_score));
        }
        entry: dict = {
            "wallet": w,
            "pre_event_volume_usdc": round(wallet_volumes[w], 2),
            "trade_count": len(times),
            "first_trade_vs_event_delta": round(first_trade_vs_event_delta),
            "avg_hours_before_event": round(avg_hours_before, 2),
            "timing_score": round(timing_score, 1),
            "cluster_execution_span": round((last_trade_ts - first_trade_ts) / 3600, 2),
            "post_event_only": using_all_trades
        };
        if news_epoch is not None {
            first_trade_vs_news = first_trade_ts - news_epoch;
            entry["first_trade_vs_news_delta"] = round(first_trade_vs_news);
            entry["traded_before_news"] = first_trade_vs_news < 0;
        }
        all_avg_hours = [];
        for (aw, at) in wallet_trade_times.items() {
            if using_all_trades { avg_h = abs(at[0] - event_epoch) / 3600 if at else 0; }
            else { avg_h = sum((event_epoch - tt) / 3600 for tt in at) / max(len(at), 1); }
            all_avg_hours.append(avg_h);
        }
        if all_avg_hours {
            rank = sum(1 for h in all_avg_hours if h >= avg_hours_before);
            entry["timing_percentile"] = round(rank / len(all_avg_hours) * 100, 1);
        } else { entry["timing_percentile"] = 50.0; }
        wallet_scores.append(entry);
    }
    avg_score = sum(ws["timing_score"] for ws in wallet_scores) / max(len(wallet_scores), 1);
    suspicion = "HIGH" if avg_score > 70 else ("MEDIUM" if avg_score > 40 else "LOW");
    pre_news_count = sum(1 for ws in wallet_scores if ws.get("traded_before_news", False));
    data = {
        "market_id": market_id, "event_timestamp": event_timestamp,
        "wallets_scored": len(wallet_scores), "wallet_scores": wallet_scores,
        "avg_timing_score": round(avg_score, 1), "suspicion_level": suspicion,
        "pre_news_trade_count": pre_news_count if news_epoch else None,
        "using_post_event_trades": using_all_trades
    };
    summary = (
        f"Multi-wallet timing for {market_id}: scored {len(wallet_scores)} top wallets. "
        f"Avg timing score: {avg_score:.0f}/100. Suspicion: {suspicion}."
    );
    if using_all_trades { summary += " Note: All available trades are post-event (API returns recent only)."; }
    if news_epoch { summary += f" {pre_news_count}/{len(wallet_scores)} traded before news."; }
    return {"data": data, "summary": summary};
}

def find_synchronized_traders(market_id: str, time_window: str = "1h",
                              direction: str | None = "YES") -> dict {
    all_result = get_market_trades(market_id);
    trades = all_result["data"];
    window_map = {"5m": 300, "15m": 900, "30m": 1800, "1h": 3600, "2h": 7200};
    window_sec = window_map.get(time_window, 3600);
    if direction { dir_trades = [t for t in trades if direction.upper() in t.get("direction", "")]; }
    else { dir_trades = trades; }
    if not dir_trades {
        return {"data": [], "summary": f"No {direction} trades found on {market_id}."};
    }
    dir_trades.sort(key=lambda t: t.get("timestamp", 0));
    clusters = [];
    current_cluster: list = [];
    for t in dir_trades {
        if not current_cluster { current_cluster = [t]; }
        elif t.get("timestamp", 0) - current_cluster[0].get("timestamp", 0) <= window_sec {
            current_cluster.append(t);
        } else {
            if len(current_cluster) >= 2 {
                wallets = list({tr["wallet"] for tr in current_cluster});
                if len(wallets) >= 2 {
                    total_vol = sum(tr["size_usdc"] for tr in current_cluster);
                    time_span = current_cluster[-1].get("timestamp", 0) - current_cluster[0].get("timestamp", 0);
                    clusters.append({
                        "cluster_id": len(clusters) + 1, "wallets": wallets,
                        "direction": direction or "MIXED",
                        "time_window_minutes": round(time_span / 60, 1),
                        "total_volume_usdc": round(total_vol, 2),
                        "trade_count": len(current_cluster),
                        "avg_trade_size_usdc": round(total_vol / len(current_cluster), 2),
                        "suspicion_score": min(95, round(len(wallets) * 15 + total_vol / 500, 1))
                    });
                }
            }
            current_cluster = [t];
        }
    }
    if len(current_cluster) >= 2 {
        wallets = list({tr["wallet"] for tr in current_cluster});
        if len(wallets) >= 2 {
            total_vol = sum(tr["size_usdc"] for tr in current_cluster);
            time_span = current_cluster[-1].get("timestamp", 0) - current_cluster[0].get("timestamp", 0);
            clusters.append({
                "cluster_id": len(clusters) + 1, "wallets": wallets,
                "direction": direction or "MIXED",
                "time_window_minutes": round(time_span / 60, 1),
                "total_volume_usdc": round(total_vol, 2),
                "trade_count": len(current_cluster),
                "avg_trade_size_usdc": round(total_vol / len(current_cluster), 2),
                "suspicion_score": min(95, round(len(wallets) * 15 + total_vol / 500, 1))
            });
        }
    }
    total_wallets = sum(len(c["wallets"]) for c in clusters);
    top_score = max((c["suspicion_score"] for c in clusters), default=0);
    summary = (
        f"Found {len(clusters)} synchronized cluster(s) on {market_id} "
        f"({total_wallets} wallets). Top suspicion: {top_score:.0f}/100."
    );
    return {"data": clusters, "summary": summary};
}

# ═══════════════════════════════════════════════════════════════════
# 4. NEWS CORRELATION TOOLS
# ═══════════════════════════════════════════════════════════════════

glob _NEWSAPI_KEY: str = os.environ.get("NEWSAPI_API_KEY", "");
glob _WEBZ_KEY: str = os.environ.get("WEBZ_API_KEY", "");
glob _NEWS_MIN_INTERVAL: float = 0.25;
glob _news_state: dict = {"last_request": 0.0};

glob _STOPWORDS: set = {
    "the", "a", "an", "in", "on", "at", "to", "for", "of", "is", "are",
    "was", "were", "will", "be", "been", "being", "have", "has", "had",
    "do", "does", "did", "it", "its", "this", "that", "with", "from",
    "by", "as", "or", "and", "but", "if", "not", "no", "so", "up",
    "out", "about", "into", "over", "after", "before", "between",
    "through", "during", "each", "few", "more", "most", "other", "some",
    "such", "than", "too", "very", "can", "just", "should", "now",
    "detect", "insider", "trading", "polymarket", "market", "prediction"
};

glob _RELIABLE_SOURCES: set = {
    "reuters", "associated press", "ap news", "bbc news", "bbc",
    "the new york times", "washington post", "the guardian",
    "bloomberg", "cnbc", "financial times", "wall street journal",
    "al jazeera", "cnn", "nbc news", "abc news", "cbs news",
    "politico", "the hill", "axios", "espn", "usa today",
    "foreign affairs", "the jerusalem post", "ncaa.com"
};

def _rfc2822_to_iso(date_str: str) -> str | None {
    try {
        dt = email.utils.parsedate_to_datetime(date_str);
        return dt.isoformat();
    } except Exception {
        try {
            dt = datetime.datetime.strptime(date_str, "%a, %d %b %Y %H:%M:%S %Z");
            return dt.replace(tzinfo=datetime.timezone.utc).isoformat();
        } except Exception { return None; }
    }
}

def _gnews_rss_search(query: str, start_date: str | None = None,
                      end_date: str | None = None,
                      max_results: int = 100) -> list {
    elapsed = time.monotonic() - _news_state["last_request"];
    if elapsed < _NEWS_MIN_INTERVAL { time.sleep(_NEWS_MIN_INTERVAL - elapsed); }
    _news_state["last_request"] = time.monotonic();
    q = query;
    if start_date { q += f" after:{start_date}"; }
    if end_date { q += f" before:{end_date}"; }
    try {
        resp = requests.get("https://news.google.com/rss/search", params={
            "q": q, "hl": "en-US", "gl": "US", "ceid": "US:en"
        }, timeout=20);
        resp.raise_for_status();
    } except Exception as e {
        print(f"[NEWS DEBUG] Google News RSS request failed: {e}");
        return [];
    }
    try { xml_root = ET.fromstring(resp.content); }
    except Exception as e {
        print(f"[NEWS DEBUG] Google News RSS XML parse failed: {e}");
        return [];
    }
    articles = [];
    found_items = xml_root.findall(".//item");
    print(f"[NEWS DEBUG] Google RSS returned {len(found_items)} items for query: {q[:80]}");
    for item in found_items {
        title_el = item.find("title");
        pub_el = item.find("pubDate");
        link_el = item.find("link");
        source_el = item.find("source");
        desc_el = item.find("description");
        title = title_el.text if title_el is not None else "";
        pub_date = pub_el.text if pub_el is not None else "";
        link = link_el.text if link_el is not None else "";
        source = source_el.text if source_el is not None else "";
        desc = desc_el.text if desc_el is not None else "";
        iso_date = _rfc2822_to_iso(pub_date) if pub_date else None;
        articles.append({
            "title": title, "source": {"name": source},
            "publishedAt": iso_date, "url": link,
            "description": (desc or "")[:300]
        });
    }
    return articles[:max_results];
}

def _webzio_search(query: str, start_date: str | None = None,
                   end_date: str | None = None,
                   max_results: int = 50) -> list {
    if not _WEBZ_KEY { return []; }
    try {
        import webzio;
        webzio.config(token=_WEBZ_KEY);
        params = {"q": query, "size": min(max_results, 100)};
        if start_date {
            try {
                dt = datetime.datetime.fromisoformat(start_date + "T00:00:00+00:00");
                params["ts"] = int(dt.timestamp() * 1000);
            } except (ValueError, TypeError) { }
        }
        result = webzio.query("filterWebContent", params);
        articles = [];
        for post in (result.posts or []) {
            pub = post.get("published") or post.get("crawled") or "";
            articles.append({
                "title": post.get("title", ""),
                "source": {"name": post.get("thread", {}).get("site", "unknown")},
                "publishedAt": pub, "url": post.get("url", ""),
                "description": (post.get("text") or "")[:300]
            });
        }
        return articles;
    } except Exception as e {
        print(f"[NEWS DEBUG] Webz.io search failed: {e}");
        return [];
    }
}

def _extract_query_components(text: str) -> dict {
    words = text.split();
    clean = [w for w in words if w.lower().strip(".,!?\"'()") not in _STOPWORDS];
    entities = [];
    i = 0;
    while i < len(words) {
        w = words[i].strip(".,!?\"'()");
        if w and w[0].isupper() and w.lower() not in _STOPWORDS and len(w) > 1 {
            entity_parts = [w];
            j = i + 1;
            while j < len(words) {
                nw = words[j].strip(".,!?\"'()");
                if nw and nw[0].isupper() and len(nw) > 1 { entity_parts.append(nw); j += 1; }
                else { break; }
            }
            entity = " ".join(entity_parts);
            if len(entity) > 2 { entities.append(entity); }
            i = j;
        } else { i += 1; }
    }
    event_types = [];
    event_keywords = {
        "election": "election", "vote": "vote", "war": "military conflict",
        "military": "military", "troops": "military deployment",
        "attack": "attack", "invasion": "invasion", "arrest": "arrest",
        "championship": "championship", "game": "game",
        "tournament": "tournament", "final": "final", "winner": "winner",
        "president": "presidency", "sanctions": "sanctions", "nuclear": "nuclear",
        "trade": "trade deal", "tariff": "tariff", "ncaa": "NCAA",
        "basketball": "basketball", "football": "football", "iran": "Iran"
    };
    text_lower = text.lower();
    for (kw, etype) in event_keywords.items() {
        if kw in text_lower { event_types.append(etype); }
    }
    keywords = [w.strip(".,!?\"'()") for w in clean if len(w.strip(".,!?\"'()")) > 3];
    return {"entities": entities[:5], "event_types": event_types[:3], "keywords": keywords[:8]};
}

def _generate_queries(text: str) -> list {
    components = _extract_query_components(text);
    queries = [];
    if components["entities"] and components["event_types"] {
        base = " ".join(components["entities"][:3]) + " " + components["event_types"][0];
        queries.append({"query": base.strip(), "type": "base", "priority": 1});
    }
    if components["entities"] {
        entity_q = " ".join(components["entities"][:4]);
        queries.append({"query": entity_q.strip(), "type": "entity", "priority": 2});
    }
    if components["keywords"] {
        kw_q = " ".join(components["keywords"][:5]);
        queries.append({"query": kw_q.strip(), "type": "keyword", "priority": 3});
    }
    fallback_words = [w for w in text.split() if w.lower() not in _STOPWORDS][:6];
    if fallback_words {
        queries.append({"query": " ".join(fallback_words), "type": "fallback", "priority": 4});
    }
    seen: set = set();
    unique = [];
    for q in queries {
        norm = q["query"].lower().strip();
        if norm and norm not in seen { seen.add(norm); unique.append(q); }
    }
    return unique or [{"query": text[:80], "type": "raw", "priority": 5}];
}

def _score_relevance_weighted(article: dict, keywords: list, entities: list,
                              reference_date: str | None = None) -> float {
    title = (article.get("title") or "").lower();
    desc = (article.get("description") or "").lower();
    text = title + " " + desc;
    if keywords {
        kw_matches = sum(1 for kw in keywords if kw.lower() in text);
        kw_score = min(1.0, kw_matches / max(len(keywords), 1));
    } else { kw_score = 0.3; }
    if entities {
        entity_matches = sum(1 for e in entities if e.lower() in text);
        entity_score = min(1.0, entity_matches / max(len(entities), 1));
    } else { entity_score = 0.3; }
    source_name = ((article.get("source") or {}).get("name") or "").lower();
    source_score = 1.0 if source_name in _RELIABLE_SOURCES else 0.6;
    recency_score = 0.5;
    pub_at = article.get("publishedAt") or "";
    if reference_date and pub_at {
        try {
            ref_dt = datetime.datetime.fromisoformat(reference_date.replace("Z", "+00:00"));
            pub_dt = datetime.datetime.fromisoformat(pub_at.replace("Z", "+00:00"));
            days_diff = abs((ref_dt - pub_dt).total_seconds()) / 86400;
            if days_diff <= 7 { recency_score = 1.0; }
            elif days_diff <= 14 { recency_score = 0.8; }
            elif days_diff <= 30 { recency_score = 0.6; }
            elif days_diff <= 90 { recency_score = 0.4; }
            else { recency_score = 0.2; }
        } except (ValueError, TypeError) { recency_score = 0.5; }
    }
    score = (kw_score * 0.35 + entity_score * 0.35 + source_score * 0.15 + recency_score * 0.15);
    return round(min(1.0, score), 3);
}

def _dynamic_threshold(articles: list, target_count: int = 10) -> float {
    if not articles { return 0.15; }
    scores = sorted([a.get("relevance_score", 0) for a in articles], reverse=True);
    if len(scores) <= target_count {
        return max(0.15, scores[-1] - 0.05) if scores else 0.15;
    }
    return max(0.15, scores[target_count - 1] - 0.01);
}

def _dedup_articles(articles: list) -> list {
    seen: set = set();
    unique = [];
    for a in articles {
        title = (a.get("title") or "").strip().lower();
        key = hashlib.md5(title[:60].encode()).hexdigest();
        if key not in seen and title and title != "[removed]" {
            seen.add(key);
            unique.append(a);
        }
    }
    return unique;
}

def _normalize_articles(raw_articles: list, keywords: list,
                        entities: list | None = None,
                        reference_date: str | None = None) -> list {
    deduped = _dedup_articles(raw_articles);
    normalized = [];
    for a in deduped {
        relevance = _score_relevance_weighted(a, keywords, entities or [],
                                              reference_date=reference_date);
        normalized.append({
            "title": a.get("title", ""),
            "source": (a.get("source") or {}).get("name", "unknown"),
            "published_at": a.get("publishedAt"),
            "url": a.get("url", ""),
            "description": (a.get("description") or "")[:300],
            "relevance_score": relevance
        });
    }
    normalized.sort(key=lambda x: (-x["relevance_score"], x["published_at"] or ""));
    return normalized;
}

def _multi_query_search(text: str, start_date: str | None = None,
                        end_date: str | None = None,
                        sort_by: str = "relevancy",
                        page_size: int = 100,
                        reference_date: str | None = None) -> dict {
    queries = _generate_queries(text);
    components = _extract_query_components(text);
    all_raw: list = [];
    queries_used: list = [];
    errors: list = [];
    for q in queries {
        try {
            batch = _gnews_rss_search(q["query"], start_date, end_date);
            all_raw.extend(batch);
            queries_used.append(f"gnews_{q['type']}: '{q['query']}' -> {len(batch)} results");
        } except Exception as e {
            errors.append(f"gnews_{q['type']}: {str(e)[:80]}");
        }
        if _WEBZ_KEY {
            try {
                batch = _webzio_search(q["query"], start_date, end_date);
                all_raw.extend(batch);
                queries_used.append(f"webzio_{q['type']}: '{q['query']}' -> {len(batch)} results");
            } except Exception as e {
                errors.append(f"webzio_{q['type']}: {str(e)[:80]}");
            }
        }
    }
    normalized = _normalize_articles(all_raw, components["keywords"], components["entities"],
                                     reference_date=reference_date);
    threshold = _dynamic_threshold(normalized);
    relevant = [a for a in normalized if a["relevance_score"] >= threshold];
    return {
        "normalized": normalized, "relevant": relevant,
        "queries_used": queries_used, "errors": errors,
        "components": components, "threshold": threshold,
        "total_raw": len(all_raw)
    };
}

def search_news(query: str, start_date: str | None = None,
                end_date: str | None = None,
                reference_date: str | None = None) -> dict {
    result = _multi_query_search(query, start_date, end_date, reference_date=reference_date);
    relevant = result["relevant"];
    earliest = None;
    if relevant {
        timestamps = [a["published_at"] for a in relevant if a["published_at"]];
        if timestamps { earliest = min(timestamps); }
    }
    data = {
        "query": query, "queries_generated": result["queries_used"],
        "total_raw_results": result["total_raw"],
        "articles_after_dedup": len(result["normalized"]),
        "relevance_threshold": result["threshold"],
        "relevant_article_count": len(relevant),
        "articles": relevant[:20],
        "earliest_relevant_news_timestamp": earliest,
        "news_available": len(relevant) > 0,
        "news_coverage_density": round(len(relevant) / max(len(result["normalized"]), 1), 3) if result["normalized"] else 0
    };
    summary = (
        f"News search for '{query}': {len(relevant)} relevant articles "
        f"(threshold={result['threshold']:.2f}, {result['total_raw']} raw, "
        f"{len(result['normalized'])} deduped). "
        f"Queries: {len(result['queries_used'])}. Earliest: {earliest or 'N/A'}."
    );
    if result["errors"] { summary += f" Errors: {'; '.join(result['errors'][:2])}."; }
    return {"data": data, "summary": summary};
}

def get_event_news_timeline(event_description: str) -> dict {
    result = _multi_query_search(event_description, page_size=100);
    relevant = result["relevant"];
    timeline = [];
    for a in relevant {
        if a["published_at"] {
            timeline.append({
                "timestamp": a["published_at"], "source": a["source"],
                "headline": a["title"][:150], "relevance_score": a["relevance_score"],
                "url": a.get("url", "")
            });
        }
    }
    timeline.sort(key=lambda x: x["timestamp"]);
    earliest = timeline[0]["timestamp"] if timeline else None;
    data = {
        "event": event_description, "timeline": timeline[:30],
        "queries_generated": result["queries_used"],
        "total_articles_found": result["total_raw"],
        "relevant_articles": len(relevant),
        "earliest_relevant_news_timestamp": earliest,
        "news_available": len(relevant) > 0,
        "news_coverage_density": round(len(relevant) / max(len(result["normalized"]), 1), 3) if result["normalized"] else 0
    };
    summary = (
        f"News timeline for '{event_description[:40]}': {len(timeline)} events. "
        f"Earliest: {earliest or 'none'}. "
        f"{len(relevant)} relevant from {result['total_raw']} raw. "
        f"Queries: {len(result['queries_used'])}."
    );
    return {"data": data, "summary": summary};
}

def check_pre_news_trades(wallet_address: str, market_id: str,
                          news_timestamp: str) -> dict {
    news_epoch = _parse_ts(news_timestamp);
    if news_epoch is None {
        return {"data": {"wallet": wallet_address, "finding": "INCONCLUSIVE",
                         "note": "Could not parse news timestamp."},
                "summary": f"Pre-news check for {wallet_address[:12]}...: INCONCLUSIVE — bad timestamp."};
    }
    all_result = get_market_trades(market_id);
    trades = all_result["data"];
    wallet_trades = [t for t in trades if t.get("wallet", "").lower() == wallet_address.lower()];
    if not wallet_trades {
        return {"data": {"wallet": wallet_address, "market_id": market_id,
                         "finding": "NO_TRADES", "pre_news_trade_count": 0},
                "summary": f"Pre-news check for {wallet_address[:12]}...: No trades found."};
    }
    pre_news = [t for t in wallet_trades if t.get("timestamp", 0) < news_epoch];
    post_news = [t for t in wallet_trades if t.get("timestamp", 0) >= news_epoch];
    if pre_news {
        earliest_ts = min(t.get("timestamp", 0) for t in pre_news);
        delta = earliest_ts - news_epoch;
        pre_vol = sum(t.get("size_usdc", 0) for t in pre_news);
        finding = "PRE_NEWS_TRADING_DETECTED";
    } else { delta = 0; pre_vol = 0; finding = "NO_PRE_NEWS_TRADING"; }
    data = {
        "wallet": wallet_address, "market_id": market_id,
        "news_timestamp": news_timestamp, "finding": finding,
        "pre_news_trade_count": len(pre_news),
        "post_news_trade_count": len(post_news),
        "pre_news_volume_usdc": round(pre_vol, 2),
        "first_trade_minus_first_news_seconds": round(delta)
    };
    summary = (
        f"Pre-news check for {wallet_address[:12]}...: {finding}. "
        f"{len(pre_news)} before, {len(post_news)} after news. "
        f"Delta: {abs(delta)/3600:.1f}h {'before' if delta < 0 else 'after'}."
    );
    return {"data": data, "summary": summary};
}

def correlate_market_trades_with_news(market_id: str) -> dict {
    info_result = get_market_info(market_id);
    market_title = "";
    if isinstance(info_result, dict) {
        info_data = info_result.get("data", {});
        market_title = info_data.get("title", "") or info_data.get("question", "");
    }
    if not market_title { market_title = f"polymarket market {market_id}"; }
    news_result = search_news(market_title);
    news_data = news_result.get("data", {});
    articles = news_data.get("articles", []);
    trades_result = get_market_trades(market_id);
    trades = trades_result.get("data", []);
    events = [];
    if articles {
        earliest_news = news_data.get("earliest_relevant_news_timestamp");
        if earliest_news and trades {
            news_epoch = _parse_ts(earliest_news);
            if news_epoch {
                before = [t for t in trades if t.get("timestamp", 0) < news_epoch];
                after = [t for t in trades if t.get("timestamp", 0) >= news_epoch];
                vol_before = sum(t.get("size_usdc", 0) for t in before);
                vol_after = sum(t.get("size_usdc", 0) for t in after);
                total_vol = vol_before + vol_after;
                events.append({
                    "type": "news_trade_correlation",
                    "earliest_news": earliest_news,
                    "trades_before_news": len(before), "trades_after_news": len(after),
                    "volume_before_news": round(vol_before, 2),
                    "volume_after_news": round(vol_after, 2),
                    "pct_volume_before_news": round(vol_before / max(total_vol, 1) * 100, 1),
                    "pct_trades_before_news": round(len(before) / max(len(before) + len(after), 1) * 100, 1)
                });
            }
        }
    }
    data = {
        "market_id": market_id, "market_title": market_title,
        "events": events, "relevant_article_count": len(articles),
        "news_available": len(articles) > 0
    };
    summary = (
        f"Trade-news correlation for {market_id}: "
        f"{len(articles)} articles, {len(events)} correlations."
    );
    if events {
        e = events[0];
        summary += (f" {e['pct_volume_before_news']:.0f}% volume before news, "
                    f"{e['pct_trades_before_news']:.0f}% trades before news.");
    }
    return {"data": data, "summary": summary};
}

def get_news_sentiment_around_event(event_description: str,
                                    window_days: int = 7) -> dict {
    timeline_result = get_event_news_timeline(event_description);
    timeline_data = timeline_result.get("data", {});
    data = {
        "event": event_description,
        "total_articles": timeline_data.get("relevant_articles", 0),
        "news_available": timeline_data.get("news_available", False),
        "news_coverage_density": timeline_data.get("news_coverage_density", 0),
        "earliest_relevant_news_timestamp": timeline_data.get("earliest_relevant_news_timestamp"),
        "sentiments": [],
        "note": "Coverage density provided. Full sentiment requires NLP integration."
    };
    summary = (
        f"News coverage for '{event_description[:40]}': "
        f"{timeline_data.get('relevant_articles', 0)} articles. "
        f"Density: {timeline_data.get('news_coverage_density', 0):.1%}."
    );
    return {"data": data, "summary": summary};
}

def analyze_pre_news_trading(market_id: str, event_timestamp: str,
                             top_n: int = 10,
                             news_window_days: int = 90) -> dict {
    """Combined news+timing analysis: primary insider-trading evidence signal.""";
    event_epoch = _parse_ts(event_timestamp);
    info_result = get_market_info(market_id);
    market_title = "";
    if isinstance(info_result, dict) {
        info_data = info_result.get("data", {});
        market_title = info_data.get("title", "") or info_data.get("question", "");
    }
    if not market_title { market_title = f"market {market_id}"; }
    news_timestamp = None;
    news_article_count = 0;
    news_available = False;
    queries_used = [];
    news_window_info = {};
    articles_kept = 0;
    articles_filtered_out = 0;
    proxy_news_used = False;
    if event_epoch is not None {
        try { event_dt = datetime.datetime.fromtimestamp(event_epoch, tz=datetime.timezone.utc); }
        except (ValueError, TypeError, OSError) { event_dt = datetime.datetime.now(datetime.timezone.utc); }
        window_start = event_dt - datetime.timedelta(days=news_window_days);
        window_end = event_dt + datetime.timedelta(days=7);
        start_date = window_start.strftime("%Y-%m-%d");
        end_date = window_end.strftime("%Y-%m-%d");
        news_window_info = {"window_start": start_date, "window_end": end_date,
                            "window_days": news_window_days};
        news_result = search_news(market_title, start_date=start_date,
                                  end_date=end_date, reference_date=event_timestamp);
        news_data = news_result.get("data", {});
        raw_articles = news_data.get("articles", []);
        event_cutoff = event_dt + datetime.timedelta(hours=24);
        valid_articles = [];
        for a in raw_articles {
            pub = a.get("published_at") or "";
            if pub {
                try {
                    pub_dt = datetime.datetime.fromisoformat(pub.replace("Z", "+00:00"));
                    if pub_dt <= event_cutoff { valid_articles.append(a); }
                    else { articles_filtered_out += 1; }
                } except (ValueError, TypeError) { valid_articles.append(a); }
            } else { valid_articles.append(a); }
        }
        articles_kept = len(valid_articles);
        if valid_articles {
            timestamps = [a["published_at"] for a in valid_articles if a.get("published_at")];
            if timestamps { news_timestamp = min(timestamps); }
            news_article_count = len(valid_articles);
            news_available = True;
        }
        queries_used = news_data.get("queries_generated", []);
    }
    timing_result = score_top_suspicious_wallets(
        market_id, event_timestamp, top_n=top_n, news_timestamp=news_timestamp);
    timing_data = timing_result.get("data", {});
    wallet_scores = timing_data.get("wallet_scores", []);
    if news_timestamp {
        pre_news_wallets = [w for w in wallet_scores if w.get("traded_before_news")];
        post_news_wallets = [w for w in wallet_scores if not w.get("traded_before_news", True)];
    } else { pre_news_wallets = []; post_news_wallets = []; }
    total_volume = sum(w.get("pre_event_volume_usdc", 0) for w in wallet_scores);
    pre_news_volume = sum(w.get("pre_event_volume_usdc", 0) for w in pre_news_wallets);
    pct_wallets_before_news = round(len(pre_news_wallets) / max(len(wallet_scores), 1) * 100, 1) if news_timestamp else 0.0;
    pct_volume_before_news = round(pre_news_volume / max(total_volume, 1) * 100, 1) if news_timestamp else 0.0;
    high_conf_pre_news = [w for w in pre_news_wallets if w.get("timing_score", 0) >= 60];
    avg_timing = timing_data.get("avg_timing_score", 0);
    if not news_available { pre_news_signal = "NO_NEWS_DATA"; }
    elif not news_timestamp { pre_news_signal = "NO_NEWS_DATA"; }
    elif len(pre_news_wallets) == 0 { pre_news_signal = "NONE"; }
    elif len(high_conf_pre_news) == 0 and pct_volume_before_news < 10 { pre_news_signal = "WEAK"; }
    elif len(high_conf_pre_news) >= 3 or pct_volume_before_news >= 30 { pre_news_signal = "STRONG"; }
    elif len(high_conf_pre_news) >= 1 or pct_volume_before_news >= 10 { pre_news_signal = "MODERATE"; }
    else { pre_news_signal = "WEAK"; }
    if news_available and news_timestamp {
        if pre_news_signal in ("MODERATE", "STRONG") {
            trading_classification = "POSSIBLE INSIDER TRADING — pre-news positioning detected";
        } elif avg_timing >= 70 and len(pre_news_wallets) == 0 {
            trading_classification = "POST-NEWS CLUSTERING — high timing scores but all trades after news";
        } elif pre_news_signal == "WEAK" {
            trading_classification = "WEAK PRE-NEWS SIGNAL — insufficient for insider trading conclusion";
        } elif pre_news_signal == "NONE" and avg_timing < 30 {
            trading_classification = "NORMAL MARKET BEHAVIOR — no anomalous patterns";
        } elif pre_news_signal == "NONE" {
            trading_classification = "NO PRE-NEWS TRADING — reactive or publicly-informed behavior";
        } else { trading_classification = "INCONCLUSIVE — mixed signals"; }
    } else { trading_classification = "INSUFFICIENT PUBLIC NEWS — PROXY ANALYSIS USED"; }
    wallet_classifications = [];
    for w in wallet_scores {
        wc = {"wallet": w["wallet"][:16] + "...", "timing_score": w.get("timing_score", 0),
              "volume_usdc": w.get("pre_event_volume_usdc", 0)};
        if news_timestamp and w.get("traded_before_news") {
            if w.get("timing_score", 0) >= 60 { wc["classification"] = "PRE_NEWS_HIGH_CONFIDENCE"; }
            else { wc["classification"] = "PRE_NEWS_MODERATE"; }
        } elif news_timestamp and not w.get("traded_before_news", True) {
            wc["classification"] = "POST_NEWS_ONLY";
        } else {
            ts = w.get("timing_score", 0);
            if ts >= 70 { wc["classification"] = "HIGH_TIMING_NO_NEWS"; }
            elif ts >= 40 { wc["classification"] = "MODERATE_TIMING_NO_NEWS"; }
            else { wc["classification"] = "LOW_TIMING"; }
        }
        wallet_classifications.append(wc);
    }
    proxy_drift = None;
    proxy_suspicion = None;
    if event_epoch is not None {
        try {
            runup = compute_price_run_up(market_id, event_timestamp);
            runup_data = runup.get("data", {});
            proxy_drift = runup_data.get("total_pre_event_drift", 0);
            proxy_suspicion = runup_data.get("suspicion_level", "UNKNOWN");
        } except Exception { proxy_drift = 0; proxy_suspicion = "UNKNOWN"; }
    }
    if not news_available { proxy_news_used = True; }
    if not news_available and proxy_suspicion {
        if proxy_suspicion == "HIGH" and avg_timing >= 60 {
            trading_classification = "INSUFFICIENT PUBLIC NEWS — PROXY SIGNALS SUSPICIOUS (high price drift + timing)";
        } elif proxy_suspicion == "MEDIUM" or avg_timing >= 50 {
            trading_classification = "INSUFFICIENT PUBLIC NEWS — PROXY SIGNALS MODERATE";
        } else {
            trading_classification = "INSUFFICIENT PUBLIC NEWS — PROXY SIGNALS LOW";
        }
    }
    data = {
        "market_id": market_id, "event_timestamp": event_timestamp,
        "market_title": market_title,
        "news_available": news_available, "earliest_news_timestamp": news_timestamp,
        "relevant_article_count": news_article_count, "queries_generated": queries_used,
        "news_window": news_window_info,
        "articles_kept": articles_kept, "articles_filtered_out": articles_filtered_out,
        "proxy_news_used": proxy_news_used,
        "wallets_scored": len(wallet_scores), "avg_timing_score": avg_timing,
        "pre_news_wallet_count": len(pre_news_wallets),
        "post_news_wallet_count": len(post_news_wallets),
        "pct_wallets_before_news": pct_wallets_before_news,
        "pct_volume_before_news": pct_volume_before_news,
        "pre_news_volume_usdc": round(pre_news_volume, 2),
        "high_confidence_pre_news_wallets": len(high_conf_pre_news),
        "trading_classification": trading_classification,
        "pre_news_signal": pre_news_signal,
        "suspicion_level": timing_data.get("suspicion_level", "UNKNOWN"),
        "wallet_classifications": wallet_classifications[:10],
        "pre_news_high_confidence_wallets": [
            {"wallet": w["wallet"][:16] + "...", "timing_score": w["timing_score"],
             "volume_usdc": w["pre_event_volume_usdc"],
             "hours_before_news": round(abs(w.get("first_trade_vs_news_delta", 0)) / 3600, 1)}
            for w in high_conf_pre_news[:5]
        ] if news_timestamp else [],
        "proxy_price_drift": proxy_drift, "proxy_suspicion": proxy_suspicion
    };
    summary_parts = [
        f"Pre-news trading analysis for {market_id}: ",
        f"{len(wallet_scores)} wallets scored, avg timing {avg_timing:.0f}/100."
    ];
    if news_window_info {
        summary_parts.append(
            f" NEWS WINDOW: {news_window_info.get('window_start')} to {news_window_info.get('window_end')}.");
    }
    if articles_filtered_out > 0 {
        summary_parts.append(f" NEWS FILTER: kept {articles_kept}, removed {articles_filtered_out} post-event articles.");
    }
    if news_timestamp {
        summary_parts.append(f" News found: {news_article_count} articles, earliest {news_timestamp}.");
        summary_parts.append(f" {pct_wallets_before_news:.0f}% wallets, {pct_volume_before_news:.0f}% volume before news.");
        if high_conf_pre_news { summary_parts.append(f" {len(high_conf_pre_news)} high-confidence pre-news wallet(s)."); }
    } elif not news_available {
        summary_parts.append(" No valid news in event window — proxy signals used.");
        if proxy_drift is not None { summary_parts.append(f" Proxy price drift: {proxy_drift:+.1%}, suspicion: {proxy_suspicion}."); }
    } else { summary_parts.append(" No news timeline available — cannot assess pre-news trading."); }
    summary_parts.append(f" Classification: {trading_classification}.");
    summary_parts.append(f" Signal: {pre_news_signal}.");
    return {"data": data, "summary": "".join(summary_parts)};
}

# ═══════════════════════════════════════════════════════════════════
# 5. WALLET PROFILING TOOLS — V11: Derive from trade data
# ═══════════════════════════════════════════════════════════════════

def get_wallet_profile(wallet_address: str, market_id: str = "") -> dict {
    """Build wallet profile from market trade data. V11: actually derives stats.""";
    if not market_id {
        return {"data": {"wallet": wallet_address, "note": "No market_id — use trade-level tools."},
                "summary": f"Wallet {wallet_address[:12]}...: Provide market_id for profile."};
    }
    all_result = get_market_trades(market_id);
    trades = all_result["data"];
    wallet_trades = [t for t in trades if t.get("wallet", "").lower() == wallet_address.lower()];
    if not wallet_trades {
        return {"data": {"wallet": wallet_address, "market_id": market_id,
                         "total_trades": 0, "total_volume_usdc": 0,
                         "suspicion_level": "LOW"},
                "summary": f"Wallet {wallet_address[:12]}...: No trades on {market_id}."};
    }
    total_vol = sum(t["size_usdc"] for t in wallet_trades);
    yes_trades = sum(1 for t in wallet_trades if "YES" in t.get("direction", ""));
    no_trades = len(wallet_trades) - yes_trades;
    buy_trades = sum(1 for t in wallet_trades if "BUY" in t.get("direction", ""));
    timestamps = sorted(t.get("timestamp", 0) for t in wallet_trades);
    first_trade = timestamps[0];
    last_trade = timestamps[-1];
    span_hours = (last_trade - first_trade) / 3600 if len(timestamps) > 1 else 0;
    avg_size = total_vol / len(wallet_trades);
    direction_bias = "YES" if yes_trades > no_trades else ("NO" if no_trades > yes_trades else "NEUTRAL");
    data = {
        "wallet": wallet_address, "market_id": market_id,
        "total_trades": len(wallet_trades),
        "total_volume_usdc": round(total_vol, 2),
        "avg_trade_size_usdc": round(avg_size, 2),
        "yes_trade_count": yes_trades, "no_trade_count": no_trades,
        "buy_count": buy_trades, "sell_count": len(wallet_trades) - buy_trades,
        "direction_bias": direction_bias,
        "yes_pct": round(yes_trades / max(len(wallet_trades), 1) * 100, 1),
        "first_trade_ts": first_trade, "last_trade_ts": last_trade,
        "trading_span_hours": round(span_hours, 2),
        "flags": []
    };
    if avg_size > 500 { data["flags"].append("large_avg_size"); }
    if span_hours < 1 and len(wallet_trades) > 3 { data["flags"].append("rapid_clustering"); }
    if yes_trades / max(len(wallet_trades), 1) > 0.9 { data["flags"].append("extreme_yes_bias"); }
    summary = (
        f"Wallet {wallet_address[:12]}...: {len(wallet_trades)} trades, "
        f"${total_vol:,.0f} volume, {direction_bias} bias ({yes_trades}/{len(wallet_trades)} YES). "
        f"Avg size: ${avg_size:,.0f}. Span: {span_hours:.1f}h. Flags: {data['flags'] or 'none'}."
    );
    return {"data": data, "summary": summary};
}

def get_wallet_trade_history(wallet_address: str, market_id: str = "",
                             limit: int = 50) -> dict {
    """Filter market trades by wallet address. V11: returns actual data.""";
    if not market_id {
        return {"data": {"wallet": wallet_address, "trades": [],
                         "note": "Cross-market history requires market_id."},
                "summary": f"Trade history for {wallet_address[:12]}...: Provide market_id."};
    }
    all_result = get_market_trades(market_id);
    trades = all_result["data"];
    wallet_trades = [t for t in trades if t.get("wallet", "").lower() == wallet_address.lower()][:limit];
    data = {
        "wallet": wallet_address, "market_id": market_id,
        "trade_count": len(wallet_trades), "trades": wallet_trades
    };
    total_vol = sum(t["size_usdc"] for t in wallet_trades);
    summary = (
        f"Trade history for {wallet_address[:12]}...: {len(wallet_trades)} trades on {market_id}. "
        f"Total volume: ${total_vol:,.0f} USDC."
    );
    return {"data": data, "summary": summary};
}

def get_wallet_pnl(wallet_address: str, market_id: str = "") -> dict {
    """Estimate PnL from trade data. V11: derives from buy/sell prices.""";
    if not market_id {
        return {"data": {"wallet": wallet_address, "note": "PnL requires market_id."},
                "summary": f"PnL for {wallet_address[:12]}...: Provide market_id."};
    }
    all_result = get_market_trades(market_id);
    trades = all_result["data"];
    wallet_trades = [t for t in trades if t.get("wallet", "").lower() == wallet_address.lower()];
    if not wallet_trades {
        return {"data": {"wallet": wallet_address, "market_id": market_id,
                         "total_pnl": 0, "total_volume_usdc": 0},
                "summary": f"PnL for {wallet_address[:12]}...: No trades on {market_id}."};
    }
    buy_vol = sum(t["size_usdc"] for t in wallet_trades if "BUY" in t.get("direction", ""));
    sell_vol = sum(t["size_usdc"] for t in wallet_trades if "SELL" in t.get("direction", ""));
    net_pnl_estimate = sell_vol - buy_vol;
    total_vol = buy_vol + sell_vol;
    data = {
        "wallet": wallet_address, "market_id": market_id,
        "buy_volume_usdc": round(buy_vol, 2),
        "sell_volume_usdc": round(sell_vol, 2),
        "net_pnl_estimate_usdc": round(net_pnl_estimate, 2),
        "total_volume_usdc": round(total_vol, 2),
        "trade_count": len(wallet_trades),
        "note": "PnL estimate from buy/sell volume delta. Does not include resolution payouts."
    };
    summary = (
        f"PnL estimate for {wallet_address[:12]}...: "
        f"Buy ${buy_vol:,.0f}, Sell ${sell_vol:,.0f}, Net: ${net_pnl_estimate:,.0f} USDC. "
        f"Note: excludes resolution payouts."
    );
    return {"data": data, "summary": summary};
}

def get_wallet_win_rate_by_market_type(wallet_address: str) -> dict {
    """Win rate by market type — limited without cross-market data.""";
    data = {
        "wallet": wallet_address,
        "note": "Win rate by market category requires resolved trade history across markets. "
                "Use compare_trader_to_peers for per-market analysis."
    };
    summary = (
        f"Win rate by category for {wallet_address[:12]}...: "
        f"Requires cross-market resolved data. Use compare_trader_to_peers instead."
    );
    return {"data": data, "summary": summary};
}

def get_wallet_first_activity(wallet_address: str, market_id: str = "") -> dict {
    """Find earliest trade for wallet. V11: derives from trade data.""";
    if not market_id {
        return {"data": {"wallet": wallet_address,
                         "note": "First activity requires market_id."},
                "summary": f"First activity for {wallet_address[:12]}...: Provide market_id."};
    }
    all_result = get_market_trades(market_id);
    trades = all_result["data"];
    wallet_trades = [t for t in trades if t.get("wallet", "").lower() == wallet_address.lower()];
    if not wallet_trades {
        return {"data": {"wallet": wallet_address, "market_id": market_id,
                         "first_activity": None},
                "summary": f"First activity for {wallet_address[:12]}...: No trades on {market_id}."};
    }
    earliest = min(wallet_trades, key=lambda t: t.get("timestamp", 0));
    data = {
        "wallet": wallet_address, "market_id": market_id,
        "first_trade_timestamp": earliest.get("timestamp", 0),
        "first_trade_direction": earliest.get("direction", ""),
        "first_trade_size_usdc": earliest.get("size_usdc", 0),
        "total_trades_on_market": len(wallet_trades)
    };
    summary = (
        f"First activity for {wallet_address[:12]}...: "
        f"Trade at ts={earliest.get('timestamp', 0)}, "
        f"{earliest.get('direction', '')} ${earliest.get('size_usdc', 0):,.0f}. "
        f"Total: {len(wallet_trades)} trades on {market_id}."
    );
    return {"data": data, "summary": summary};
}

# ═══════════════════════════════════════════════════════════════════
# 6. NETWORK / FUND FLOW TOOLS — V11: Co-occurrence analysis
# ═══════════════════════════════════════════════════════════════════

def find_linked_wallets(wallet_address: str, market_id: str = "") -> dict {
    """Find wallets with co-occurrence patterns. V11: derives from trade data.""";
    if not market_id {
        return {"data": {"wallet": wallet_address, "linked_wallets": [],
                         "note": "Linked wallet detection requires market_id."},
                "summary": f"Linked wallets for {wallet_address[:12]}...: Provide market_id."};
    }
    all_result = get_market_trades(market_id);
    trades = all_result["data"];
    wallet_trades = [t for t in trades if t.get("wallet", "").lower() == wallet_address.lower()];
    if not wallet_trades {
        return {"data": {"wallet": wallet_address, "linked_wallets": []},
                "summary": f"Linked wallets for {wallet_address[:12]}...: No trades on {market_id}."};
    }
    bucket_size = 3600;
    wallet_buckets: set = set();
    for t in wallet_trades {
        wallet_buckets.add(int(t.get("timestamp", 0) // bucket_size));
    }
    co_wallets: dict = {};
    for t in trades {
        w = t.get("wallet", "");
        if w.lower() == wallet_address.lower() { continue; }
        bucket = int(t.get("timestamp", 0) // bucket_size);
        if bucket in wallet_buckets {
            if w not in co_wallets { co_wallets[w] = {"wallet": w, "co_occurrences": 0, "shared_volume": 0.0}; }
            co_wallets[w]["co_occurrences"] += 1;
            co_wallets[w]["shared_volume"] += t.get("size_usdc", 0);
        }
    }
    linked = sorted(co_wallets.values(), key=lambda x: x["co_occurrences"], reverse=True)[:10];
    for lw in linked { lw["shared_volume"] = round(lw["shared_volume"], 2); }
    data = {
        "wallet": wallet_address, "market_id": market_id,
        "linked_wallets": linked, "co_trading_wallets_found": len(linked)
    };
    summary = (
        f"Linked wallets for {wallet_address[:12]}...: "
        f"{len(linked)} co-trading wallets found on {market_id}."
    );
    if linked {
        summary += f" Top: {linked[0]['wallet'][:12]}... ({linked[0]['co_occurrences']} co-occurrences).";
    }
    return {"data": data, "summary": summary};
}

def build_trader_network(market_id: str) -> dict {
    """Build co-occurrence network from real trade data.""";
    all_result = get_market_trades(market_id);
    trades = all_result["data"];
    bucket_size = 3600;
    buckets: dict = {};
    for t in trades {
        ts = t.get("timestamp", 0);
        bucket = int(ts // bucket_size);
        buckets.setdefault(bucket, []).append(t.get("wallet", ""));
    }
    wallets = list({t.get("wallet", "") for t in trades});
    edges = [];
    edge_set: set = set();
    for bucket_wallets in buckets.values() {
        unique_in_bucket = list(set(bucket_wallets));
        for i in range(len(unique_in_bucket)) {
            for j in range(i + 1, len(unique_in_bucket)) {
                (w1, w2) = (unique_in_bucket[i], unique_in_bucket[j]) if unique_in_bucket[i] < unique_in_bucket[j] else (unique_in_bucket[j], unique_in_bucket[i]);
                key = (w1, w2);
                if key not in edge_set {
                    edge_set.add(key);
                    edges.append({"source": w1, "target": w2,
                                  "co_occurrence_count": 1, "shared_direction": True});
                } else {
                    for e in edges {
                        if e["source"] == w1 and e["target"] == w2 {
                            e["co_occurrence_count"] += 1;
                            break;
                        }
                    }
                }
            }
        }
    }
    connection_count: dict = {};
    for e in edges {
        connection_count[e["source"]] = connection_count.get(e["source"], 0) + 1;
        connection_count[e["target"]] = connection_count.get(e["target"], 0) + 1;
    }
    dense_wallets = sorted(connection_count, key=lambda w: connection_count[w], reverse=True)[:5];
    data = {
        "market_id": market_id, "node_count": len(wallets), "edge_count": len(edges),
        "nodes": wallets[:50], "edges": edges[:100],
        "dense_cluster": {
            "wallet_count": len(dense_wallets), "wallets": dense_wallets,
            "max_connections": connection_count.get(dense_wallets[0], 0) if dense_wallets else 0
        }
    };
    summary = (
        f"Trader network for {market_id}: {len(wallets)} nodes, {len(edges)} edges. "
        f"Dense cluster: {len(dense_wallets)} wallets with highest co-occurrence."
    );
    return {"data": data, "summary": summary};
}

def trace_fund_flows(wallet_address: str, depth: int = 2) -> dict {
    """Fund flow tracing — limited without on-chain data.""";
    data = {
        "wallet": wallet_address, "depth": depth,
        "funding_sources": [], "fund_destinations": [],
        "suspicious_flow_count": 0,
        "note": "Fund flow tracing requires on-chain transaction data. "
                "Use build_trader_network for co-occurrence analysis."
    };
    summary = (
        f"Fund flow trace for {wallet_address[:12]}...: "
        f"Requires on-chain data. Use build_trader_network instead."
    );
    return {"data": data, "summary": summary};
}

# ═══════════════════════════════════════════════════════════════════
# 7. TOOL REGISTRY
# ═══════════════════════════════════════════════════════════════════

glob TOOL_REGISTRY: dict = {
    "get_market_info": {
        "fn": get_market_info,
        "description": "Fetches metadata for a market: resolution criteria, outcomes, category, creation date, current prices.",
        "params": [{"name": "market_id", "type": "str", "required": True}]
    },
    "get_market_price_history": {
        "fn": get_market_price_history,
        "description": "Returns the full price time series for a market within a window.",
        "params": [
            {"name": "market_id", "type": "str", "required": True},
            {"name": "start_time", "type": "str|None", "required": False},
            {"name": "end_time", "type": "str|None", "required": False}
        ]
    },
    "get_market_trades": {
        "fn": get_market_trades,
        "description": "All trades on a market in a time window with wallet, size, direction, timestamp.",
        "params": [
            {"name": "market_id", "type": "str", "required": True},
            {"name": "start_time", "type": "str|None", "required": False},
            {"name": "end_time", "type": "str|None", "required": False}
        ]
    },
    "get_large_trades": {
        "fn": get_large_trades,
        "description": "Filters trades above a given size threshold — surfaces whale activity.",
        "params": [
            {"name": "market_id", "type": "str", "required": True},
            {"name": "size_threshold", "type": "float", "required": True}
        ]
    },
    "get_pre_event_trades": {
        "fn": get_pre_event_trades,
        "description": "All trades placed within a configurable window before the event resolved.",
        "params": [
            {"name": "market_id", "type": "str", "required": True},
            {"name": "event_timestamp", "type": "str", "required": True},
            {"name": "lookback_hours", "type": "float", "required": False}
        ]
    },
    "get_market_movers": {
        "fn": get_market_movers,
        "description": "Wallets ranked by largest net position change within a time window.",
        "params": [
            {"name": "market_id", "type": "str", "required": True},
            {"name": "time_window", "type": "str", "required": False}
        ]
    },
    "compute_abnormal_volume": {
        "fn": compute_abnormal_volume,
        "description": "Compares pre-event trading volume to baseline to detect statistically unusual spikes.",
        "params": [
            {"name": "market_id", "type": "str", "required": True},
            {"name": "event_timestamp", "type": "str", "required": True}
        ]
    },
    "compute_price_run_up": {
        "fn": compute_price_run_up,
        "description": "Measures cumulative return drift before resolution — abnormal positive drift is a primary insider signal.",
        "params": [
            {"name": "market_id", "type": "str", "required": True},
            {"name": "event_timestamp", "type": "str", "required": True},
            {"name": "baseline_window", "type": "str|None", "required": False}
        ]
    },
    "score_trade_timing": {
        "fn": score_trade_timing,
        "description": "Scores how well-timed a wallet's trades were relative to the event.",
        "params": [
            {"name": "wallet_address", "type": "str", "required": True},
            {"name": "market_id", "type": "str", "required": True},
            {"name": "event_timestamp", "type": "str", "required": True}
        ]
    },
    "compare_trader_to_peers": {
        "fn": compare_trader_to_peers,
        "description": "Detects discontinuities in a trader's behavior vs peer traders.",
        "params": [
            {"name": "wallet_address", "type": "str", "required": True},
            {"name": "market_id", "type": "str", "required": True}
        ]
    },
    "find_synchronized_traders": {
        "fn": find_synchronized_traders,
        "description": "Identifies clusters of wallets that placed trades in the same direction within a tight time window.",
        "params": [
            {"name": "market_id", "type": "str", "required": True},
            {"name": "time_window", "type": "str", "required": False},
            {"name": "direction", "type": "str|None", "required": False}
        ]
    },
    "score_top_suspicious_wallets": {
        "fn": score_top_suspicious_wallets,
        "description": "Scores trade timing for the top N most active pre-event wallets.",
        "params": [
            {"name": "market_id", "type": "str", "required": True},
            {"name": "event_timestamp", "type": "str", "required": True},
            {"name": "top_n", "type": "int", "required": False},
            {"name": "news_timestamp", "type": "str", "required": False}
        ]
    },
    "search_news": {
        "fn": search_news,
        "description": "General news search returning articles with titles, sources, and publication timestamps.",
        "params": [
            {"name": "query", "type": "str", "required": True},
            {"name": "start_date", "type": "str|None", "required": False},
            {"name": "end_date", "type": "str|None", "required": False}
        ]
    },
    "get_event_news_timeline": {
        "fn": get_event_news_timeline,
        "description": "Constructs a chronological timeline of when news about a specific event first became public.",
        "params": [{"name": "event_description", "type": "str", "required": True}]
    },
    "check_pre_news_trades": {
        "fn": check_pre_news_trades,
        "description": "Determines whether a wallet placed significant trades before the earliest relevant news was published.",
        "params": [
            {"name": "wallet_address", "type": "str", "required": True},
            {"name": "market_id", "type": "str", "required": True},
            {"name": "news_timestamp", "type": "str", "required": True}
        ]
    },
    "correlate_market_trades_with_news": {
        "fn": correlate_market_trades_with_news,
        "description": "Overlays the full trade timeline against the news timeline.",
        "params": [{"name": "market_id", "type": "str", "required": True}]
    },
    "get_news_sentiment_around_event": {
        "fn": get_news_sentiment_around_event,
        "description": "Measures media sentiment leading up to and after the event.",
        "params": [
            {"name": "event_description", "type": "str", "required": True},
            {"name": "window_days", "type": "int", "required": False}
        ]
    },
    "analyze_pre_news_trading": {
        "fn": analyze_pre_news_trading,
        "description": "Combined news+timing analysis: searches news, scores top wallets by timing, classifies pre-news vs post-news trading.",
        "params": [
            {"name": "market_id", "type": "str", "required": True},
            {"name": "event_timestamp", "type": "str", "required": True},
            {"name": "top_n", "type": "int", "required": False}
        ]
    },
    "get_wallet_profile": {
        "fn": get_wallet_profile,
        "description": "Wallet stats derived from trade data: volume, direction bias, trade count, flags.",
        "params": [
            {"name": "wallet_address", "type": "str", "required": True},
            {"name": "market_id", "type": "str", "required": False}
        ]
    },
    "get_wallet_trade_history": {
        "fn": get_wallet_trade_history,
        "description": "Full trade history for a wallet on a specific market.",
        "params": [
            {"name": "wallet_address", "type": "str", "required": True},
            {"name": "market_id", "type": "str", "required": False},
            {"name": "limit", "type": "int", "required": False}
        ]
    },
    "get_wallet_pnl": {
        "fn": get_wallet_pnl,
        "description": "Profit and loss estimate from buy/sell volume delta.",
        "params": [
            {"name": "wallet_address", "type": "str", "required": True},
            {"name": "market_id", "type": "str", "required": False}
        ]
    },
    "get_wallet_win_rate_by_market_type": {
        "fn": get_wallet_win_rate_by_market_type,
        "description": "Win rate by market category — requires cross-market resolved data.",
        "params": [{"name": "wallet_address", "type": "str", "required": True}]
    },
    "get_wallet_first_activity": {
        "fn": get_wallet_first_activity,
        "description": "Returns the wallet's first trade on a market — new wallets that immediately profit are suspicious.",
        "params": [
            {"name": "wallet_address", "type": "str", "required": True},
            {"name": "market_id", "type": "str", "required": False}
        ]
    },
    "find_linked_wallets": {
        "fn": find_linked_wallets,
        "description": "Identifies wallets with co-trading patterns on the same market.",
        "params": [
            {"name": "wallet_address", "type": "str", "required": True},
            {"name": "market_id", "type": "str", "required": False}
        ]
    },
    "build_trader_network": {
        "fn": build_trader_network,
        "description": "Builds a graph of wallets that traded on the same market, edges weighted by temporal co-occurrence.",
        "params": [{"name": "market_id", "type": "str", "required": True}]
    },
    "trace_fund_flows": {
        "fn": trace_fund_flows,
        "description": "Follows USDC in/out of a wallet to find funding sources or money destinations.",
        "params": [
            {"name": "wallet_address", "type": "str", "required": True},
            {"name": "depth", "type": "int", "required": False}
        ]
    }
};

obj ToolRegistry {
    def list_tools() -> list {
        return [
            {"name": name, "description": spec["description"], "params": spec["params"]}
            for (name, spec) in TOOL_REGISTRY.items()
        ];
    }

    def call(tool_name: str, tool_args: dict) -> dict {
        if tool_name not in TOOL_REGISTRY {
            similar = self._find_similar(tool_name);
            hint = f" Did you mean: {similar}?" if similar else "";
            return {"error": f"Unknown tool '{tool_name}'.{hint} Valid tools: {', '.join(TOOL_REGISTRY.keys())}"};
        }
        spec = TOOL_REGISTRY[tool_name];
        fn = spec["fn"];
        required_params = [p["name"] for p in spec["params"] if p.get("required")];
        missing = [p for p in required_params if p not in tool_args];
        if missing {
            return {"error": f"Tool '{tool_name}' missing required params: {missing}."};
        }
        valid_param_names = {p["name"] for p in spec["params"]};
        filtered_args = {k: v for (k, v) in tool_args.items() if k in valid_param_names};
        try {
            result = fn(**filtered_args);
            return self._wrap_result(tool_name, result);
        } except TypeError as e {
            return {"error": f"Tool '{tool_name}' argument error: {e}"};
        } except Exception as e {
            return {"error": f"Tool '{tool_name}' execution error: {e}\n{traceback.format_exc()}"};
        }
    }

    def _wrap_result(tool_name: str, result: object) -> dict {
        if isinstance(result, dict) and "data" in result and "summary" in result {
            return result;
        }
        if isinstance(result, list) {
            return {"data": result, "summary": f"{tool_name} returned {len(result)} records."};
        } elif isinstance(result, dict) {
            return {"data": result, "summary": f"{tool_name} returned dict with keys: {list(result.keys())[:5]}"};
        }
        return {"data": result, "summary": f"{tool_name} returned: {str(result)[:200]}"};
    }

    def _find_similar(name: str) -> str | None {
        if not name { return None; }
        name_lower = name.lower();
        for valid_name in TOOL_REGISTRY {
            if name_lower in valid_name.lower() or valid_name.lower() in name_lower {
                return valid_name;
            }
        }
        return None;
    }
}
