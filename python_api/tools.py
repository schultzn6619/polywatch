"""
polymarket_tools.py
═══════════════════
Polymarket Insider Trading Investigation Toolkit

API bases:
  Gamma API  →  https://gamma-api.polymarket.com   (market metadata, events, search)
  CLOB API   →  https://clob.polymarket.com         (orderbook, pricing, price history)
  Data API   →  https://data-api.polymarket.com     (trades, positions, holders, PnL)

Key concepts:
  Event      – A top-level topic (e.g. "Will the US strike Iran?")
  Market     – A specific binary question inside an event
  conditionId – The on-chain hex ID for a market (used by Data API and CLOB)
  clobTokenId – Per-outcome token ID used for orderbook and price-history calls
               (a binary market has two: one for YES, one for NO)
"""

import json
import requests
from collections import defaultdict
from datetime import datetime, timezone
from typing import Dict, List, Optional, Tuple

# ══════════════════════════════════════════════════════════════════
# Internal helpers
# ══════════════════════════════════════════════════════════════════

GAMMA = "https://gamma-api.polymarket.com"
CLOB  = "https://clob.polymarket.com"
DATA  = "https://data-api.polymarket.com"


def _get(url: str, **kwargs) -> Optional[any]:
    """GET with timeout and graceful error handling. Returns parsed JSON or None."""
    try:
        r = requests.get(url, timeout=15, **kwargs)
        r.raise_for_status()
        return r.json()
    except requests.RequestException as e:
        print(f"[HTTP ERROR] {url}\n  → {e}")
        return None


def _find_event_by_slug(slug: str) -> List[Dict]:
    """Find all events matching a given slug."""
    data = _get(f"{GAMMA}/events?slug={slug}")
    return data if data else []


def _parse_json_field(value, fallback=None):
    """Safely parse a JSON-string field (outcomes, outcomePrices, clobTokenIds, etc.)."""
    if value is None:
        return fallback if fallback is not None else []
    if isinstance(value, (list, dict)):
        return value
    try:
        return json.loads(value)
    except (json.JSONDecodeError, TypeError):
        return fallback if fallback is not None else []


def _ts(unix: float) -> str:
    """Format a Unix timestamp as a readable UTC string."""
    return datetime.fromtimestamp(unix, tz=timezone.utc).strftime("%Y-%m-%d %H:%M UTC")


def _divider(char="─", width=64) -> str:
    return char * width


def _get_market_meta(condition_id: str) -> Dict:
    """
    Fetch the Gamma market object by conditionId (hex, 0x-prefixed).
    Uses GET /markets?condition_ids= which is the correct Gamma param for conditionId.

    NOTE: conditionId (hex, 0x...) and questionId (large decimal number shown as
    'questionID' in get_event_info output) are DIFFERENT identifiers. This function
    takes conditionId. Use get_market_by_question_id() if you only have the questionId.
    """
    data = _get(f"{GAMMA}/markets", params={"condition_ids": condition_id})
    if not data:
        raise Exception(
            f"No market found for conditionId: {condition_id}\n"
            "  Ensure you are passing the hex conditionId (0x...) from get_event_info output,\n"
            "  not the questionId (large decimal number). These are different identifiers.\n"
            "  Use get_market_by_question_id() if you only have the questionId."
        )
    return data[0]


def _market_end_timestamp(condition_id: str) -> float:
    """
    Return the market's reference timestamp for pre-event analysis.
    Accepts conditionId (hex, 0x-prefixed) — not questionId.

    Returns min(endDate, now) so that:
      - Closed markets: reference time = endDate (moment of resolution)
      - Active markets:  reference time = now    (current moment)

    This prevents active markets from producing zero pre-event data points
    by avoiding a future reference timestamp.
    """
    market = _get_market_meta(condition_id)
    end_date = market.get("endDate")
    if not end_date:
        raise Exception(f"No endDate found for conditionId: {condition_id}")
    # endDate is ISO 8601, e.g. "2024-11-05T00:00:00Z"
    for fmt in ("%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S.%fZ", "%Y-%m-%dT%H:%M:%S"):
        try:
            end_ts = datetime.strptime(end_date, fmt).replace(tzinfo=timezone.utc).timestamp()
            now_ts = datetime.now(tz=timezone.utc).timestamp()
            return min(end_ts, now_ts)
        except ValueError:
            continue
    raise Exception(f"Could not parse endDate '{end_date}' for conditionId: {condition_id}")


def _market_start_timestamp(condition_id: str) -> float:
    """
    Return the market's startDate as a Unix timestamp (UTC).
    startDate is always in the past for any market that exists,
    making it reliable as a reference point for analysis on both
    active and closed markets.
    """
    market = _get_market_meta(condition_id)
    start_date = market.get("startDate")
    if not start_date:
        raise Exception(f"No startDate found for conditionId: {condition_id}")
    for fmt in ("%Y-%m-%dT%H:%M:%S.%fZ", "%Y-%m-%dT%H:%M:%SZ", "%Y-%m-%dT%H:%M:%S"):
        try:
            return datetime.strptime(start_date, fmt).replace(tzinfo=timezone.utc).timestamp()
        except ValueError:
            continue
    raise Exception(f"Could not parse startDate '{start_date}' for conditionId: {condition_id}")


def _clob_token_for_outcome(condition_id: str, outcome_index: int = 0) -> str:
    """
    Return the CLOB token ID for a specific outcome of a market.
    Accepts conditionId (hex, 0x-prefixed) — not questionId.
    outcome_index: 0 = first outcome (typically YES), 1 = second (typically NO).
    Works via Gamma metadata — no /book call needed, so works for closed markets.
    """
    market = _get_market_meta(condition_id)
    token_ids = _parse_json_field(market.get("clobTokenIds"))
    outcomes  = _parse_json_field(market.get("outcomes"))
    if not token_ids:
        raise Exception(f"No clobTokenIds found for conditionId: {condition_id}")
    if outcome_index >= len(token_ids):
        raise Exception(
            f"outcome_index {outcome_index} out of range — "
            f"market has {len(token_ids)} outcome(s): {outcomes}"
        )
    return token_ids[outcome_index]


def _resolve_proxy_wallet(wallet_address: str) -> str:
    """
    Resolve the proxyWallet address for a given wallet.

    Polymarket executes all trades through a proxy contract, not the user's EOA.
    The Data API 'user' param expects the proxyWallet address, not the main wallet.
    This function looks up the proxyWallet via Gamma's public-profile endpoint.

    Falls back to the original address silently if resolution fails — 404 is expected
    when the address is already a proxyWallet or has no Polymarket profile.
    """
    try:
        r = requests.get(
            f"{GAMMA}/public-profile",
            params={"address": wallet_address},
            timeout=10,
        )
        if r.status_code == 200:
            data = r.json()
            if data and data.get("proxyWallet"):
                return data["proxyWallet"]
    except requests.RequestException:
        pass
    return wallet_address


# ══════════════════════════════════════════════════════════════════
# ① EVENT DISCOVERY  (unchanged original + cleaned-up output)
# ══════════════════════════════════════════════════════════════════

def get_event_info(slug: str) -> str:
    """
    Fetch full event metadata by slug, including all nested markets.
    Entry point for any investigation — gives you conditionIds and
    clobTokenIds needed for every downstream function.

    Returns:
        summary (str): Full human-readable event + market breakdown.
    """
    events = _find_event_by_slug(slug)
    if not events:
        raise Exception(f"No event found for slug: '{slug}'")

    event = events[0]
    meta  = event.get("eventMetadata") or {}
    tags  = event.get("tags") or []
    tag_slugs = ", ".join(t.get("slug", "") for t in tags) or "none"

    lines = [
        f'Event: "{event.get("title", event.get("slug"))}"',
        _divider(),
        f'Slug:              {event.get("slug")}',
        f'Description:       {event.get("description")}',
        f'AI Context:        {meta.get("context_description")}',
        f'AI Context Date:   {meta.get("context_updated_at")}',
        f'Today:             {datetime.now().strftime("%Y-%m-%d %H:%M")}',
        f'Start Date:        {event.get("startDate")}',
        f'End Date:          {event.get("endDate")}',
        f'Active:            {event.get("active")}',
        f'Closed:            {event.get("closed")}',
        f'Tags:              {tag_slugs}',
        _divider("·"),
        f'Volume (all-time): ${event.get("volume")}',
        f'Volume 24h:        ${event.get("volume24hr")}',
        f'Volume 1wk:        ${event.get("volume1wk")}',
        f'Volume 1mo:        ${event.get("volume1mo")}',
        f'Volume 1yr:        ${event.get("volume1yr")}',
        f'Liquidity:         ${event.get("liquidity")}',
        f'Liquidity (CLOB):  ${event.get("liquidityClob")}',
        f'Open Interest:     ${event.get("openInterest")}',
        "",
    ]

    markets = event.get("markets") or []
    if not markets:
        raise Exception("No markets found for event.")

    lines.append(f"Markets ({len(markets)}):")
    lines.append(_divider())

    for i, m in enumerate(markets, 1):
        outcomes   = _parse_json_field(m.get("outcomes"))
        prices     = _parse_json_field(m.get("outcomePrices"))
        token_ids  = _parse_json_field(m.get("clobTokenIds"))

        outcome_pairs = "  |  ".join(
            f"{o}: {float(p):.3f}" for o, p in zip(outcomes, prices)
        ) if outcomes else "N/A"

        token_pairs = "  |  ".join(
            f"{o}: {t}" for o, t in zip(outcomes, token_ids)
        ) if token_ids else "N/A"

        lines += [
            f"[{i}] {m.get('question')}",
            f"     conditionId:      {m.get('conditionId')}",
            f"     questionId:       {m.get('questionID')}",
            f"     Active/Closed:    {m.get('active')} / {m.get('closed')}",
            f"     Accepting Orders: {m.get('acceptingOrders')}",
            f"     Start → End:      {m.get('startDate')} → {m.get('endDate')}",
            f"     Outcome Prices:   {outcome_pairs}",
            f"     Best Bid/Ask:     {m.get('bestBid')} / {m.get('bestAsk')}",
            f"     Spread:           {m.get('spread')}",
            f"     Last Trade Price: {m.get('lastTradePrice')}",
            f"     24h Price Δ:      {m.get('oneDayPriceChange')}",
            f"     1wk Price Δ:      {m.get('oneWeekPriceChange')}",
            f"     Volume (all):     ${m.get('volume')}",
            f"     Volume 24h:       ${m.get('volume24hr')}",
            f"     Volume 1mo:       ${m.get('volume1mo')}",
            f"     Liquidity:        ${m.get('liquidity')}",
            f"     clobTokenIds:     {token_pairs}",
            "",
        ]

    return "\n".join(lines)


def search_events(query: str, limit: int = 10) -> Tuple[str, Dict]:
    """
    Full-text search across events, markets, and profiles.
    Uses GET /public-search?q= — the only valid text-search endpoint.

    Returns:
        summary (str): Digest of matching events and tags.
        raw (dict):    { events[], tags[], profiles[], pagination }.
    """
    data = _get(f"{GAMMA}/public-search",
                params={"q": query, "limit_per_type": limit})
    if not data:
        raise Exception(f"No search results for: '{query}'")

    events     = data.get("events") or []
    tags       = data.get("tags") or []
    profiles   = data.get("profiles") or []
    pagination = data.get("pagination") or {}

    lines = [
        f"Search: '{query}'",
        f"Results: {len(events)} event(s)  {len(tags)} tag(s)  {len(profiles)} profile(s)",
        f"Has More: {pagination.get('hasMore')}   Total: {pagination.get('totalResults')}",
        _divider(),
    ]
    for i, ev in enumerate(events, 1):
        tag_slugs = ", ".join(t.get("slug", "") for t in (ev.get("tags") or []))
        lines += [
            f"[{i}] {ev.get('title', 'Untitled')}",
            f"     Slug:       {ev.get('slug')}",
            f"     Status:     {'Active' if ev.get('active') else 'Closed'}",
            f"     End Date:   {ev.get('endDate')}",
            f"     Volume:     ${ev.get('volume')}   Vol 24h: ${ev.get('volume24hr')}",
            f"     Liquidity:  ${ev.get('liquidity')}",
            f"     Markets:    {len(ev.get('markets') or [])}",
            f"     Tags:       {tag_slugs}",
            "",
        ]
    if tags:
        lines.append("Matching Tags:")
        for t in tags:
            lines.append(f"  • {t.get('label')} (slug: {t.get('slug')}, events: {t.get('event_count')})")

    return "\n".join(lines), data


def get_related_events(tag_slug: str, limit: int = 10) -> Tuple[str, List]:
    """
    Find events sharing a tag slug.
    Uses GET /events?tag_slug= on the Gamma API.

    Returns:
        summary (str): Compact event list with key metrics.
        raw (list):    Full event objects.
    """
    data = _get(f"{GAMMA}/events", params={"tag_slug": tag_slug, "limit": limit})
    if not data:
        raise Exception(f"No events for tag_slug: '{tag_slug}'")

    lines = [
        f"Events tagged '{tag_slug}'  [{len(data)} returned]",
        _divider(),
    ]
    for i, ev in enumerate(data, 1):
        lines += [
            f"[{i}] {ev.get('title', 'Untitled')}",
            f"     Slug:       {ev.get('slug')}",
            f"     Status:     {'Active' if ev.get('active') else 'Closed'}",
            f"     End Date:   {ev.get('endDate')}",
            f"     Volume:     ${ev.get('volume')}   Vol 24h: ${ev.get('volume24hr')}",
            f"     Liquidity:  ${ev.get('liquidity')}",
            f"     Open Int:   ${ev.get('openInterest')}",
            f"     Markets:    {len(ev.get('markets') or [])}",
            "",
        ]
    return "\n".join(lines), data


# ══════════════════════════════════════════════════════════════════
# ② MARKET ANALYSIS
# ══════════════════════════════════════════════════════════════════

def get_market_by_question_id(question_id: str) -> Tuple[str, Dict]:
    """
    Fetch a specific market by its questionId.
    Uses GET /markets?question_ids= on the Gamma API.

    questionId is the large decimal number shown as 'questionId' in get_event_info output.
    It is NOT the same as conditionId (the hex 0x... value).

    Use the conditionId (hex) for all statistical and trade-level functions.
    Use the questionId (decimal) for this function only.

    Args:
        question_id: The questionId decimal string from get_event_info output.

    Returns:
        summary (str): Full market snapshot including conditionId and clobTokenIds.
        raw (dict):    Full market object.
    """
    data = _get(f"{GAMMA}/markets", params={"question_ids": question_id})
    if not data:
        raise Exception(
            f"No market found for questionId: {question_id}\n"
            "  Ensure you are passing the questionId (large decimal number) from get_event_info output,\n"
            "  not the conditionId (hex 0x... string). These are different identifiers."
        )

    m = data[0]
    outcomes  = _parse_json_field(m.get("outcomes"))
    prices    = _parse_json_field(m.get("outcomePrices"))
    token_ids = _parse_json_field(m.get("clobTokenIds"))
    tags      = ", ".join(t.get("slug", "") for t in (m.get("tags") or [])) or "none"

    outcome_str = "  |  ".join(
        f"{o}: {float(p):.4f} [tokenId: {t}]"
        for o, p, t in zip(outcomes, prices, token_ids)
    ) if outcomes else "N/A"

    lines = [
        f"Market: {m.get('question')}",
        _divider(),
        f"conditionId:         {m.get('conditionId')}",
        f"Slug:                {m.get('slug')}",
        f"Active:              {m.get('active')}   Closed: {m.get('closed')}",
        f"Accepting Orders:    {m.get('acceptingOrders')}",
        f"Order Book Enabled:  {m.get('enableOrderBook')}",
        f"Start → End:         {m.get('startDate')} → {m.get('endDate')}",
        f"Tags:                {tags}",
        _divider("·"),
        f"Outcomes & Prices:   {outcome_str}",
        f"Best Bid / Ask:      {m.get('bestBid')} / {m.get('bestAsk')}",
        f"Spread:              {m.get('spread')}",
        f"Last Trade Price:    {m.get('lastTradePrice')}",
        f"1h Price Δ:          {m.get('oneHourPriceChange')}",
        f"24h Price Δ:         {m.get('oneDayPriceChange')}",
        f"1wk Price Δ:         {m.get('oneWeekPriceChange')}",
        _divider("·"),
        f"Volume (all-time):   ${m.get('volume')}",
        f"Volume 24h:          ${m.get('volume24hr')}",
        f"Volume 1wk:          ${m.get('volume1wk')}",
        f"Volume 1mo:          ${m.get('volume1mo')}",
        f"Volume 1yr:          ${m.get('volume1yr')}",
        f"Liquidity (total):   ${m.get('liquidity')}",
        f"Liquidity (CLOB):    ${m.get('liquidityClob')}",
        f"Liquidity (AMM):     ${m.get('liquidityAmm')}",
        f"Tick Size:           {m.get('orderPriceMinTickSize')}",
        f"Min Order Size:      {m.get('orderMinSize')}",
    ]
    return "\n".join(lines), m


def get_market_orderbook(clob_token_id: str) -> Tuple[str, Dict]:
    """
    Live order book for one outcome token.
    Uses GET /book?token_id= on the CLOB API.

    Note: a binary market has two tokens (YES and NO). Call this once
    per outcome to compare sentiment on each side.

    Returns:
        summary (str): Best bid/ask, spread, top-5 levels, and depth totals.
        raw (dict):    { market, asset_id, bids[], asks[], last_trade_price }.
    """
    data = _get(f"{CLOB}/book", params={"token_id": clob_token_id})
    if not data:
        raise Exception(f"No order book for token_id: {clob_token_id}")

    bids = data.get("bids") or []
    asks = data.get("asks") or []
    best_bid = bids[0] if bids else None
    best_ask = asks[0] if asks else None
    spread = (
        round(float(best_ask["price"]) - float(best_bid["price"]), 4)
        if best_bid and best_ask else "N/A"
    )
    bid_liq = sum(float(b["size"]) for b in bids)
    ask_liq = sum(float(a["size"]) for a in asks)

    def _fmt(levels, n=5):
        return "\n".join(
            f"       {lv.get('price'):>6}  ×  {lv.get('size')}" for lv in levels[:n]
        ) or "       (empty)"

    lines = [
        f"Order Book — token_id: {clob_token_id}",
        f"conditionId (market): {data.get('market')}",
        f"Last Trade Price:     {data.get('last_trade_price')}",
        _divider(),
        f"Best Bid:  {best_bid['price'] if best_bid else 'N/A'}  "
        f"(size: {best_bid['size'] if best_bid else 'N/A'})",
        f"Best Ask:  {best_ask['price'] if best_ask else 'N/A'}  "
        f"(size: {best_ask['size'] if best_ask else 'N/A'})",
        f"Spread:    {spread}",
        _divider("·"),
        f"Top Bids (price × size):\n{_fmt(bids)}",
        f"Top Asks (price × size):\n{_fmt(asks)}",
        _divider("·"),
        f"Total bid levels: {len(bids)}   Total bid liquidity: {bid_liq:.2f}",
        f"Total ask levels: {len(asks)}   Total ask liquidity: {ask_liq:.2f}",
    ]
    return "\n".join(lines), data


def get_market_price_history(
    clob_token_id: str,
    interval: str = "1w",
    fidelity: int = 100,
) -> Tuple[str, List]:
    """
    Historical price timeseries for one outcome token.
    Uses GET /prices-history?market=&interval=&fidelity= on the CLOB API.

    This endpoint is purely historical and works for both open and closed markets —
    unlike /book which becomes unavailable after market close.

    Args:
        clob_token_id: Token ID from a market's clobTokenIds (get from get_event_info).
        interval:      One of: 1h, 6h, 1d, 1w, 1m, max.
        fidelity:      Resolution in minutes.

    Returns:
        summary (str): High/low/current/trend for the period.
        raw (list):    [ { "t": unix_ts, "p": price }, ... ]
    """
    valid = {"1h", "6h", "1d", "1w", "1m", "max"}
    if interval not in valid:
        raise ValueError(f"interval must be one of {valid}, got '{interval}'")

    data = _get(f"{CLOB}/prices-history",
                params={"market": clob_token_id, "interval": interval, "fidelity": fidelity})
    if not data:
        raise Exception(f"No price history for token_id: {clob_token_id}")

    history = data.get("history") or []
    if not history:
        raise Exception("Price history is empty — market may be too new or inactive.")

    prices = [float(pt["p"]) for pt in history]
    times  = [pt["t"] for pt in history]
    cur    = prices[-1]
    hi     = max(prices)
    lo     = min(prices)
    mid    = len(prices) // 2
    trend  = "↑ Rising" if (sum(prices[mid:]) / max(len(prices) - mid, 1)) > (sum(prices[:mid]) / max(mid, 1)) else "↓ Falling"

    lines = [
        f"Price History — token_id: {clob_token_id}",
        f"Interval: {interval}   Fidelity: {fidelity} min/point   Points: {len(history)}",
        f"Period:   {_ts(times[0])}  →  {_ts(times[-1])}",
        _divider(),
        f"Current:  {cur:.4f}",
        f"High:     {hi:.4f}",
        f"Low:      {lo:.4f}",
        f"Range:    {hi - lo:.4f}",
        f"Trend:    {trend}",
    ]
    return "\n".join(lines), history


def get_market_price_history_range(
    condition_id: str,
    start_ts: float,
    end_ts: float,
    outcome_index: int = 0,
    fidelity: int = 60,
) -> Tuple[str, List]:
    """
    Historical price timeseries for a specific date range.
    Uses GET /prices-history?market=&startTs=&endTs= on the CLOB API.

    Works for open and closed markets — purely historical, no /book dependency.
    The CLOB token ID is resolved automatically from the market's Gamma metadata.

    Use this when you want to examine a precise window (e.g. the 3 days before
    a known news event) rather than a preset interval.

    Args:
        condition_id:  Market conditionId.
        start_ts:      Window start as Unix timestamp (UTC).
        end_ts:        Window end as Unix timestamp (UTC).
        outcome_index: Which outcome token (0 = first/YES, 1 = second/NO).
        fidelity:      Resolution in minutes.

    Returns:
        summary (str): High/low/open/close for the requested window.
        raw (list):    [ { "t": unix_ts, "p": price }, ... ]
    """
    clob_token_id = _clob_token_for_outcome(condition_id, outcome_index)

    data = _get(f"{CLOB}/prices-history",
                params={
                    "market":   clob_token_id,
                    "startTs":  int(start_ts),
                    "endTs":    int(end_ts),
                    "fidelity": fidelity,
                })
    if not data:
        raise Exception(f"No price history for conditionId: {condition_id} / token: {clob_token_id}")

    history = data.get("history") or []
    if not history:
        raise Exception(
            f"Price history returned empty for the requested window.\n"
            f"  Window: {_ts(start_ts)}  →  {_ts(end_ts)}\n"
            f"  token_id: {clob_token_id}"
        )

    prices = [float(pt["p"]) for pt in history]
    lines = [
        f"Price History (custom range) — conditionId: {condition_id}",
        f"CLOB token:  {clob_token_id}",
        f"Window:      {_ts(start_ts)}  →  {_ts(end_ts)}",
        f"Fidelity:    {fidelity} min/point   Points: {len(history)}",
        f"Actual span: {_ts(history[0]['t'])}  →  {_ts(history[-1]['t'])}",
        _divider(),
        f"Open:    {prices[0]:.4f}",
        f"Close:   {prices[-1]:.4f}",
        f"High:    {max(prices):.4f}",
        f"Low:     {min(prices):.4f}",
        f"Range:   {max(prices) - min(prices):.4f}",
    ]
    return "\n".join(lines), history


# ══════════════════════════════════════════════════════════════════
# ③ TRADE-LEVEL INVESTIGATION
# ══════════════════════════════════════════════════════════════════

def get_market_trades(
    condition_id: str,
    limit: int = 500,
    taker_only: bool = False,
) -> Tuple[str, List]:
    """
    All trades on a specific market.
    Uses GET /trades?market= on the Data API.

    The raw list is the backbone for every downstream trade analysis.
    Each trade includes: proxyWallet, side (BUY/SELL), size, price,
    timestamp, outcome, transactionHash.

    Args:
        condition_id: Market conditionId (hex).
        limit:        Max trades to fetch (up to 10,000 per Data API docs).
        taker_only:   If True, filter to taker-side trades only.

    Returns:
        summary (str): Count, sides, top wallets, time range.
        raw (list):    Full trade objects from the Data API.
    """
    data = _get(f"{DATA}/trades",
                params={"market": condition_id, "limit": limit, "takerOnly": str(taker_only).lower()})
    if data is None:
        raise Exception(f"Failed to fetch trades for market: {condition_id}")

    if not data:
        return f"No trades found for market: {condition_id}", []

    buys  = [t for t in data if t.get("side") == "BUY"]
    sells = [t for t in data if t.get("side") == "SELL"]
    wallets = defaultdict(float)
    for t in data:
        wallets[t.get("proxyWallet", "?")] += float(t.get("size", 0))

    times = sorted(t.get("timestamp", 0) for t in data if t.get("timestamp"))
    top_wallets = sorted(wallets.items(), key=lambda x: x[1], reverse=True)[:5]

    lines = [
        f"Market Trades — conditionId: {condition_id}",
        f"Fetched: {len(data)} trade(s)  (limit={limit}, takerOnly={taker_only})",
        f"Time range: {_ts(times[0])}  →  {_ts(times[-1])}" if times else "Time range: N/A",
        _divider(),
        f"BUY trades:   {len(buys)}",
        f"SELL trades:  {len(sells)}",
        f"Buy/Sell ratio: {len(buys)/max(len(sells),1):.2f}",
        f"Unique wallets: {len(wallets)}",
        _divider("·"),
        "Top 5 wallets by trade volume (shares):",
    ]
    for w, sz in top_wallets:
        lines.append(f"  {w}  →  {sz:.2f} shares")

    return "\n".join(lines), data


def get_large_trades(
    condition_id: str,
    min_size: float = 1000.0,
    limit: int = 500,
) -> Tuple[str, List]:
    """
    Trades above a minimum size threshold on a market — surfaces whale activity.
    Fetches market trades then filters client-side.

    Args:
        condition_id: Market conditionId.
        min_size:     Minimum trade size in shares (default 1,000).
        limit:        How many trades to pull before filtering.

    Returns:
        summary (str): Count, direction breakdown, top large traders.
        raw (list):    Filtered trade objects sorted by size descending.
    """
    _, all_trades = get_market_trades(condition_id, limit=limit)
    large = sorted(
        [t for t in all_trades if float(t.get("size", 0)) >= min_size],
        key=lambda t: float(t.get("size", 0)),
        reverse=True,
    )

    if not large:
        return f"No trades ≥ {min_size} shares found on market: {condition_id}", []

    buys  = [t for t in large if t.get("side") == "BUY"]
    sells = [t for t in large if t.get("side") == "SELL"]
    total_buy_size  = sum(float(t.get("size", 0)) for t in buys)
    total_sell_size = sum(float(t.get("size", 0)) for t in sells)

    lines = [
        f"Large Trades (≥ {min_size} shares) — conditionId: {condition_id}",
        f"Found: {len(large)} large trade(s) out of {len(all_trades)} total",
        _divider(),
        f"BUY  trades: {len(buys)}   total size: {total_buy_size:.2f}",
        f"SELL trades: {len(sells)}   total size: {total_sell_size:.2f}",
        _divider("·"),
        "Top 10 large trades:",
    ]
    for t in large[:10]:
        ts = _ts(t["timestamp"]) if t.get("timestamp") else "?"
        lines.append(
            f"  [{ts}] {t.get('side'):4s}  size: {float(t.get('size',0)):>10.2f}  "
            f"@ {t.get('price')}  outcome: {t.get('outcome')}  "
            f"wallet: {t.get('proxyWallet')}"
        )
    return "\n".join(lines), large


def get_pre_event_trades(
    condition_id: str,
    opening_hours: float = 24.0,
    limit: int = 1000,
) -> Tuple[str, List]:
    """
    Returns trades from the first N hours of actual trading activity on the market.

    Anchors to the first actual trade (not startDate), because trade data
    often begins days after market creation. This ensures results on any
    active or closed market that has trades.

    For backward-looking analysis from a specific timestamp,
    use get_pre_event_trades_at().

    Args:
        condition_id:  Market conditionId (hex, 0x-prefixed).
        opening_hours: How many hours from the first trade to include.
        limit:         Max trades to pull from the API before filtering.

    Returns:
        summary (str): Count, direction, wallets, timing quartile distribution.
        raw (list):    Trades in the opening window, sorted by timestamp.
    """
    _, all_trades = get_market_trades(condition_id, limit=limit)
    timed = sorted(
        [t for t in all_trades if t.get("timestamp")],
        key=lambda t: t["timestamp"],
    )
    if not timed:
        return f"No timestamped trades available for conditionId: {condition_id}", []

    actual_start = timed[0]["timestamp"]
    opening_end  = actual_start + opening_hours * 3600
    market_start = _market_start_timestamp(condition_id)
    data_gap     = (actual_start - market_start) / 3600

    label = (
        f"Opening Window ({opening_hours}h from first trade  —  "
        f"first trade was {data_gap:.1f}h after market start)"
        if data_gap > 1 else
        f"Opening Window ({opening_hours}h from first trade)"
    )
    # Use already-fetched trades directly to avoid a second API call
    window_trades = sorted(
        [t for t in timed if actual_start <= t["timestamp"] <= opening_end],
        key=lambda t: t["timestamp"],
    )
    if not window_trades:
        return (
            f"No trades in opening {opening_hours}h window.\n"
            f"  First trade: {_ts(actual_start)}\n"
            f"  Window end:  {_ts(opening_end)}\n"
            f"  conditionId: {condition_id}",
            [],
        )
    # Build summary directly (avoid double-fetching via _trades_in_window)
    buys    = [t for t in window_trades if t.get("side") == "BUY"]
    sells   = [t for t in window_trades if t.get("side") == "SELL"]
    wallets = defaultdict(float)
    for t in window_trades:
        wallets[t.get("proxyWallet", "?")] += float(t.get("size", 0))

    span = opening_end - actual_start
    q    = span / 4
    buckets = [0, 0, 0, 0]
    for t in window_trades:
        buckets[min(int((t["timestamp"] - actual_start) // q), 3)] += 1

    lines = [
        f"Trades — conditionId: {condition_id}",
        label,
        f"Window:         {_ts(actual_start)}  →  {_ts(opening_end)}",
        _divider(),
        f"Total trades:   {len(window_trades)}",
        f"BUY:            {len(buys)}   SELL: {len(sells)}",
        f"Buy/Sell ratio: {len(buys) / max(len(sells), 1):.2f}",
        f"Unique wallets: {len(wallets)}",
        _divider("·"),
        "Timing distribution (Q1=start of window, Q4=end of window):",
        f"  {buckets}",
        _divider("·"),
        "Top wallets by total size in window:",
    ]
    for w, sz in sorted(wallets.items(), key=lambda x: x[1], reverse=True)[:8]:
        lines.append(f"  {w}  →  {sz:.2f} shares")

    return "\n".join(lines), window_trades


def _trades_in_window(
    condition_id: str,
    window_start: float,
    window_end: float,
    label: str = "Window",
    limit: int = 1000,
) -> Tuple[str, List]:
    """
    Internal: returns trades in [window_start, window_end] with a summary.
    """
    _, all_trades = get_market_trades(condition_id, limit=limit)

    trades_in = sorted(
        [t for t in all_trades if t.get("timestamp") and window_start <= t["timestamp"] <= window_end],
        key=lambda t: t["timestamp"],
    )

    if not trades_in:
        return (
            f"No trades found in window: {_ts(window_start)}  →  {_ts(window_end)}\n"
            f"conditionId: {condition_id}",
            [],
        )

    buys    = [t for t in trades_in if t.get("side") == "BUY"]
    sells   = [t for t in trades_in if t.get("side") == "SELL"]
    wallets = defaultdict(float)
    for t in trades_in:
        wallets[t.get("proxyWallet", "?")] += float(t.get("size", 0))

    span = window_end - window_start
    q    = span / 4
    buckets = [0, 0, 0, 0]
    for t in trades_in:
        offset = t["timestamp"] - window_start
        buckets[min(int(offset // q), 3)] += 1

    lines = [
        f"Trades — conditionId: {condition_id}",
        f"{label}",
        f"Window:         {_ts(window_start)}  →  {_ts(window_end)}",
        _divider(),
        f"Total trades:   {len(trades_in)}",
        f"BUY:            {len(buys)}   SELL: {len(sells)}",
        f"Buy/Sell ratio: {len(buys) / max(len(sells), 1):.2f}",
        f"Unique wallets: {len(wallets)}",
        _divider("·"),
        "Timing distribution (Q1=start of window, Q4=end of window):",
        f"  {buckets}",
        _divider("·"),
        "Top wallets by total size in window:",
    ]
    for w, sz in sorted(wallets.items(), key=lambda x: x[1], reverse=True)[:8]:
        lines.append(f"  {w}  →  {sz:.2f} shares")

    return "\n".join(lines), trades_in


def get_pre_event_trades_at(
    condition_id: str,
    event_timestamp: float,
    lookback_hours: float = 24.0,
    limit: int = 1000,
) -> Tuple[str, List]:
    """
    Returns trades placed within a window ending at a specific timestamp.
    Use for backward-looking analysis (e.g. trades before a known resolution moment).

    Args:
        condition_id:    Market conditionId (hex, 0x-prefixed).
        event_timestamp: Unix timestamp of the reference moment.
        lookback_hours:  How many hours before the reference time to include.
        limit:           Max trades to pull from the API before filtering.

    Returns:
        summary (str): Count, direction, wallets, timing quartile distribution.
        raw (list):    Trades in the window, sorted by timestamp.
    """
    window_start = event_timestamp - lookback_hours * 3600
    return _trades_in_window(
        condition_id, window_start, event_timestamp,
        label=f"Pre-Event Window ({lookback_hours}h before {_ts(event_timestamp)})",
        limit=limit,
    )


# ══════════════════════════════════════════════════════════════════
# ④ STATISTICAL & ANOMALY DETECTION
# ══════════════════════════════════════════════════════════════════

def compute_price_run_up(
    condition_id: str,
    outcome_index: int = 0,
    opening_hours: float = 24.0,
    baseline_hours: float = 72.0,
) -> str:
    """
    Compares price movement in the first N hours of available price data
    to the subsequent baseline period.

    Anchors to the first actual price data point (not startDate), because
    CLOB price history often begins days after market creation. This ensures
    both windows always contain data on any active or closed market.

    For backward-looking analysis relative to a specific timestamp,
    use compute_price_run_up_at().

    Args:
        condition_id:   Market conditionId (hex, 0x-prefixed).
        outcome_index:  Which outcome token to analyse (0 = first/YES, 1 = second/NO).
        opening_hours:  Length of the opening window from first available data.
        baseline_hours: Length of the subsequent comparison period.

    Returns:
        summary (str): Opening vs baseline avg price, drift, up-tick fraction.
    """
    clob_token_id = _clob_token_for_outcome(condition_id, outcome_index)
    market_start  = _market_start_timestamp(condition_id)

    _, history = get_market_price_history(clob_token_id, interval="max", fidelity=60)
    if not history:
        raise Exception(f"No price history for token_id: {clob_token_id}")

    # Anchor to the first actual data point — not startDate, which may predate
    # available history by days or weeks.
    actual_start = history[0]["t"]
    opening_end  = actual_start + opening_hours * 3600
    baseline_end = opening_end  + baseline_hours * 3600

    opening_pts  = [pt for pt in history if actual_start <= pt["t"] <  opening_end]
    baseline_pts = [pt for pt in history if opening_end  <= pt["t"] <= baseline_end]

    data_gap_hours = (actual_start - market_start) / 3600

    lines = [
        f"Price Run-Up Analysis — conditionId: {condition_id}",
        f"CLOB token:          {clob_token_id}",
        f"Market start:        {_ts(market_start)}",
        f"First data point:    {_ts(actual_start)}"
        + (f"  ({data_gap_hours:.1f}h after market start)" if data_gap_hours > 1 else ""),
        f"Opening window:      {_ts(actual_start)}  →  {_ts(opening_end)}  ({opening_hours}h)",
        f"Baseline window:     {_ts(opening_end)}  →  {_ts(baseline_end)}  ({baseline_hours}h)",
        f"Total data points:   {len(history)}  spanning  "
        f"{_ts(history[0]['t'])}  →  {_ts(history[-1]['t'])}",
        _divider(),
    ]

    opening_avg = baseline_avg = None

    if opening_pts:
        opening_prices = [float(p["p"]) for p in opening_pts]
        opening_avg    = sum(opening_prices) / len(opening_pts)
        lines += [
            f"Opening avg price:   {opening_avg:.4f}  ({len(opening_pts)} points)",
            f"Opening high/low:    {max(opening_prices):.4f} / {min(opening_prices):.4f}",
        ]
    else:
        lines.append("Opening window:      no data")

    if baseline_pts:
        baseline_prices = [float(p["p"]) for p in baseline_pts]
        baseline_avg    = sum(baseline_prices) / len(baseline_pts)
        lines += [
            f"Baseline avg price:  {baseline_avg:.4f}  ({len(baseline_pts)} points)",
            f"Baseline high/low:   {max(baseline_prices):.4f} / {min(baseline_prices):.4f}",
        ]
    else:
        lines.append("Baseline window:     no data")

    if opening_avg is not None and baseline_avg is not None:
        drift     = opening_avg - baseline_avg
        drift_pct = (drift / baseline_avg * 100) if baseline_avg else 0
        prices    = [float(p["p"]) for p in opening_pts]
        up_ticks  = sum(1 for i in range(1, len(prices)) if prices[i] > prices[i - 1])
        up_pct    = up_ticks / max(len(prices) - 1, 1) * 100
        lines += [
            _divider("·"),
            f"Opening vs baseline drift (absolute): {drift:+.4f}",
            f"Opening vs baseline drift (%):        {drift_pct:+.2f}%",
            f"Up-tick fraction (opening):           {up_pct:.1f}% of opening ticks moved upward",
        ]

    return "\n".join(lines)


def compute_price_run_up_at(
    condition_id: str,
    clob_token_id: str,
    event_timestamp: float,
    baseline_hours: float = 72.0,
    pre_event_hours: float = 24.0,
) -> str:
    """
    Measures price drift relative to a specific reference timestamp.
    Use when probing a moment other than market close (e.g. a news event).

    Args:
        condition_id:    Market conditionId (for labelling only).
        clob_token_id:   The specific CLOB token to fetch history for.
        event_timestamp: Unix timestamp of the reference moment.
        baseline_hours:  Length of the comparison baseline.
        pre_event_hours: The window immediately before the reference time.

    Returns:
        summary (str): Baseline avg, pre-event avg, run-up stats.
    """
    _, history = get_market_price_history(clob_token_id, interval="max", fidelity=60)
    if not history:
        raise Exception(
            f"No price history for token_id: {clob_token_id}\n"
            "Note: /prices-history is used (not /book), so this should work even for closed markets."
        )

    baseline_start = event_timestamp - (baseline_hours + pre_event_hours) * 3600
    pre_start      = event_timestamp - pre_event_hours * 3600

    baseline_pts = [pt for pt in history if baseline_start <= pt["t"] < pre_start]
    pre_pts      = [pt for pt in history if pre_start <= pt["t"] <= event_timestamp]

    if not baseline_pts or not pre_pts:
        return (
            f"Insufficient data to compute run-up.\n"
            f"  Baseline points: {len(baseline_pts)}   Pre-event points: {len(pre_pts)}\n"
            f"  Total history points available: {len(history)}\n"
            f"  History spans: {_ts(history[0]['t'])}  →  {_ts(history[-1]['t'])}"
        )

    baseline_avg = sum(float(p["p"]) for p in baseline_pts) / len(baseline_pts)
    pre_avg      = sum(float(p["p"]) for p in pre_pts) / len(pre_pts)
    run_up       = pre_avg - baseline_avg
    run_up_pct   = (run_up / baseline_avg * 100) if baseline_avg else 0

    # Fraction of pre-event ticks that moved upward
    pre_prices = [float(p["p"]) for p in pre_pts]
    up_ticks   = sum(1 for i in range(1, len(pre_prices)) if pre_prices[i] > pre_prices[i-1])
    up_pct     = up_ticks / max(len(pre_prices) - 1, 1) * 100

    lines = [
        f"Price Run-Up Analysis — conditionId: {condition_id}",
        f"CLOB token:          {clob_token_id}",
        f"Reference time:      {_ts(event_timestamp)}",
        f"Baseline window:     {_ts(baseline_start)}  →  {_ts(pre_start)}  ({baseline_hours}h)",
        f"Pre-event window:    {_ts(pre_start)}  →  {_ts(event_timestamp)}  ({pre_event_hours}h)",
        _divider(),
        f"Baseline avg price:  {baseline_avg:.4f}  ({len(baseline_pts)} data points)",
        f"Pre-event avg price: {pre_avg:.4f}  ({len(pre_pts)} data points)",
        f"Run-up (absolute):   {run_up:+.4f}",
        f"Run-up (%):          {run_up_pct:+.2f}%",
        f"Up-tick fraction:    {up_pct:.1f}% of pre-event price ticks moved upward",
    ]
    return "\n".join(lines)


def compute_abnormal_volume(
    condition_id: str,
    opening_hours: float = 24.0,
    baseline_hours: float = 72.0,
    limit: int = 2000,
) -> str:
    """
    Compares trading volume in the first N hours of actual trading activity
    to the subsequent baseline period, normalised to shares/hr.

    Anchors to the first actual trade (not startDate), because trade data
    often begins days after market creation. Both windows will always contain
    data on any active or closed market that has trades.

    For backward-looking analysis relative to a specific timestamp,
    use compute_abnormal_volume_at().

    Args:
        condition_id:   Market conditionId (hex, 0x-prefixed).
        opening_hours:  Length of the opening window from first trade.
        baseline_hours: Length of the subsequent comparison period.
        limit:          Max trades to pull from the Data API.

    Returns:
        summary (str): Opening rate, baseline rate, ratio, direction split.
    """
    market_start  = _market_start_timestamp(condition_id)

    _, all_trades = get_market_trades(condition_id, limit=limit)
    if not all_trades:
        return f"No trades available for conditionId: {condition_id}"

    timed = [t for t in all_trades if t.get("timestamp")]
    if not timed:
        return f"All fetched trades are missing timestamps for conditionId: {condition_id}"

    # Anchor to the earliest actual trade, not startDate
    actual_start = min(t["timestamp"] for t in timed)
    opening_end  = actual_start + opening_hours * 3600
    baseline_end = opening_end  + baseline_hours * 3600

    data_gap_hours = (actual_start - market_start) / 3600

    opening_trades  = [t for t in timed if actual_start <= t["timestamp"] <  opening_end]
    baseline_trades = [t for t in timed if opening_end  <= t["timestamp"] <= baseline_end]

    opening_size  = sum(float(t.get("size", 0)) for t in opening_trades)
    baseline_size = sum(float(t.get("size", 0)) for t in baseline_trades)
    opening_rate  = opening_size  / max(opening_hours, 1)
    baseline_rate = baseline_size / max(baseline_hours, 1)
    ratio         = opening_rate / max(baseline_rate, 0.001)

    opening_buys  = sum(1 for t in opening_trades  if t.get("side") == "BUY")
    opening_sells = sum(1 for t in opening_trades  if t.get("side") == "SELL")
    base_buys     = sum(1 for t in baseline_trades if t.get("side") == "BUY")
    base_sells    = sum(1 for t in baseline_trades if t.get("side") == "SELL")

    lines = [
        f"Volume Analysis — conditionId: {condition_id}",
        f"Market start:        {_ts(market_start)}",
        f"First trade:         {_ts(actual_start)}"
        + (f"  ({data_gap_hours:.1f}h after market start)" if data_gap_hours > 1 else ""),
        f"Opening window:      {_ts(actual_start)}  →  {_ts(opening_end)}  ({opening_hours}h)",
        f"Baseline window:     {_ts(opening_end)}  →  {_ts(baseline_end)}  ({baseline_hours}h)",
        f"Total trades fetched: {len(all_trades)}",
        _divider(),
        f"Opening:   {len(opening_trades):4d} trades   {opening_size:10.2f} shares   "
        f"{opening_rate:8.2f} shares/hr   {opening_buys} BUY / {opening_sells} SELL",
        f"Baseline:  {len(baseline_trades):4d} trades   {baseline_size:10.2f} shares   "
        f"{baseline_rate:8.2f} shares/hr   {base_buys} BUY / {base_sells} SELL",
        f"Opening/baseline ratio: {ratio:.2f}×",
    ]
    return "\n".join(lines)


def compute_abnormal_volume_at(
    condition_id: str,
    event_timestamp: float,
    baseline_hours: float = 72.0,
    pre_event_hours: float = 24.0,
    limit: int = 2000,
) -> str:
    """
    Compares trading volume before a specific timestamp to a baseline period.
    Use when probing a moment other than market close (e.g. a news event).

    Args:
        condition_id:    Market conditionId.
        event_timestamp: Unix timestamp of the reference moment.
        baseline_hours:  Length of the comparison baseline.
        pre_event_hours: The window immediately before the reference time.
        limit:           Max trades to pull.

    Returns:
        summary (str): Baseline rate, pre-event rate, pre/baseline ratio, direction split.
    """
    _, all_trades = get_market_trades(condition_id, limit=limit)
    if not all_trades:
        return f"No trades available for conditionId: {condition_id}"

    baseline_start  = event_timestamp - (baseline_hours + pre_event_hours) * 3600
    pre_start       = event_timestamp - pre_event_hours * 3600

    baseline_trades = [t for t in all_trades if baseline_start <= (t.get("timestamp") or 0) < pre_start]
    pre_trades      = [t for t in all_trades if pre_start <= (t.get("timestamp") or 0) <= event_timestamp]

    baseline_size = sum(float(t.get("size", 0)) for t in baseline_trades)
    pre_size      = sum(float(t.get("size", 0)) for t in pre_trades)

    baseline_rate = baseline_size / max(baseline_hours, 1)
    pre_rate      = pre_size / max(pre_event_hours, 1)
    ratio         = pre_rate / max(baseline_rate, 0.001)

    pre_buys  = sum(1 for t in pre_trades if t.get("side") == "BUY")
    pre_sells = sum(1 for t in pre_trades if t.get("side") == "SELL")

    lines = [
        f"Volume Analysis — conditionId: {condition_id}",
        f"Reference time:      {_ts(event_timestamp)}",
        f"Baseline window:     {_ts(baseline_start)}  →  {_ts(pre_start)}  ({baseline_hours}h)",
        f"Pre-event window:    {_ts(pre_start)}  →  {_ts(event_timestamp)}  ({pre_event_hours}h)",
        _divider(),
        f"Baseline:            {len(baseline_trades)} trades   {baseline_size:.2f} shares   {baseline_rate:.2f} shares/hr",
        f"Pre-event:           {len(pre_trades)} trades   {pre_size:.2f} shares   {pre_rate:.2f} shares/hr",
        f"Pre/baseline ratio:  {ratio:.2f}×",
        f"Pre-event direction: {pre_buys} BUY / {pre_sells} SELL",
    ]
    return "\n".join(lines)


def find_synchronized_traders(
    condition_id: str,
    time_window_seconds: int = 300,
    min_cluster_size: int = 2,
    limit: int = 1000,
) -> Tuple[str, List]:
    """
    Identifies clusters of different wallets that placed trades in the same
    direction within a tight time window.

    Args:
        condition_id:        Market conditionId.
        time_window_seconds: Max seconds between trades to be considered synchronized.
        min_cluster_size:    Minimum distinct wallets in a cluster to report it.
        limit:               Max trades to pull from the Data API.

    Returns:
        summary (str): Full cluster breakdown with per-wallet trade detail.
        raw (list):    List of cluster dicts { direction, trades[], wallets[],
                       time_span, start_ts, end_ts, total_size, avg_price }.
    """
    _, all_trades = get_market_trades(condition_id, limit=limit)
    if not all_trades:
        return f"No trades available for conditionId: {condition_id}", []

    timed = sorted(
        [t for t in all_trades if t.get("timestamp")],
        key=lambda t: t["timestamp"],
    )

    clusters = []
    i = 0
    while i < len(timed):
        anchor = timed[i]
        group  = [anchor]
        j = i + 1
        while j < len(timed):
            if (timed[j]["timestamp"] - anchor["timestamp"]) <= time_window_seconds:
                group.append(timed[j])
                j += 1
            else:
                break

        for direction in ("BUY", "SELL"):
            dir_group = [t for t in group if t.get("side") == direction]
            wallets   = list({t.get("proxyWallet") for t in dir_group})
            if len(wallets) >= min_cluster_size:
                sizes  = [float(t.get("size", 0)) for t in dir_group]
                prices = [float(t.get("price", 0)) for t in dir_group if t.get("price")]
                clusters.append({
                    "direction":  direction,
                    "trades":     dir_group,
                    "wallets":    wallets,
                    "time_span":  dir_group[-1]["timestamp"] - dir_group[0]["timestamp"],
                    "start_ts":   dir_group[0]["timestamp"],
                    "end_ts":     dir_group[-1]["timestamp"],
                    "total_size": sum(sizes),
                    "avg_price":  sum(prices) / len(prices) if prices else None,
                })
        i = j if j > i else i + 1

    clusters.sort(key=lambda c: len(c["wallets"]), reverse=True)

    if not clusters:
        return (
            f"No synchronized trading clusters found\n"
            f"  conditionId:   {condition_id}\n"
            f"  Time window:   {time_window_seconds}s\n"
            f"  Min wallets:   {min_cluster_size}\n"
            f"  Trades scanned: {len(timed)}",
            [],
        )

    # Total volume across all fetched trades for context
    total_market_size = sum(float(t.get("size", 0)) for t in all_trades)

    # Wallets that appear in more than one cluster
    wallet_cluster_count: Dict[str, int] = defaultdict(int)
    for cl in clusters:
        for w in cl["wallets"]:
            wallet_cluster_count[w] += 1
    multi_cluster_wallets = {w for w, c in wallet_cluster_count.items() if c > 1}

    # Market start for time-since-open labelling
    try:
        market_start_ts = _market_start_timestamp(condition_id)
    except Exception:
        market_start_ts = None

    lines = [
        f"Synchronized Trader Analysis — conditionId: {condition_id}",
        f"Trades scanned:  {len(timed)} (of {len(all_trades)} fetched)   "
        f"Total volume in fetch: {total_market_size:.2f} shares",
        f"Time window:     {time_window_seconds}s   Min wallets: {min_cluster_size}",
        f"Clusters found:  {len(clusters)}",
        f"Unique wallets across all clusters: {len(wallet_cluster_count)}",
    ]
    if multi_cluster_wallets:
        lines.append(f"Wallets in multiple clusters: {len(multi_cluster_wallets)}")
        for w in sorted(multi_cluster_wallets):
            lines.append(f"  {w}  (appears in {wallet_cluster_count[w]} clusters)")
    lines.append(_divider())

    for idx, cl in enumerate(clusters[:10], 1):
        avg_p    = f"{cl['avg_price']:.4f}" if cl["avg_price"] is not None else "N/A"
        span_str = f"{cl['time_span']:.0f}s" if cl["time_span"] > 0 else "<1s"
        vol_pct  = (cl["total_size"] / total_market_size * 100) if total_market_size else 0

        # Time since market open
        if market_start_ts:
            hrs_since_open = (cl["start_ts"] - market_start_ts) / 3600
            open_label = f"{hrs_since_open:.1f}h after market open"
        else:
            open_label = "market open time unavailable"

        lines += [
            f"Cluster [{idx}]  {cl['direction']}",
            f"  Start:         {_ts(cl['start_ts'])}  ({open_label})",
            f"  End:           {_ts(cl['end_ts'])}",
            f"  Time span:     {span_str}",
            f"  Wallets:       {len(cl['wallets'])}",
            f"  Trades:        {len(cl['trades'])}",
            f"  Total size:    {cl['total_size']:.2f} shares  "
            f"({vol_pct:.2f}% of fetched market volume)",
            f"  Avg price:     {avg_p}",
        ]

        # Per-wallet breakdown inside this cluster
        wallet_trades: Dict[str, List] = defaultdict(list)
        for t in cl["trades"]:
            wallet_trades[t.get("proxyWallet", "?")].append(t)

        lines.append(f"  Wallet breakdown:")
        for wallet, wt in sorted(wallet_trades.items(),
                                  key=lambda x: sum(float(t.get("size", 0)) for t in x[1]),
                                  reverse=True):
            w_size   = sum(float(t.get("size", 0)) for t in wt)
            w_prices = [float(t.get("price", 0)) for t in wt if t.get("price")]
            w_avg_p  = f"{sum(w_prices)/len(w_prices):.4f}" if w_prices else "N/A"
            multi    = " ★" if wallet in multi_cluster_wallets else ""
            lines.append(
                f"    {wallet}{multi}\n"
                f"      trades: {len(wt)}   size: {w_size:.2f}   avg price: {w_avg_p}"
            )
            # Each individual trade for this wallet in this cluster
            for t in sorted(wt, key=lambda t: t.get("timestamp", 0)):
                ts_str  = _ts(t["timestamp"]) if t.get("timestamp") else "?"
                tx_hash = t.get("transactionHash", "N/A")
                outcome = t.get("outcome", "?")
                lines.append(
                    f"      [{ts_str}]  size: {float(t.get('size', 0)):.2f}"
                    f"  @ {t.get('price', '?')}  outcome: {outcome}"
                    f"  tx: {tx_hash}"
                )

        lines.append("")

    if len(clusters) > 10:
        lines.append(f"... {len(clusters) - 10} additional cluster(s) in raw output.")

    return "\n".join(lines), clusters


def get_market_movers(
    condition_id: str,
    limit: int = 50,
) -> Tuple[str, List]:
    """
    Wallets ranked by current position size on a market — the biggest holders.
    Uses GET /v1/market-positions?market= on the Data API.

    Useful for quickly identifying who has the most skin in the game
    and whether large holders entered before or after public news.

    Returns:
        summary (str): Top holders table with sizes, PnL, and entry prices.
        raw (list):    Full position objects from both YES and NO token sides.
    """
    data = _get(f"{DATA}/v1/market-positions",
                params={"market": condition_id, "limit": limit, "sortBy": "TOKENS", "sortDirection": "DESC"})
    if not data:
        raise Exception(f"No position data for market: {condition_id}")

    # Response is [ { token: str, positions: [...] }, ... ]
    all_positions = []
    for token_bucket in data:
        token = token_bucket.get("token", "?")
        for pos in token_bucket.get("positions") or []:
            pos["_token"] = token
            all_positions.append(pos)

    all_positions.sort(key=lambda p: float(p.get("size", 0)), reverse=True)

    lines = [
        f"Market Movers — conditionId: {condition_id}",
        f"Top {min(limit, len(all_positions))} positions by size",
        _divider(),
    ]
    for p in all_positions[:20]:
        pnl_str = f"cashPnl: {float(p.get('cashPnl',0)):+.2f}  totalPnl: {float(p.get('totalPnl',0)):+.2f}"
        lines.append(
            f"  {p.get('proxyWallet')}  |  outcome: {p.get('outcome')}  "
            f"|  size: {float(p.get('size',0)):.2f}  |  avgPrice: {p.get('avgPrice')}  "
            f"|  {pnl_str}"
        )

    return "\n".join(lines), all_positions


def get_market_top_holders(
    condition_id: str,
    min_balance: int = 1,
    limit: int = 20,
) -> Tuple[str, Dict]:
    """
    Top token holders for a market by current balance.
    Uses GET /holders?market= on the Data API.

    Returns:
        summary (str): Top holders per outcome token.
        raw (dict):    Full response { token: str, holders: [...] }.
    """
    data = _get(f"{DATA}/holders",
                params={"market": condition_id, "limit": limit, "minBalance": min_balance})
    if not data:
        raise Exception(f"No holder data for market: {condition_id}")

    lines = [
        f"Top Holders — conditionId: {condition_id}",
        _divider(),
    ]
    for bucket in data:
        token = bucket.get("token", "?")
        holders = bucket.get("holders") or []
        lines.append(f"Token: {token}  ({len(holders)} holders)")
        for h in holders[:10]:
            name        = h.get("name") or h.get("pseudonym") or "Anonymous"
            proxy_wallet = h.get("proxyWallet", "?")
            lines.append(
                f"   {name}  ({proxy_wallet})"
                f"  |  balance: {h.get('amount')}"
                f"  |  outcome: {h.get('outcomeIndex')}"
            )
        lines.append("")

    return "\n".join(lines), data


# ══════════════════════════════════════════════════════════════════
# ⑤ WALLET PROFILING
# ══════════════════════════════════════════════════════════════════

def get_wallet_profile(wallet_address: str) -> str:
    """
    Public profile + trading summary for a wallet.
    Combines Gamma /public-profile and Data API /trades + /positions.

    Returns:
        summary (str): Identity, trading stats, current positions snapshot.
    """
    profile  = _get(f"{GAMMA}/public-profile", params={"address": wallet_address}) or {}
    trades   = _get(f"{DATA}/trades", params={"user": wallet_address, "limit": 500}) or []
    positions = _get(f"{DATA}/positions", params={"user": wallet_address, "limit": 50}) or []

    name = (
        profile.get("name") or profile.get("pseudonym") or
        profile.get("displayUsernamePublic") or "Anonymous"
    )
    markets_traded = len({t.get("conditionId") for t in trades})
    buys  = [t for t in trades if t.get("side") == "BUY"]
    sells = [t for t in trades if t.get("side") == "SELL"]
    total_vol = sum(float(t.get("usdcSize", 0)) for t in trades)

    earliest = min((t.get("timestamp", float("inf")) for t in trades), default=None)
    latest   = max((t.get("timestamp", 0) for t in trades), default=None)

    open_pos = len(positions)
    total_cur_val = sum(float(p.get("currentValue", 0)) for p in positions)
    total_cash_pnl = sum(float(p.get("cashPnl", 0)) for p in positions)

    lines = [
        f"Wallet Profile: {wallet_address}",
        _divider(),
        f"Name:            {name}",
        f"Bio:             {profile.get('bio', 'N/A')}",
        f"X (Twitter):     {profile.get('xUsername', 'N/A')}",
        f"Verified:        {profile.get('verifiedBadge', False)}",
        f"Proxy Wallet:    {profile.get('proxyWallet', wallet_address)}",
        f"Profile Created: {profile.get('createdAt', 'N/A')}",
        _divider("·"),
        f"Trade History (last {len(trades)} fetched):",
        f"  First trade:     {_ts(earliest) if earliest else 'N/A'}",
        f"  Latest trade:    {_ts(latest) if latest else 'N/A'}",
        f"  Markets traded:  {markets_traded}",
        f"  BUY trades:      {len(buys)}",
        f"  SELL trades:     {len(sells)}",
        f"  Total USDC vol:  ${total_vol:.2f}",
        _divider("·"),
        f"Open Positions ({open_pos}):",
        f"  Total cur. value: ${total_cur_val:.2f}",
        f"  Total cash PnL:   ${total_cash_pnl:+.2f}",
    ]
    for p in positions[:5]:
        lines.append(
            f"  • {p.get('title', p.get('conditionId','?')[:20])}  "
            f"outcome: {p.get('outcome')}  size: {p.get('size')}  "
            f"curPrice: {p.get('curPrice')}  cashPnl: {float(p.get('cashPnl',0)):+.2f}"
        )

    return "\n".join(lines)


def get_wallet_trade_history(
    wallet_address: str,
    limit: int = 200,
    condition_id: Optional[str] = None,
) -> Tuple[str, List]:
    """
    Full paginated trade history for a wallet across all markets.
    Uses GET /trades?user= on the Data API.

    Automatically resolves the proxyWallet address via Gamma's public-profile
    endpoint, since the Data API expects the proxy contract address, not the
    user's EOA. The resolved proxyWallet is shown in the summary.

    Optionally filter to a single market with condition_id.

    Returns:
        summary (str): Time range, market count, direction split, top markets.
        raw (list):    Full trade objects.
    """
    proxy = _resolve_proxy_wallet(wallet_address)
    params: Dict = {"user": proxy, "limit": limit}
    if condition_id:
        params["market"] = condition_id

    data = _get(f"{DATA}/trades", params=params) or []

    proxy_note = f"  (resolved proxyWallet: {proxy})" if proxy != wallet_address else ""
    if not data:
        if condition_id:
            # Retry without market filter to distinguish "wrong wallet" from "no trades on this market"
            all_data = _get(f"{DATA}/trades", params={"user": proxy, "limit": 5}) or []
            if all_data:
                return (
                    f"No trades found for wallet on conditionId: {condition_id}\n"
                    f"  Wallet:  {wallet_address}{proxy_note}\n"
                    f"  Wallet has trades on other markets ({len(all_data)} fetched in check).",
                    [],
                )
        return (
            f"No trade history found for wallet: {wallet_address}{proxy_note}\n"
            "  The wallet may not have traded on Polymarket, or the address may be an EOA\n"
            "  rather than a proxy wallet. Try get_wallet_profile() first to confirm the address.",
            [],
        )

    buys  = [t for t in data if t.get("side") == "BUY"]
    sells = [t for t in data if t.get("side") == "SELL"]
    times = sorted(t.get("timestamp", 0) for t in data if t.get("timestamp"))
    markets_hit = defaultdict(int)
    for t in data:
        markets_hit[t.get("title") or t.get("conditionId", "?")] += 1

    lines = [
        f"Trade History — wallet: {wallet_address}",
        f"Fetched: {len(data)} trade(s)  (limit={limit})",
        f"Period: {_ts(times[0])}  →  {_ts(times[-1])}" if len(times) >= 2 else "",
        _divider(),
        f"BUY trades:   {len(buys)}",
        f"SELL trades:  {len(sells)}",
        f"Unique markets: {len(markets_hit)}",
        _divider("·"),
        "Most traded markets:",
    ]
    for title, count in sorted(markets_hit.items(), key=lambda x: x[1], reverse=True)[:8]:
        lines.append(f"  [{count:3d}×]  {str(title)[:60]}")

    lines += [
        _divider("·"),
        "Last 5 trades:",
    ]
    for t in sorted(data, key=lambda t: t.get("timestamp", 0), reverse=True)[:5]:
        ts = _ts(t["timestamp"]) if t.get("timestamp") else "?"
        lines.append(
            f"  [{ts}] {t.get('side'):4s}  {float(t.get('size',0)):>10.2f} shares  "
            f"@ {t.get('price')}  {str(t.get('title','?'))[:40]}"
        )

    return "\n".join(lines), data


def get_wallet_pnl(wallet_address: str) -> str:
    """
    Profit and loss breakdown for a wallet: open positions + closed positions.
    Uses Data API GET /positions and GET /closed-positions.

    Returns:
        summary (str): Open PnL, realised PnL, win rate, top winners/losers.
    """
    open_pos   = _get(f"{DATA}/positions",
                      params={"user": wallet_address, "limit": 500, "sortBy": "CASHPNL"}) or []
    closed_pos = _get(f"{DATA}/closed-positions",
                      params={"user": wallet_address, "limit": 50, "sortBy": "REALIZEDPNL"}) or []

    open_pnl     = sum(float(p.get("cashPnl", 0)) for p in open_pos)
    realised_pnl = sum(float(p.get("realizedPnl", 0)) for p in closed_pos)
    total_pnl    = open_pnl + realised_pnl

    wins  = [p for p in closed_pos if float(p.get("realizedPnl", 0)) > 0]
    losses = [p for p in closed_pos if float(p.get("realizedPnl", 0)) < 0]
    win_rate = len(wins) / max(len(closed_pos), 1) * 100

    lines = [
        f"Wallet PnL — {wallet_address}",
        _divider(),
        f"Open positions:    {len(open_pos)}",
        f"Open PnL:          ${open_pnl:+.2f}",
        f"Closed positions:  {len(closed_pos)}",
        f"Realised PnL:      ${realised_pnl:+.2f}",
        f"Total PnL:         ${total_pnl:+.2f}",
        _divider("·"),
        f"Win rate (closed): {win_rate:.1f}%  ({len(wins)} wins / {len(losses)} losses)",
    ]

    if closed_pos:
        lines.append("Top 5 closed positions by realised PnL:")
        for p in sorted(closed_pos, key=lambda p: float(p.get("realizedPnl", 0)), reverse=True)[:5]:
            lines.append(
                f"  {p.get('title', p.get('conditionId','?'))[:50]}  "
                f"outcome: {p.get('outcome')}  "
                f"realizedPnl: ${float(p.get('realizedPnl',0)):+.2f}  "
                f"avgPrice: {p.get('avgPrice')}"
            )

    if open_pos:
        lines.append("Top 5 open positions by cash PnL:")
        for p in sorted(open_pos, key=lambda p: float(p.get("cashPnl", 0)), reverse=True)[:5]:
            lines.append(
                f"  {p.get('title', p.get('conditionId','?'))[:50]}  "
                f"outcome: {p.get('outcome')}  size: {p.get('size')}  "
                f"cashPnl: ${float(p.get('cashPnl',0)):+.2f}"
            )

    return "\n".join(lines)


def score_trade_timing(
    wallet_address: str,
    condition_id: str,
) -> str:
    """
    Computes a timing score (0–1) for each pre-endDate trade placed by a wallet,
    and an overall score averaged across all trades.

    The reference timestamp is derived automatically from the market's endDate.
    To use a custom reference timestamp, use score_trade_timing_at().

    Scoring method:
      - Recency component (70% weight): based on hours before the reference time.
          < 0.5h : 0.0
          0.5–24h: 0.9
          24–72h : 0.7
          72–168h: 0.4
          > 168h : 0.15
      - Size component (30% weight): trade size normalised to a 5,000-share ceiling.

    Overall score = mean of individual trade scores.
    Score range: 0.0 to 1.0. No interpretation is applied.

    Returns:
        summary (str): Reference time, per-trade scores, overall score.
    """
    event_timestamp = _market_end_timestamp(condition_id)
    return score_trade_timing_at(wallet_address, condition_id, event_timestamp)


def score_trade_timing_at(
    wallet_address: str,
    condition_id: str,
    event_timestamp: float,
) -> str:
    """
    Computes a timing score relative to a specific reference timestamp.
    Use when probing a moment other than market close (e.g. a news event).

    Args:
        wallet_address:  Wallet to analyse.
        condition_id:    Market conditionId.
        event_timestamp: Unix timestamp of the reference moment.

    Returns:
        summary (str): Reference time, per-trade scores, overall score.
    """
    # Let get_wallet_trade_history handle proxy resolution — don't double-resolve.
    _, wallet_trades = get_wallet_trade_history(wallet_address, condition_id=condition_id)
    if not wallet_trades:
        return (
            f"No trades by {wallet_address}\n"
            f"on market {condition_id}"
        )

    pre_trades = [t for t in wallet_trades if (t.get("timestamp") or 0) <= event_timestamp]
    if not pre_trades:
        return f"Wallet {wallet_address} placed no trades before {_ts(event_timestamp)} on market {condition_id}"

    scored = []
    for t in pre_trades:
        ts   = t.get("timestamp", 0)
        hours_before = (event_timestamp - ts) / 3600
        if hours_before < 0.5:
            recency = 0.0
        elif hours_before <= 24:
            recency = 0.9
        elif hours_before <= 72:
            recency = 0.7
        elif hours_before <= 168:
            recency = 0.4
        else:
            recency = 0.15

        size = float(t.get("size", 0))
        size_score = min(size / 5000, 1.0)

        score = round((recency * 0.7 + size_score * 0.3), 3)
        scored.append((t, score, hours_before))

    overall = sum(s for _, s, _ in scored) / len(scored)

    lines = [
        f"Trade Timing Score — wallet: {wallet_address}",
        f"conditionId:        {condition_id}",
        f"Reference time:     {_ts(event_timestamp)}",
        _divider(),
        f"Pre-event trades:   {len(scored)}",
        f"Overall score:      {overall:.3f}  (0.0 = lowest, 1.0 = maximum recency + size)",
        _divider("·"),
        "Individual trade scores (sorted by score descending):",
    ]
    for t, score, hrs in sorted(scored, key=lambda x: x[1], reverse=True):
        ts_str = _ts(t["timestamp"]) if t.get("timestamp") else "?"
        lines.append(
            f"  score={score:.3f}  [{ts_str}]  {t.get('side'):4s}  "
            f"size={float(t.get('size',0)):.2f}  "
            f"{hrs:.1f}h before reference time"
        )

    return "\n".join(lines)


def get_wallet_activity(
    wallet_address: str,
    limit: int = 200,
) -> Tuple[str, List]:
    """
    On-chain activity for a wallet: trades, splits, merges, redeems, rewards.
    Uses GET /activity?user= on the Data API.

    Returns:
        summary (str): Activity type breakdown and recent events.
        raw (list):    Full activity objects.
    """
    data = _get(f"{DATA}/activity",
                params={"user": wallet_address, "limit": limit}) or []

    if not data:
        return f"No activity found for wallet: {wallet_address}", []

    type_counts: Dict[str, int] = defaultdict(int)
    for a in data:
        type_counts[a.get("type", "UNKNOWN")] += 1

    times = sorted(a.get("timestamp", 0) for a in data if a.get("timestamp"))

    lines = [
        f"Wallet Activity — {wallet_address}",
        f"Fetched: {len(data)} events",
        f"Period: {_ts(times[0])}  →  {_ts(times[-1])}" if len(times) >= 2 else "",
        _divider(),
        "Activity breakdown:",
    ]
    for atype, count in sorted(type_counts.items(), key=lambda x: x[1], reverse=True):
        lines.append(f"  {atype:<20} {count}")

    lines += [_divider("·"), "Last 5 activity events:"]
    for a in sorted(data, key=lambda x: x.get("timestamp", 0), reverse=True)[:5]:
        ts = _ts(a["timestamp"]) if a.get("timestamp") else "?"
        lines.append(
            f"  [{ts}]  {a.get('type'):15s}  "
            f"size: {a.get('size')}  cash: {a.get('usdcSize')}  "
            f"{str(a.get('title',''))[:40]}"
        )

    return "\n".join(lines), data


# ══════════════════════════════════════════════════════════════════
# ⑥ MARKET OPEN INTEREST & LIVE VOLUME
# ══════════════════════════════════════════════════════════════════

def get_market_open_interest(condition_id: str) -> str:
    """
    Current open interest for a market.
    Uses GET /oi?market= on the Data API.

    Returns:
        summary (str): Open interest value.
    """
    data = _get(f"{DATA}/oi", params={"market": condition_id})
    if not data:
        raise Exception(f"No open interest data for: {condition_id}")

    lines = [f"Open Interest — conditionId: {condition_id}", _divider()]
    for item in data:
        lines.append(f"  Market: {item.get('market')}   OI: ${item.get('value')}")
    return "\n".join(lines)


def get_live_event_volume(event_id: int) -> str:
    """
    Live trading volume for an event (all its markets combined).
    Uses GET /live-volume?id= on the Data API.

    Useful for tracking volume surges in real time around sensitive events.

    Returns:
        summary (str): Total event volume + per-market breakdown.
    """
    data = _get(f"{DATA}/live-volume", params={"id": event_id})
    if not data:
        raise Exception(f"No live volume data for event_id: {event_id}")

    item = data[0] if data else {}
    total = item.get("total", 0)
    markets = item.get("markets") or []

    lines = [
        f"Live Volume — event_id: {event_id}",
        f"Total volume: ${total}",
        _divider(),
        "Per-market breakdown:",
    ]
    for m in markets:
        lines.append(f"  conditionId: {m.get('market')}   volume: ${m.get('value')}")
    return "\n".join(lines)


# ══════════════════════════════════════════════════════════════════
# ⑦ QUERYING & FILTERING UTILITIES
#
# Pure data manipulation — no API calls.
# Operate on the `raw` second return value from any function that
# returns (summary, raw). Fetch once, query freely.
#
# Trade object key fields (from Data API):
#   proxyWallet, side, size, price, timestamp, conditionId,
#   outcome, outcomeIndex, usdcSize, transactionHash, title
#
# Cluster object key fields (from find_synchronized_traders):
#   direction, wallets[], trades[], total_size, avg_price,
#   start_ts, end_ts, time_span
# ══════════════════════════════════════════════════════════════════

def filter_trades(
    trades: List[Dict],
    wallet: Optional[str] = None,
    side: Optional[str] = None,
    min_size: Optional[float] = None,
    max_size: Optional[float] = None,
    start_ts: Optional[float] = None,
    end_ts: Optional[float] = None,
    outcome: Optional[str] = None,
    min_price: Optional[float] = None,
    max_price: Optional[float] = None,
) -> Tuple[str, List[Dict]]:
    """
    Filter a trade list by any combination of fields.
    Accepts the raw list from get_market_trades, get_wallet_trade_history,
    get_pre_event_trades, get_large_trades, etc.

    All parameters are optional and combinable.

    Args:
        trades:    Raw trade list to filter.
        wallet:    Exact proxyWallet address match.
        side:      "BUY" or "SELL".
        min_size:  Minimum trade size in shares (inclusive).
        max_size:  Maximum trade size in shares (inclusive).
        start_ts:  Earliest timestamp (Unix, inclusive).
        end_ts:    Latest timestamp (Unix, inclusive).
        outcome:   Outcome label match (e.g. "Yes", "No").
        min_price: Minimum price (inclusive).
        max_price: Maximum price (inclusive).

    Returns:
        summary (str): Filter parameters applied and result count.
        raw (list):    Filtered trades sorted by timestamp ascending.
    """
    result = trades

    if wallet is not None:
        result = [t for t in result if t.get("proxyWallet") == wallet]
    if side is not None:
        result = [t for t in result if t.get("side") == side.upper()]
    if min_size is not None:
        result = [t for t in result if float(t.get("size", 0)) >= min_size]
    if max_size is not None:
        result = [t for t in result if float(t.get("size", 0)) <= max_size]
    if start_ts is not None:
        result = [t for t in result if (t.get("timestamp") or 0) >= start_ts]
    if end_ts is not None:
        result = [t for t in result if (t.get("timestamp") or 0) <= end_ts]
    if outcome is not None:
        result = [t for t in result if t.get("outcome") == outcome]
    if min_price is not None:
        result = [t for t in result if float(t.get("price") or 0) >= min_price]
    if max_price is not None:
        result = [t for t in result if float(t.get("price") or 0) <= max_price]

    result = sorted(result, key=lambda t: t.get("timestamp") or 0)

    applied = []
    if wallet    is not None: applied.append(f"wallet={wallet}")
    if side      is not None: applied.append(f"side={side.upper()}")
    if min_size  is not None: applied.append(f"min_size={min_size}")
    if max_size  is not None: applied.append(f"max_size={max_size}")
    if start_ts  is not None: applied.append(f"start={_ts(start_ts)}")
    if end_ts    is not None: applied.append(f"end={_ts(end_ts)}")
    if outcome   is not None: applied.append(f"outcome={outcome}")
    if min_price is not None: applied.append(f"min_price={min_price}")
    if max_price is not None: applied.append(f"max_price={max_price}")

    buys  = sum(1 for t in result if t.get("side") == "BUY")
    sells = sum(1 for t in result if t.get("side") == "SELL")
    total_size = sum(float(t.get("size", 0)) for t in result)

    summary = (
        f"filter_trades  [{len(result)} of {len(trades)} trades match]\n"
        f"Filters: {', '.join(applied) if applied else 'none'}\n"
        f"BUY: {buys}   SELL: {sells}   Total size: {total_size:.2f} shares"
    )
    return summary, result


def sort_trades(
    trades: List[Dict],
    by: str = "timestamp",
    ascending: bool = True,
) -> List[Dict]:
    """
    Sort a trade list by any field.

    Common values for `by`: "timestamp", "size", "price", "usdcSize".

    Returns:
        Sorted trade list (no summary — use summarize_trades if needed).
    """
    reverse = not ascending
    try:
        return sorted(trades, key=lambda t: float(t.get(by) or 0), reverse=reverse)
    except (TypeError, ValueError):
        return sorted(trades, key=lambda t: str(t.get(by) or ""), reverse=reverse)


def summarize_trades(trades: List[Dict], label: str = "") -> str:
    """
    Print a quick statistical summary of any trade list.
    Works on the raw output of any trade-returning function.

    Args:
        trades: Any list of trade dicts.
        label:  Optional label shown in the header.

    Returns:
        summary (str): Count, sides, size stats, wallet count, time span.
    """
    if not trades:
        return f"summarize_trades: empty list{f'  ({label})' if label else ''}"

    timed   = [t for t in trades if t.get("timestamp")]
    buys    = [t for t in trades if t.get("side") == "BUY"]
    sells   = [t for t in trades if t.get("side") == "SELL"]
    sizes   = [float(t.get("size", 0)) for t in trades]
    prices  = [float(t.get("price") or 0) for t in trades if t.get("price")]
    wallets = {t.get("proxyWallet") for t in trades if t.get("proxyWallet")}
    usdc    = sum(float(t.get("usdcSize", 0)) for t in trades)

    lines = [
        f"Trade Summary{f'  —  {label}' if label else ''}",
        _divider(),
        f"Total trades:    {len(trades)}",
        f"BUY:             {len(buys)}   SELL: {len(sells)}",
        f"Buy/Sell ratio:  {len(buys) / max(len(sells), 1):.2f}",
        f"Unique wallets:  {len(wallets)}",
        _divider("·"),
        f"Size — total:    {sum(sizes):.2f} shares",
        f"Size — avg:      {sum(sizes) / max(len(sizes), 1):.2f}",
        f"Size — min:      {min(sizes):.2f}",
        f"Size — max:      {max(sizes):.2f}",
        f"USDC volume:     ${usdc:.2f}",
    ]
    if prices:
        lines += [
            _divider("·"),
            f"Price — avg:     {sum(prices) / len(prices):.4f}",
            f"Price — min:     {min(prices):.4f}",
            f"Price — max:     {max(prices):.4f}",
        ]
    if timed:
        ts_sorted = sorted(t["timestamp"] for t in timed)
        lines += [
            _divider("·"),
            f"Time span:       {_ts(ts_sorted[0])}  →  {_ts(ts_sorted[-1])}",
        ]
    return "\n".join(lines)


def group_trades_by_wallet(trades: List[Dict]) -> Tuple[str, Dict[str, List[Dict]]]:
    """
    Group a trade list by proxyWallet address.

    Returns:
        summary (str): Wallet count and top wallets by total size.
        raw (dict):    { proxyWallet: [trade, ...] } sorted by total size descending.
    """
    grouped: Dict[str, List] = defaultdict(list)
    for t in trades:
        grouped[t.get("proxyWallet", "unknown")].append(t)

    # Sort by total size descending
    sorted_grouped = dict(
        sorted(grouped.items(),
               key=lambda kv: sum(float(t.get("size", 0)) for t in kv[1]),
               reverse=True)
    )

    lines = [
        f"Trades grouped by wallet  [{len(sorted_grouped)} wallets, {len(trades)} trades]",
        _divider(),
    ]
    for wallet, wt in list(sorted_grouped.items())[:15]:
        total   = sum(float(t.get("size", 0)) for t in wt)
        buys    = sum(1 for t in wt if t.get("side") == "BUY")
        sells   = sum(1 for t in wt if t.get("side") == "SELL")
        usdc    = sum(float(t.get("usdcSize", 0)) for t in wt)
        lines.append(
            f"  {wallet}\n"
            f"    trades: {len(wt)}   size: {total:.2f}   "
            f"BUY: {buys}  SELL: {sells}   USDC: ${usdc:.2f}"
        )

    return "\n".join(lines), sorted_grouped


def cross_reference_wallets(
    trades_a: List[Dict],
    trades_b: List[Dict],
    label_a: str = "A",
    label_b: str = "B",
) -> Tuple[str, List[str]]:
    """
    Find wallets that appear in both trade lists.
    Useful for identifying wallets that traded on two different markets,
    or in two different time windows.

    Args:
        trades_a: First trade list (raw output from any trade function).
        trades_b: Second trade list.
        label_a:  Human label for the first list (shown in summary).
        label_b:  Human label for the second list.

    Returns:
        summary (str): Overlap count and per-wallet details in both lists.
        raw (list):    List of proxyWallet addresses present in both lists.
    """
    wallets_a = {t.get("proxyWallet") for t in trades_a if t.get("proxyWallet")}
    wallets_b = {t.get("proxyWallet") for t in trades_b if t.get("proxyWallet")}
    overlap   = sorted(wallets_a & wallets_b)

    lines = [
        f"Wallet Cross-Reference  [{label_a}] ∩ [{label_b}]",
        f"Wallets in {label_a}: {len(wallets_a)}   "
        f"Wallets in {label_b}: {len(wallets_b)}   "
        f"Overlap: {len(overlap)}",
        _divider(),
    ]

    if not overlap:
        lines.append("No wallets in common.")
        return "\n".join(lines), []

    # For each overlapping wallet, show their activity in both lists
    grouped_a: Dict[str, List] = defaultdict(list)
    grouped_b: Dict[str, List] = defaultdict(list)
    for t in trades_a:
        if t.get("proxyWallet") in overlap:
            grouped_a[t["proxyWallet"]].append(t)
    for t in trades_b:
        if t.get("proxyWallet") in overlap:
            grouped_b[t["proxyWallet"]].append(t)

    for w in overlap:
        a_trades = grouped_a[w]
        b_trades = grouped_b[w]
        a_size   = sum(float(t.get("size", 0)) for t in a_trades)
        b_size   = sum(float(t.get("size", 0)) for t in b_trades)
        lines.append(
            f"  {w}\n"
            f"    [{label_a}]: {len(a_trades)} trades   {a_size:.2f} shares\n"
            f"    [{label_b}]: {len(b_trades)} trades   {b_size:.2f} shares"
        )

    return "\n".join(lines), overlap


def filter_clusters(
    clusters: List[Dict],
    min_wallets: Optional[int] = None,
    min_total_size: Optional[float] = None,
    direction: Optional[str] = None,
    max_time_span_seconds: Optional[int] = None,
) -> Tuple[str, List[Dict]]:
    """
    Filter the cluster list from find_synchronized_traders.

    Args:
        clusters:               Raw cluster list from find_synchronized_traders.
        min_wallets:            Minimum distinct wallets in cluster.
        min_total_size:         Minimum total shares traded in cluster.
        direction:              "BUY" or "SELL".
        max_time_span_seconds:  Maximum time span of the cluster in seconds.

    Returns:
        summary (str): Filters applied and matching cluster count.
        raw (list):    Filtered cluster list.
    """
    result = clusters

    if direction is not None:
        result = [c for c in result if c.get("direction") == direction.upper()]
    if min_wallets is not None:
        result = [c for c in result if len(c.get("wallets") or []) >= min_wallets]
    if min_total_size is not None:
        result = [c for c in result if c.get("total_size", 0) >= min_total_size]
    if max_time_span_seconds is not None:
        result = [c for c in result if c.get("time_span", float("inf")) <= max_time_span_seconds]

    applied = []
    if direction              is not None: applied.append(f"direction={direction.upper()}")
    if min_wallets            is not None: applied.append(f"min_wallets={min_wallets}")
    if min_total_size         is not None: applied.append(f"min_total_size={min_total_size}")
    if max_time_span_seconds  is not None: applied.append(f"max_span={max_time_span_seconds}s")

    summary = (
        f"filter_clusters  [{len(result)} of {len(clusters)} clusters match]\n"
        f"Filters: {', '.join(applied) if applied else 'none'}"
    )
    return summary, result


def trades_timeline(trades: List[Dict], max_entries: int = 50) -> str:
    """
    Format a trade list as a human-readable chronological timeline.
    Useful for auditing a specific set of trades after filtering.

    Args:
        trades:      Any list of trade dicts.
        max_entries: Max lines to show (most recent if truncated).

    Returns:
        summary (str): Chronological trade log.
    """
    if not trades:
        return "trades_timeline: no trades to display."

    sorted_trades = sorted(trades, key=lambda t: t.get("timestamp") or 0)
    total = len(sorted_trades)
    display = sorted_trades[-max_entries:] if total > max_entries else sorted_trades

    lines = [
        f"Trade Timeline  [{total} trades"
        + (f", showing last {max_entries}" if total > max_entries else "")
        + "]",
        _divider(),
    ]
    for t in display:
        ts      = _ts(t["timestamp"]) if t.get("timestamp") else "?"
        wallet  = (t.get("proxyWallet") or "?")
        side    = t.get("side", "?")
        size    = float(t.get("size", 0))
        price   = t.get("price", "?")
        outcome = t.get("outcome", "?")
        tx      = t.get("transactionHash", "")
        tx_str  = f"  tx: {tx}" if tx else ""
        lines.append(
            f"  [{ts}]  {side:4s}  {size:>10.2f} shares"
            f"  @ {price}  outcome: {outcome}"
            f"  {wallet}{tx_str}"
        )

    return "\n".join(lines)


def filter_events(
    events: List[Dict],
    active: Optional[bool] = None,
    closed: Optional[bool] = None,
    min_volume: Optional[float] = None,
    max_volume: Optional[float] = None,
    min_liquidity: Optional[float] = None,
    tag_slug: Optional[str] = None,
) -> Tuple[str, List[Dict]]:
    """
    Filter an event list from search_events or get_related_events.

    Args:
        events:        Raw event list (second return value from search/related functions).
        active:        If True, only active events. If False, only inactive.
        closed:        If True, only closed events. If False, only open.
        min_volume:    Minimum all-time volume.
        max_volume:    Maximum all-time volume.
        min_liquidity: Minimum liquidity.
        tag_slug:      Only events containing this tag slug.

    Returns:
        summary (str): Filters applied and count.
        raw (list):    Filtered event list.
    """
    result = events

    if active is not None:
        result = [e for e in result if bool(e.get("active")) == active]
    if closed is not None:
        result = [e for e in result if bool(e.get("closed")) == closed]
    if min_volume is not None:
        result = [e for e in result if float(e.get("volume") or 0) >= min_volume]
    if max_volume is not None:
        result = [e for e in result if float(e.get("volume") or 0) <= max_volume]
    if min_liquidity is not None:
        result = [e for e in result if float(e.get("liquidity") or 0) >= min_liquidity]
    if tag_slug is not None:
        result = [
            e for e in result
            if any(t.get("slug") == tag_slug for t in (e.get("tags") or []))
        ]

    applied = []
    if active        is not None: applied.append(f"active={active}")
    if closed        is not None: applied.append(f"closed={closed}")
    if min_volume    is not None: applied.append(f"min_volume={min_volume}")
    if max_volume    is not None: applied.append(f"max_volume={max_volume}")
    if min_liquidity is not None: applied.append(f"min_liquidity={min_liquidity}")
    if tag_slug      is not None: applied.append(f"tag_slug={tag_slug}")

    summary = (
        f"filter_events  [{len(result)} of {len(events)} events match]\n"
        f"Filters: {', '.join(applied) if applied else 'none'}"
    )
    return summary, result


# ══════════════════════════════════════════════════════════════════
# Example usage
# ══════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    # ════════════════════════════════════════════════════════════
    # Test market: "US x Iran ceasefire by May 31?"
    # ════════════════════════════════════════════════════════════
    EVENT_SLUG    = "us-x-iran-ceasefire-by"
    CONDITION_ID  = "0xa9937410f8aae98cc6440a7480ad832be5a1a998afcf5a6e77c6f5aa4c0f259f"
    QUESTION_ID   = "0xfd7de881ca0c74f243f457cc39c2a60346dcb36a106b8c6b0f5c682e2384ee32"
    CLOB_YES      = "97390751868769233430161550786035197721004217118584051662030655361575807718008"
    CLOB_NO       = "35501529638864997295617415678543053873295823444029641313951781455412631628785"

    WALLETS = [
        "0xb6fed20afe3cdeb9c4a963ad2eee3c5d499ce514",
        "0x79463f0b7e76ca148250055da304c4e25b8c387f",
        "0x0a793254e040027c5d1ca0c2f87cda8e22228e05",
        "0x95c8499569dac8faea4f9a21c553184b4202f511",
        "0x682c92615993fd1f75cdfe101efdc1a8adcb17ae",
    ]

    # ── Step 1: Event overview ───────────────────────────────────
    #print(get_event_info(EVENT_SLUG))

    # ── Step 2: Full market detail by questionId ─────────────────
    # summary, raw = get_market_by_question_id(QUESTION_ID)
    # print(summary)

    # ── Step 3: Price history — YES token ────────────────────────
    # summary, raw = get_market_price_history(CLOB_YES, interval="1w")
    # print(summary)

    # ── Step 4: Price history — NO token ─────────────────────────
    # summary, raw = get_market_price_history(CLOB_NO, interval="1w")
    # print(summary)

    # ── Step 5: Opening price run-up (first 24h vs next 72h) ─────
    # print(compute_price_run_up(CONDITION_ID, outcome_index=0, opening_hours=24, baseline_hours=72))

    # ── Step 6: Opening volume vs baseline ───────────────────────
    # print(compute_abnormal_volume(CONDITION_ID, opening_hours=8, baseline_hours=72))

    # ── Step 7: Trades in the opening 24h ────────────────────────
    # summary, raw = get_pre_event_trades(CONDITION_ID, opening_hours=24)
    # print(summary)

    # ── Step 7b: Trades before a specific timestamp (backward) ───
    # import time
    # summary, raw = get_pre_event_trades_at(CONDITION_ID, event_timestamp=time.time(), lookback_hours=48)
    # print(summary)

    # ── Step 8: Live order book (YES side) ───────────────────────
    # summary, raw = get_market_orderbook(CLOB_YES)
    # print(summary)

    # ── Step 9: Market movers (top position holders) ─────────────
    # summary, raw = get_market_movers(CONDITION_ID)
    # print(summary)

    # ── Step 10: Top token holders ───────────────────────────────
    # summary, raw = get_market_top_holders(CONDITION_ID)
    # print(summary)

    # ── Step 11: Synchronized traders ────────────────────────────
    #summary, raw = find_synchronized_traders(CONDITION_ID, time_window_seconds=300)
    #print(summary)

    # ── Step 12: All market trades ────────────────────────────────
    # summary, raw = get_market_trades(CONDITION_ID, limit=500)
    # print(summary)

    # ── Step 13: Large trades only (≥ 5,000 shares) ───────────────
    # summary, raw = get_large_trades(CONDITION_ID, min_size=5000)
    # print(summary)

    print(get_wallet_profile(WALLETS[0]))
    # ── Step 14: Wallet profiles ──────────────────────────────────
    #for wallet in WALLETS:
         #print(get_wallet_profile(wallet))
         #print()

    # ── Step 15: Wallet trade history (on this market) ───────────
    #summary, raw = get_wallet_trade_history(WALLETS[0], condition_id=CONDITION_ID)
    #print(summary)

    # ── Step 16: Wallet PnL ───────────────────────────────────────
    # print(get_wallet_pnl(WALLETS[0]))

    # ── Step 17: Timing score (vs market startDate) ───────────────
    # print(score_trade_timing(WALLETS[0], CONDITION_ID))

    # ── Step 17b: Timing score vs a specific moment ───────────────
    # import time
    # print(score_trade_timing_at(WALLETS[0], CONDITION_ID, event_timestamp=time.time()))

    # ── Step 18: Wallet on-chain activity ────────────────────────
    # summary, raw = get_wallet_activity(WALLETS[0])
    # print(summary)

    # ── Step 19: Open interest ────────────────────────────────────
    # print(get_market_open_interest(CONDITION_ID))

    # ── Step 20: Price history for a custom date range ───────────
    # import time
    # summary, raw = get_market_price_history_range(
    #     CONDITION_ID,
    #     start_ts=time.time() - 7 * 24 * 3600,  # 7 days ago
    #     end_ts=time.time(),
    #     outcome_index=0,
    # )
    # print(summary)