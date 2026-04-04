"""Webz.io News API client for PolyWatch.

Supports both the free News API Lite and the full filterWebContent endpoint.
Docs: https://docs.webz.io/reference/1
"""

import os;
import requests;
import from pathlib { Path }

glob BASE_URL_LITE: str = "https://api.webz.io/newsApiLite";
glob BASE_URL_FULL: str = "https://api.webz.io/filterWebContent";


def _load_token() -> str {
    token = os.environ.get("WEBZ_TOKEN", "");
    if token {
        return token;
    }
    env_path = Path(__file__).resolve().parent.parent / ".env";
    if env_path.exists() {
        for line in env_path.read_text().splitlines() {
            if line.startswith("WEBZ_TOKEN=") {
                return line.split("=", 1)[1].strip();
            }
        }
    }
    return "";
}

glob WEBZ_TOKEN: str = _load_token();


def _make_request(url: str, params: dict) -> dict {
    try {
        resp = requests.get(url, params=params, timeout=15);
        resp.raise_for_status();
        return resp.json();
    } except Exception as e {
        print("Webz.io API error: " + str(e));
        return {};
    }
}


# Parse a single post from the API response into a simplified article dict
def _parse_article(post: dict, full: bool = False) -> dict {
    thread = post.get("thread", {});
    article = {
        "title": thread.get("title", ""),
        "url": thread.get("url", ""),
        "site": thread.get("site_full", ""),
        "published": post.get("published", ""),
        "author": post.get("author", ""),
        "text": post.get("text", ""),
        "sentiment": post.get("sentiment", ""),
        "language": post.get("language", ""),
        "domain_rank": thread.get("domain_rank", 0),
        "country": thread.get("country", "")
    };

    if not full {
        article["categories"] = post.get("categories", []);
        return article;
    }

    # Full API includes extra fields
    entities = post.get("entities", {});
    syndication = post.get("syndication", {});
    trust = thread.get("trust", {});

    article["summary"] = post.get("summary", "");
    article["categories"] = post.get("categories", []);
    article["topics"] = post.get("topics", []);
    article["performance_score"] = thread.get("performance_score", 0);
    article["main_image"] = thread.get("main_image", "");

    persons = [];
    for p in entities.get("persons", []) {
        persons.append(p.get("name", ""));
    }
    article["persons"] = persons;

    orgs = [];
    for o in entities.get("organizations", []) {
        orgs.append(o.get("name", ""));
    }
    article["organizations"] = orgs;

    locs = [];
    for l in entities.get("locations", []) {
        locs.append(l.get("name", ""));
    }
    article["locations"] = locs;

    article["syndicated"] = syndication.get("syndicated", False);
    article["trust_category"] = trust.get("category", []);
    article["trust_bias"] = trust.get("bias", "");

    social = thread.get("social", {});
    fb = social.get("facebook", {});
    article["social_facebook_likes"] = fb.get("likes", 0);
    article["social_facebook_shares"] = fb.get("shares", 0);

    article["highlight_text"] = post.get("highlightText", "");
    article["highlight_title"] = post.get("highlightTitle", "");

    return article;
}


# Wrap API response into a standard return dict
def _build_response(data: dict, full: bool = False) -> dict {
    articles = [];
    for post in data.get("posts", []) {
        articles.append(_parse_article(post, full));
    }

    return {
        "totalResults": data.get("totalResults", 0),
        "moreResultsAvailable": data.get("moreResultsAvailable", 0),
        "articles": articles,
        "next": data.get("next", ""),
        "requestsLeft": data.get("requestsLeft", -1)
    };
}


# Search news using the free News API Lite (max 10 results, snippets only)
def search_news_lite(query: str, ts: int = 0) -> dict {
    if not WEBZ_TOKEN {
        return {"error": "WEBZ_TOKEN not set. Export it as an environment variable."};
    }

    params: dict = {"token": WEBZ_TOKEN, "q": query};
    if ts {
        params["ts"] = ts;
    }

    data = _make_request(BASE_URL_LITE, params);
    if not data {
        return {"error": "Request failed"};
    }

    return _build_response(data, False);
}


# Search news using the full filterWebContent API
def search_news(
    query: str,
    size: int = 20,
    sort: str = "relevancy",
    order: str = "desc",
    ts: int = 0,
    highlight: bool = False
) -> dict {
    if not WEBZ_TOKEN {
        return {"error": "WEBZ_TOKEN not set. Export it as an environment variable."};
    }

    clamped_size = size;
    if clamped_size < 1 {
        clamped_size = 1;
    }
    if clamped_size > 100 {
        clamped_size = 100;
    }

    params: dict = {
        "token": WEBZ_TOKEN,
        "q": query,
        "format": "json",
        "size": clamped_size,
        "sort": sort,
        "order": order
    };
    if ts {
        params["ts"] = ts;
    }
    if highlight {
        params["highlight"] = "true";
    }

    data = _make_request(BASE_URL_FULL, params);
    if not data {
        return {"error": "Request failed"};
    }

    return _build_response(data, True);
}


# Fetch the next page of results using the 'next' URL from a previous response
def fetch_next_page(next_url: str) -> dict {
    if not next_url {
        return {"error": "No next URL provided"};
    }

    full_url = next_url;
    if next_url.startswith("/") {
        full_url = "https://api.webz.io" + next_url;
    }

    data = _make_request(full_url, {});
    if not data {
        return {"error": "Request failed"};
    }

    return _build_response(data, False);
}
