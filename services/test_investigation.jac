"""Test script — verify news pulling works and investigation can be kicked off.

Run with: jac run services/test_investigation.jac
"""

import from services.tools {
    tool_search_news,
    tool_search_news_sentiment,
    tool_search_news_timeline,
    tool_get_event_data,
    tool_get_market_movers,
    tool_compare_news_vs_trades,
    TOOL_REGISTRY,
    TOOL_DESCRIPTIONS
}


with entry {
    print("=" * 60);
    print("PolyWatch Investigation Tools — Integration Test");
    print("=" * 60);

    # ----- Test 1: News search -----
    print("\n--- Test 1: search_news ---");
    result = tool_search_news("title:(Maduro Trump) language:english");
    print("Summary: " + result["summary"]);
    print("Data visible to AI: " + str(result["data_visible_to_ai"]));
    print("Data preview (first 500 chars):");
    print(str(result["data"])[:500]);

    # ----- Test 2: Sentiment-filtered news -----
    print("\n--- Test 2: search_news_sentiment ---");
    result = tool_search_news_sentiment("Venezuela Maduro", "negative");
    print("Summary: " + result["summary"]);
    print("Data preview (first 500 chars):");
    print(str(result["data"])[:500]);

    # ----- Test 3: News timeline -----
    print("\n--- Test 3: search_news_timeline ---");
    result = tool_search_news_timeline("Maduro arrest");
    print("Summary: " + result["summary"]);
    print("Data preview (first 500 chars):");
    print(str(result["data"])[:500]);

    # ----- Test 4: Polymarket event data -----
    print("\n--- Test 4: get_event_data ---");
    result = tool_get_event_data("us-x-iran-ceasefire-by");
    print("Summary: " + result["summary"]);
    print("Data preview (first 500 chars):");
    print(str(result["data"])[:500]);

    # ----- Test 5: Placeholder — market movers -----
    print("\n--- Test 5: get_market_movers (PLACEHOLDER) ---");
    result = tool_get_market_movers("market-123");
    print("Summary: " + result["summary"]);
    print("Data: " + str(result["data"]));

    # ----- Test 6: Compare news vs trades -----
    print("\n--- Test 6: compare_news_vs_trades ---");
    result = tool_compare_news_vs_trades("market-123", "Maduro Venezuela");
    print("Summary: " + result["summary"]);
    print("Data preview (first 500 chars):");
    print(str(result["data"])[:500]);

    # ----- Test 7: Tool registry -----
    print("\n--- Test 7: Tool Registry ---");
    print("Registered tools: " + str(list(TOOL_REGISTRY.keys())));
    print("\nTool descriptions:");
    print(TOOL_DESCRIPTIONS);

    print("\n" + "=" * 60);
    print("All tests complete.");
    print("=" * 60);
}
