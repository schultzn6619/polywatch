"""Polymarket service — wraps API toolkit for the PolyWatch frontend."""

import from services.polymarketApi {
    search_events,
    search_events_structured,
    get_event_info,
    get_related_events,
    get_market_by_question_id,
    get_market_orderbook,
    get_market_price_history,
    get_market_price_history_range,
    get_market_trades,
    get_large_trades,
    get_pre_event_trades,
    get_pre_event_trades_at,
    compute_price_run_up,
    compute_abnormal_volume,
    find_synchronized_traders,
    get_market_movers,
    get_market_top_holders,
    get_wallet_profile,
    get_wallet_trade_history,
    get_wallet_pnl,
    score_trade_timing,
    get_wallet_activity,
    get_market_open_interest,
    get_live_event_volume
}


# Search Polymarket events — structured data for frontend cards
def:priv search_polymarket(query: str) -> dict {
    results = search_events_structured(query);
    return {"events": results};
}

# Search Polymarket events by keyword (text summary)
def:priv search_polymarket_events(query: str) -> dict {
    (raw, _) = search_events(query);
    return {"results": raw};
}

# Get full event info by slug
def:priv get_polymarket_event(slug: str) -> dict {
    raw = get_event_info(slug);
    return {"event_info": raw};
}
