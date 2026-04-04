"""Test all 6 news API tool functions from amar_tools.

Run with: jac run services/test_news_api.jac
"""

import os;
import json;

import from services.amar_tools {
    search_news,
    get_event_news_timeline,
    check_pre_news_trades,
    correlate_market_trades_with_news,
    get_news_sentiment_around_event,
    analyze_pre_news_trading
}

def _print_result(name: str, result: dict) {
    print("\n" + "=" * 60);
    print("TEST: " + name);
    print("=" * 60);
    data = result.get("data", {});
    summary = result.get("summary", "");
    print("SUMMARY: " + summary);
    print("DATA KEYS: " + str(list(data.keys())));

    # Print key fields
    if "news_available" in data {
        print("  news_available: " + str(data["news_available"]));
    }
    if "relevant_article_count" in data {
        print("  relevant_article_count: " + str(data["relevant_article_count"]));
    }
    if "articles" in data {
        articles = data["articles"];
        print("  articles count: " + str(len(articles)));
        for a in articles[:3] {
            print("    - " + str(a.get("title", ""))[:80]);
            print("      source: " + str(a.get("source", "")));
            print("      published: " + str(a.get("published_at", "")));
        }
    }
    if "timeline" in data {
        timeline = data["timeline"];
        print("  timeline events: " + str(len(timeline)));
        for t in timeline[:3] {
            print("    - [" + str(t.get("timestamp", "")) + "] " + str(t.get("headline", ""))[:60]);
        }
    }
    if "earliest_relevant_news_timestamp" in data {
        print("  earliest_news: " + str(data["earliest_relevant_news_timestamp"]));
    }
    if "finding" in data {
        print("  finding: " + str(data["finding"]));
    }
    if "trading_classification" in data {
        print("  trading_classification: " + str(data["trading_classification"]));
    }
    if "pre_news_signal" in data {
        print("  pre_news_signal: " + str(data["pre_news_signal"]));
    }
    print("-" * 60);
}

# Test market — use a well-known event slug
glob TEST_MARKET: str = "us-operation-to-capture-maduro-in-2025";
glob TEST_QUERY: str = "Maduro Venezuela capture operation 2025";
glob TEST_WALLET: str = "0x01d7717581d7cb04be166eb4b0dba1ae087d1f79";

with entry {
    print("\n" + "#" * 60);
    print("  NEWS API FUNCTION TESTS");
    print("  WEBZ_API_KEY set: " + str(bool(os.environ.get("WEBZ_API_KEY", ""))));
    print("  NEWSAPI_API_KEY set: " + str(bool(os.environ.get("NEWSAPI_API_KEY", ""))));
    print("#" * 60);

    # ── Test 1: search_news ──────────────────────────────────────
    print("\n[1/6] Testing search_news...");
    try {
        result = search_news(TEST_QUERY);
        _print_result("search_news('" + TEST_QUERY + "')", result);
    } except Exception as e {
        print("FAILED: " + str(e));
    }

    # ── Test 2: get_event_news_timeline ──────────────────────────
    print("\n[2/6] Testing get_event_news_timeline...");
    try {
        result = get_event_news_timeline("US military operation to capture Maduro in Venezuela 2025");
        _print_result("get_event_news_timeline", result);
    } except Exception as e {
        print("FAILED: " + str(e));
    }

    # ── Test 3: check_pre_news_trades ────────────────────────────
    print("\n[3/6] Testing check_pre_news_trades...");
    try {
        result = check_pre_news_trades(TEST_WALLET, TEST_MARKET, "2025-03-15T00:00:00Z");
        _print_result("check_pre_news_trades", result);
    } except Exception as e {
        print("FAILED: " + str(e));
    }

    # ── Test 4: correlate_market_trades_with_news ────────────────
    print("\n[4/6] Testing correlate_market_trades_with_news...");
    try {
        result = correlate_market_trades_with_news(TEST_MARKET);
        _print_result("correlate_market_trades_with_news", result);
    } except Exception as e {
        print("FAILED: " + str(e));
    }

    # ── Test 5: get_news_sentiment_around_event ──────────────────
    print("\n[5/6] Testing get_news_sentiment_around_event...");
    try {
        result = get_news_sentiment_around_event("US operation to capture Maduro Venezuela", window_days=14);
        _print_result("get_news_sentiment_around_event", result);
    } except Exception as e {
        print("FAILED: " + str(e));
    }

    # ── Test 6: analyze_pre_news_trading ─────────────────────────
    print("\n[6/6] Testing analyze_pre_news_trading...");
    try {
        result = analyze_pre_news_trading(TEST_MARKET, "2025-04-01T00:00:00Z", top_n=5);
        _print_result("analyze_pre_news_trading", result);
    } except Exception as e {
        print("FAILED: " + str(e));
    }

    print("\n" + "#" * 60);
    print("  ALL NEWS API TESTS COMPLETE");
    print("#" * 60);
}
