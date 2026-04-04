"""Webz.io News API client for PolyWatch.

Supports both the free News API Lite and the full filterWebContent endpoint.
Docs: https://docs.webz.io/reference/1
"""

import os
import requests
from typing import Optional
from datetime import datetime, timedelta
from pathlib import Path


def _load_token() -> str:
    token = os.environ.get("WEBZ_TOKEN", "")
    if token:
        return token
    env_path = Path(__file__).resolve().parent.parent / ".env"
    if env_path.exists():
        for line in env_path.read_text().splitlines():
            if line.startswith("WEBZ_TOKEN="):
                return line.split("=", 1)[1].strip()
    return ""


WEBZ_TOKEN = _load_token()

BASE_URL_LITE = "https://api.webz.io/newsApiLite"
BASE_URL_FULL = "https://api.webz.io/filterWebContent"


def _make_request(url: str, params: dict) -> Optional[dict]:
    try:
        resp = requests.get(url, params=params, timeout=15)
        resp.raise_for_status()
        return resp.json()
    except requests.RequestException as e:
        print(f"Webz.io API error: {e}")
        return None


def search_news_lite(query: str, ts: Optional[int] = None) -> dict:
    """Search news using the free News API Lite (max 10 results, snippets only).

    Args:
        query: Search query with optional filters (e.g. 'Bitcoin', 'title:Trump sentiment:negative')
        ts: Unix timestamp — only return articles collected after this time (default: last 3 days)

    Returns:
        dict with keys: totalResults, moreResultsAvailable, articles (list), next (pagination url), requestsLeft
    """
    if not WEBZ_TOKEN:
        return {"error": "WEBZ_TOKEN not set. Export it as an environment variable."}

    params = {"token": WEBZ_TOKEN, "q": query}
    if ts:
        params["ts"] = ts

    data = _make_request(BASE_URL_LITE, params)
    if not data:
        return {"error": "Request failed"}

    articles = []
    for post in data.get("posts", []):
        thread = post.get("thread", {})
        articles.append({
            "title": thread.get("title", ""),
            "url": thread.get("url", ""),
            "site": thread.get("site_full", ""),
            "published": post.get("published", ""),
            "author": post.get("author", ""),
            "text": post.get("text", ""),
            "sentiment": post.get("sentiment", ""),
            "language": post.get("language", ""),
            "categories": post.get("categories", []),
            "domain_rank": thread.get("domain_rank", 0),
            "country": thread.get("country", ""),
        })

    return {
        "totalResults": data.get("totalResults", 0),
        "moreResultsAvailable": data.get("moreResultsAvailable", 0),
        "articles": articles,
        "next": data.get("next", ""),
        "requestsLeft": data.get("requestsLeft", -1),
    }


def search_news(
    query: str,
    size: int = 20,
    sort: str = "relevancy",
    order: str = "desc",
    ts: Optional[int] = None,
    highlight: bool = False,
) -> dict:
    """Search news using the full filterWebContent API.

    Args:
        query: Boolean query with filters (e.g. 'Bitcoin language:english site_type:news')
        size: Results per page (1-100, default 20)
        sort: Sort by relevancy|published|performance_score|domain_rank|social.facebook.likes
        order: asc or desc
        ts: Unix timestamp in ms — results crawled after this time
        highlight: If True, matching fragments are wrapped in <em> tags

    Returns:
        dict with keys: totalResults, moreResultsAvailable, articles (list), next, requestsLeft
    """
    if not WEBZ_TOKEN:
        return {"error": "WEBZ_TOKEN not set. Export it as an environment variable."}

    params = {
        "token": WEBZ_TOKEN,
        "q": query,
        "format": "json",
        "size": min(max(size, 1), 100),
        "sort": sort,
        "order": order,
    }
    if ts:
        params["ts"] = ts
    if highlight:
        params["highlight"] = "true"

    data = _make_request(BASE_URL_FULL, params)
    if not data:
        return {"error": "Request failed"}

    articles = []
    for post in data.get("posts", []):
        thread = post.get("thread", {})
        entities = post.get("entities", {})
        syndication = post.get("syndication", {})
        trust = thread.get("trust", {})

        articles.append({
            "title": thread.get("title", ""),
            "url": thread.get("url", ""),
            "site": thread.get("site_full", ""),
            "published": post.get("published", ""),
            "author": post.get("author", ""),
            "text": post.get("text", ""),
            "summary": post.get("summary", ""),
            "sentiment": post.get("sentiment", ""),
            "language": post.get("language", ""),
            "categories": post.get("categories", []),
            "topics": post.get("topics", []),
            "domain_rank": thread.get("domain_rank", 0),
            "performance_score": thread.get("performance_score", 0),
            "country": thread.get("country", ""),
            "main_image": thread.get("main_image", ""),
            "persons": [p.get("name", "") for p in entities.get("persons", [])],
            "organizations": [o.get("name", "") for o in entities.get("organizations", [])],
            "locations": [l.get("name", "") for l in entities.get("locations", [])],
            "syndicated": syndication.get("syndicated", False),
            "trust_category": trust.get("category", []),
            "trust_bias": trust.get("bias", ""),
            "social_facebook_likes": thread.get("social", {}).get("facebook", {}).get("likes", 0),
            "social_facebook_shares": thread.get("social", {}).get("facebook", {}).get("shares", 0),
            "highlight_text": post.get("highlightText", ""),
            "highlight_title": post.get("highlightTitle", ""),
        })

    return {
        "totalResults": data.get("totalResults", 0),
        "moreResultsAvailable": data.get("moreResultsAvailable", 0),
        "articles": articles,
        "next": data.get("next", ""),
        "requestsLeft": data.get("requestsLeft", -1),
    }


def fetch_next_page(next_url: str) -> dict:
    """Fetch the next page of results using the 'next' URL from a previous response.

    Args:
        next_url: The 'next' value from a previous search response

    Returns:
        Same structure as search_news / search_news_lite
    """
    if not next_url:
        return {"error": "No next URL provided"}

    full_url = f"https://api.webz.io{next_url}" if next_url.startswith("/") else next_url

    data = _make_request(full_url, {})
    if not data:
        return {"error": "Request failed"}

    articles = []
    for post in data.get("posts", []):
        thread = post.get("thread", {})
        articles.append({
            "title": thread.get("title", ""),
            "url": thread.get("url", ""),
            "site": thread.get("site_full", ""),
            "published": post.get("published", ""),
            "author": post.get("author", ""),
            "text": post.get("text", ""),
            "sentiment": post.get("sentiment", ""),
            "language": post.get("language", ""),
            "domain_rank": thread.get("domain_rank", 0),
        })

    return {
        "totalResults": data.get("totalResults", 0),
        "moreResultsAvailable": data.get("moreResultsAvailable", 0),
        "articles": articles,
        "next": data.get("next", ""),
        "requestsLeft": data.get("requestsLeft", -1),
    }


if __name__ == "__main__":
    result = search_news_lite("Bitcoin")
    print(f"Total results: {result.get('totalResults')}")
    for a in result.get("articles", []):
        print(f"  - {a['title']} ({a['site']})")
