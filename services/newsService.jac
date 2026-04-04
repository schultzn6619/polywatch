"""News service — wraps webz.io API for the PolyWatch frontend and LLM consumption."""

import:py from python_api.news { search_news_lite, search_news, fetch_next_page }


def _format_articles(result: dict) -> str {
    """Format a news API response dict into a readable string for LLM consumption."""
    if "error" in result {
        return "Error: " + str(result["error"]);
    }

    total = result.get("totalResults", 0);
    articles = result.get("articles", []);
    remaining = result.get("moreResultsAvailable", 0);

    if not articles {
        return "No articles found.";
    }

    output = "Found " + str(total) + " total results. Showing " + str(len(articles)) + " articles:\n\n";

    for i, a in enumerate(articles) {
        output += "--- Article " + str(i + 1) + " ---\n";
        output += "Title: " + str(a.get("title", "N/A")) + "\n";
        output += "Source: " + str(a.get("site", "N/A")) + "\n";
        output += "Published: " + str(a.get("published", "N/A")) + "\n";
        output += "Author: " + str(a.get("author", "N/A")) + "\n";
        output += "Sentiment: " + str(a.get("sentiment", "N/A")) + "\n";
        output += "Language: " + str(a.get("language", "N/A")) + "\n";
        output += "Country: " + str(a.get("country", "N/A")) + "\n";
        output += "Domain Rank: " + str(a.get("domain_rank", "N/A")) + "\n";
        if a.get("categories") {
            output += "Categories: " + str(a.get("categories")) + "\n";
        }
        if a.get("text") {
            output += "Snippet: " + str(a.get("text", ""))[:500] + "\n";
        }
        output += "\n";
    }

    if remaining > 0 {
        output += str(remaining) + " more results available.\n";
    }

    return output;
}


def:priv search_news_lite(query: str, ts: int = 0) -> str {
    """Search news using the free Lite API (max 10 results).
    Returns a formatted string suitable for LLM consumption."""
    result = search_news_lite(query, ts if ts else None);
    return _format_articles(result);
}

def:priv search_news_full(
    query: str,
    size: int = 20,
    sort: str = "relevancy",
    order: str = "desc",
    ts: int = 0,
    highlight: bool = False
) -> str {
    """Search news using the full API with all filters and sorting.
    Returns a formatted string suitable for LLM consumption."""
    result = search_news(query, size, sort, order, ts if ts else None, highlight);
    return _format_articles(result);
}

def:priv get_next_page(next_url: str) -> str {
    """Paginate to the next page of news results.
    Returns a formatted string suitable for LLM consumption."""
    result = fetch_next_page(next_url);
    return _format_articles(result);
}
