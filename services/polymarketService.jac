"""Polymarket service — wraps gamma API for the PolyWatch frontend."""

import from services.polymarketApi { search_events, get_event_info }


# Search Polymarket events by keyword
def:priv search_polymarket_events(query: str) -> dict {
    raw = search_events(query);
    return {"results": raw};
}

# Get full event info by slug
def:priv get_polymarket_event(slug: str) -> dict {
    raw = get_event_info(slug);
    return {"event_info": raw};
}
