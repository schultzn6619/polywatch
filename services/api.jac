"""PolyWatch — Polymarket API client.

Endpoints:
  - gamma-api.polymarket.com  — event/market metadata, prices, volume
  - data-api.polymarket.com   — trade history
  - clob.polymarket.com       — CLOB market details, order books
"""

import time;
import requests;
import json;

glob GAMMA: str = "https://gamma-api.polymarket.com";
glob DATA: str = "https://data-api.polymarket.com";
glob CLOB: str = "https://clob.polymarket.com";

glob _session: object = requests.Session();
glob _state: dict = {"last_request": 0.0};
glob _MIN_INTERVAL: float = 0.15;

# Initialize session headers
::py::
_session.headers["Accept"] = "application/json"
::py::

def _get(url: str, params: dict | None = None, timeout: int = 15) -> object {
    """GET with rate limiting and error handling. Returns parsed JSON.""";
    elapsed = time.monotonic() - _state["last_request"];
    if elapsed < _MIN_INTERVAL {
        time.sleep(_MIN_INTERVAL - elapsed);
    }
    _state["last_request"] = time.monotonic();
    resp = _session.get(url, params=params, timeout=timeout);
    resp.raise_for_status();
    return resp.json();
}

# ── Market Metadata ─────────────────────────────────────────

def get_market_by_id(market_id: str) -> dict | None {
    """Fetch a single market by its numeric gamma ID.""";
    data = _get(f"{GAMMA}/markets/{market_id}");
    if isinstance(data, dict) {
        return data;
    }
    return None;
}

def get_market_by_condition(condition_id: str) -> dict | None {
    """Fetch market by condition ID.""";
    data = _get(f"{GAMMA}/markets", params={"condition_id": condition_id});
    if isinstance(data, list) and len(data) > 0 {
        return data[0];
    }
    return None;
}

def get_event_by_slug(slug: str) -> dict | None {
    """Fetch event metadata including sub-markets.""";
    data = _get(f"{GAMMA}/events", params={"slug": slug});
    if isinstance(data, list) and len(data) > 0 {
        return data[0];
    }
    return None;
}

# ── Trades ───────────────────────────────────────────────────

def get_trades(condition_id: str, limit: int = 100, before_ts: int | None = None) -> list {
    """Fetch trades for a market condition ID.""";
    try {
        params = {"market": condition_id, "limit": limit};
        if before_ts is not None {
            params["before"] = before_ts;
        }
        data = _get(f"{DATA}/trades", params=params);
        if isinstance(data, list) {
            return data;
        }
    } except Exception {
    }
    return [];
}

def get_all_trades(condition_id: str, max_trades: int = 500) -> list {
    """Paginate through trades up to max_trades.""";
    all_trades = [];
    before_ts = None;
    while len(all_trades) < max_trades {
        batch = get_trades(condition_id, limit=min(100, max_trades - len(all_trades)),
                           before_ts=before_ts);
        if not batch {
            break;
        }
        all_trades.extend(batch);
        last_ts = batch[-1].get("timestamp");
        if last_ts is not None {
            before_ts = int(last_ts);
        } else {
            break;
        }
    }
    return all_trades;
}

# ── Price History ────────────────────────────────────────────

def get_price_history(condition_id: str, fidelity: int = 60) -> list {
    """Fetch price history from CLOB. fidelity = minutes per candle.""";
    try {
        data = _get(f"{CLOB}/prices-history",
                    params={"market": condition_id, "interval": "all", "fidelity": fidelity});
        if isinstance(data, dict) and "history" in data {
            return data["history"];
        }
    } except Exception {
    }
    return [];
}

# ── Resolve market ID to usable identifiers ──────────────────

def resolve_market(market_id: str) -> dict {
    """Given a market_id, resolve to a dict with condition_id, title, etc.""";
    try {
        if market_id.startswith("0x") {
            m = get_market_by_condition(market_id);
            if m {
                return _extract_market_info(m);
            }
        }
        if market_id.isdigit() {
            m = get_market_by_id(market_id);
            if m {
                return _extract_market_info(m);
            }
        }
        event = get_event_by_slug(market_id);
        if event and "markets" in event {
            markets = event["markets"];
            if markets {
                return _extract_market_info(markets[0]);
            }
        }
    } except Exception {
    }
    return {"market_id": market_id, "resolved": False};
}

def _extract_market_info(m: dict) -> dict {
    return {
        "market_id": str(m.get("id", "")),
        "condition_id": m.get("conditionId", m.get("condition_id", "")),
        "title": m.get("question", m.get("title", "")),
        "slug": m.get("slug", ""),
        "outcomes": m.get("outcomes", ""),
        "outcome_prices": m.get("outcomePrices", m.get("outcome_prices", "")),
        "volume": m.get("volume", 0),
        "volume_24h": m.get("volume24hr", 0),
        "liquidity": m.get("liquidity", 0),
        "end_date": m.get("endDate", m.get("end_date", "")),
        "active": m.get("active", False),
        "closed": m.get("closed", False),
        "resolved": True,
        "clob_token_ids": m.get("clobTokenIds", []),
        "best_bid": m.get("bestBid", None),
        "best_ask": m.get("bestAsk", None),
        "last_trade_price": m.get("lastTradePrice", None),
        "neg_risk_market_id": m.get("negRiskMarketID", "")
    };
}
