"""Investigation tools — functions the investigator LLM can call as edges in the tree.

News tools are live (webz.io). Polymarket tools are placeholders.
Each tool takes artifact data and returns a new artifact dict with:
  - data: the raw output
  - summary: explanation of what the data is
  - data_visible_to_ai: whether raw data should be passed to LLM
"""

import from services.newsApi { search_news_lite }
import from services.polymarketApi { get_event_info }


# ============================================================
# NEWS TOOLS (LIVE)
# ============================================================

# Search recent news articles related to an investigation query
def tool_search_news(query: str, artifact_context: str = "") -> dict {
    result = search_news_lite(query);
    articles = result.get("articles", []);

    if not articles {
        return {
            "data": "No articles found for: " + query,
            "summary": "News search for '" + query + "' returned no results.",
            "data_visible_to_ai": True
        };
    }

    formatted = "";
    for a in articles {
        formatted += "Title: " + str(a.get("title", "")) + "\n";
        formatted += "Source: " + str(a.get("site", "")) + "\n";
        formatted += "Published: " + str(a.get("published", "")) + "\n";
        formatted += "Author: " + str(a.get("author", "")) + "\n";
        formatted += "Sentiment: " + str(a.get("sentiment", "")) + "\n";
        formatted += "Country: " + str(a.get("country", "")) + "\n";
        formatted += "\n";
    }

    return {
        "data": formatted,
        "summary": "News search for '" + query + "' returned " + str(len(articles)) + " articles. Contains titles, sources, publication dates, authors, sentiment, and country of origin.",
        "data_visible_to_ai": True
    };
}

# Search news filtered by sentiment (positive, negative, neutral)
def tool_search_news_sentiment(query: str, sentiment: str = "negative") -> dict {
    full_query = query + " sentiment:" + sentiment;
    result = search_news_lite(full_query);
    articles = result.get("articles", []);

    formatted = "";
    for a in articles {
        formatted += "Title: " + str(a.get("title", "")) + "\n";
        formatted += "Source: " + str(a.get("site", "")) + "\n";
        formatted += "Published: " + str(a.get("published", "")) + "\n";
        formatted += "Sentiment: " + str(a.get("sentiment", "")) + "\n\n";
    }

    return {
        "data": formatted,
        "summary": "News search for '" + query + "' filtered to " + sentiment + " sentiment. Found " + str(len(articles)) + " articles.",
        "data_visible_to_ai": True
    };
}

# Search news and organize by publication date to build a timeline of events
def tool_search_news_timeline(query: str) -> dict {
    result = search_news_lite("title:(" + query + ") language:english");
    articles = result.get("articles", []);

    sorted_articles = sorted(articles, key=lambda a: str(a.get("published", "")));

    formatted = "Timeline for '" + query + "':\n\n";
    for a in sorted_articles {
        formatted += str(a.get("published", ""))[:10] + " | " + str(a.get("title", "")) + " | " + str(a.get("site", "")) + "\n";
    }

    return {
        "data": formatted,
        "summary": "Chronological timeline of " + str(len(articles)) + " news articles about '" + query + "'. Sorted by publication date. Useful for determining when news broke relative to trading activity.",
        "data_visible_to_ai": True
    };
}


# ============================================================
# POLYMARKET TOOLS (LIVE - Gamma API)
# ============================================================

# Fetch Polymarket event data including markets, liquidity, and volume
def tool_get_event_data(slug: str) -> dict {
    try {
        event_str = get_event_info(slug);
    } except Exception as e {
        return {
            "data": "Error fetching event '" + slug + "': " + str(e),
            "summary": "Failed to fetch Polymarket event data for '" + slug + "'. The slug may be incorrect.",
            "data_visible_to_ai": True
        };
    }

    return {
        "data": event_str,
        "summary": "Polymarket event data for '" + slug + "'. Contains event description, liquidity, volume (24h/1wk/1mo/1yr), tags, and individual market outcomes with prices.",
        "data_visible_to_ai": True
    };
}


# ============================================================
# POLYMARKET TOOLS (PLACEHOLDERS — custom API being developed)
# ============================================================

# PLACEHOLDER: Get accounts that made the largest trades in a market
def tool_get_market_movers(market_id: str) -> dict {
    return {
        "data": "[PLACEHOLDER] Market movers data for market " + market_id + " not yet available.",
        "summary": "PLACEHOLDER: Would return the top accounts by trade volume for market '" + market_id + "'. Will include wallet addresses, trade sizes, buy/sell direction, and timestamps.",
        "data_visible_to_ai": True
    };
}

# PLACEHOLDER: Get full trading history for a specific wallet address
def tool_get_wallet_history(wallet_address: str) -> dict {
    return {
        "data": "[PLACEHOLDER] Wallet history for " + wallet_address + " not yet available.",
        "summary": "PLACEHOLDER: Would return full trade history for wallet '" + wallet_address + "'. Will include every trade with timestamps, amounts, markets, and realized PnL.",
        "data_visible_to_ai": False
    };
}

# PLACEHOLDER: Get trade distribution over time for a market
def tool_get_trade_timing(market_id: str, time_window: str = "24h") -> dict {
    return {
        "data": "[PLACEHOLDER] Trade timing for market " + market_id + " (" + time_window + ") not yet available.",
        "summary": "PLACEHOLDER: Would return trade volume bucketed by time intervals for market '" + market_id + "' over the last " + time_window + ". Useful for detecting pre-news trading spikes.",
        "data_visible_to_ai": True
    };
}

# PLACEHOLDER: Get wallets holding large positions in a market
def tool_get_large_positions(market_id: str, min_size: float = 1000.0) -> dict {
    return {
        "data": "[PLACEHOLDER] Large positions for market " + market_id + " (min $" + str(min_size) + ") not yet available.",
        "summary": "PLACEHOLDER: Would return wallets with positions >= $" + str(min_size) + " in market '" + market_id + "'. Will include position size, avg entry price, and when position was opened.",
        "data_visible_to_ai": False
    };
}

# PLACEHOLDER: Check if a wallet has traded in related markets
def tool_get_wallet_cross_market(wallet_address: str) -> dict {
    return {
        "data": "[PLACEHOLDER] Cross-market data for " + wallet_address + " not yet available.",
        "summary": "PLACEHOLDER: Would return all markets wallet '" + wallet_address + "' has traded in, with position sizes and timing. Useful for detecting if suspicious wallets trade across correlated events.",
        "data_visible_to_ai": False
    };
}

# Compare news publication timestamps against trade activity (news live, trades placeholder)
def tool_compare_news_vs_trades(market_id: str, query: str) -> dict {
    news_result = search_news_lite("title:(" + query + ") language:english");
    articles = news_result.get("articles", []);

    news_timeline = "News timeline:\n";
    for a in articles {
        news_timeline += str(a.get("published", ""))[:19] + " | " + str(a.get("title", "")) + "\n";
    }

    trade_timeline = "\nTrade timeline:\n[PLACEHOLDER] Trade data for market " + market_id + " not yet available.\n";

    combined = news_timeline + trade_timeline;

    return {
        "data": combined,
        "summary": "Comparison of news publication times vs trading activity for market '" + market_id + "' and query '" + query + "'. News data is live (" + str(len(articles)) + " articles). Trade data is placeholder.",
        "data_visible_to_ai": True
    };
}


# ============================================================
# TOOL REGISTRY — maps tool names to functions for the walker
# ============================================================

glob TOOL_REGISTRY: dict = {
    "search_news": tool_search_news,
    "search_news_sentiment": tool_search_news_sentiment,
    "search_news_timeline": tool_search_news_timeline,
    "get_event_data": tool_get_event_data,
    "get_market_movers": tool_get_market_movers,
    "get_wallet_history": tool_get_wallet_history,
    "get_trade_timing": tool_get_trade_timing,
    "get_large_positions": tool_get_large_positions,
    "get_wallet_cross_market": tool_get_wallet_cross_market,
    "compare_news_vs_trades": tool_compare_news_vs_trades
};

glob TOOL_DESCRIPTIONS: str = "Available investigation tools:\n\nLIVE TOOLS:\n- search_news(query: str) — Search recent news articles. Returns titles, sources, dates, sentiment.\n- search_news_sentiment(query: str, sentiment: str) — Search news filtered by sentiment (positive/negative/neutral).\n- search_news_timeline(query: str) — Build a chronological timeline of news articles about a topic.\n- get_event_data(slug: str) — Get Polymarket event data (markets, liquidity, volume, outcomes).\n\nPLACEHOLDER TOOLS (data not yet available, will return placeholder):\n- get_market_movers(market_id: str) — Get accounts with largest trades in a market.\n- get_wallet_history(wallet_address: str) — Get full trading history for a wallet.\n- get_trade_timing(market_id: str, time_window: str) — Get trade volume over time (detect spikes).\n- get_large_positions(market_id: str, min_size: float) — Get wallets with large positions.\n- get_wallet_cross_market(wallet_address: str) — Check if a wallet traded across related markets.\n- compare_news_vs_trades(market_id: str, query: str) — Compare news timestamps vs trade activity.\n";
