"""News service — wraps webz.io API for the PolyWatch frontend."""

import:py from python_api.news { search_news_lite, search_news, fetch_next_page }

def:priv search_news_lite(query: str, ts: int = 0) -> dict {
    """Search news using the free Lite API (max 10 results, snippets only)."""
    result = search_news_lite(query, ts if ts else None);
    return result;
}

def:priv search_news_full(
    query: str,
    size: int = 20,
    sort: str = "relevancy",
    order: str = "desc",
    ts: int = 0,
    highlight: bool = False
) -> dict {
    """Search news using the full API with all filters and sorting."""
    result = search_news(query, size, sort, order, ts if ts else None, highlight);
    return result;
}

def:priv get_next_page(next_url: str) -> dict {
    """Paginate to the next page of news results."""
    result = fetch_next_page(next_url);
    return result;
}
