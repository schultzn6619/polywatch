"""Polymarket Gamma API client for PolyWatch."""

import requests;
import from datetime { datetime }


def _fetch_from_api(url: str) -> list {
    try {
        response = requests.get(url, timeout=10);
        response.raise_for_status();
        return response.json();
    } except Exception as e {
        print("Polymarket API error: " + str(e));
        return [];
    }
}


def _find_event_by_slug(slug: str) -> list {
    url = "https://gamma-api.polymarket.com/events?slug=" + slug;
    data = _fetch_from_api(url);
    if data {
        return data;
    }
    return [];
}


# Get detailed information about a Polymarket event by its slug
def get_event_info(slug: str) -> str {
    events = _find_event_by_slug(slug);

    if not events or len(events) == 0 {
        return "No event found for slug: " + slug;
    }

    event = events[0];
    metadata = event.get("eventMetadata", {});

    d1 = "Event: \"" + str(event.get("slug")) + "\"\n";
    d1 += "Description: " + str(event.get("description")) + "\n";
    d1 += "AI Generated Context: " + str(metadata.get("context_description")) + "\n";
    d1 += "AI Context Updated: " + str(metadata.get("context_updated_at")) + "\n";
    d1 += "Today's Date: " + str(datetime.now()) + "\n";
    d1 += "Start Date: " + str(event.get("startDate")) + "\n";
    d1 += "Creation Date: " + str(event.get("creationDate")) + "\n";
    d1 += "End Date: " + str(event.get("endDate")) + "\n";
    d1 += "Liquidity: $" + str(event.get("liquidity")) + "\n";
    d1 += "Volume: $" + str(event.get("volume")) + "\n";
    d1 += "Volume 24h: $" + str(event.get("volume24hr")) + "\n";
    d1 += "Volume 1wk: $" + str(event.get("volume1wk")) + "\n";
    d1 += "Volume 1mo: $" + str(event.get("volume1mo")) + "\n";
    d1 += "Volume 1yr: $" + str(event.get("volume1yr")) + "\n";
    d1 += "Liquidity Clob: $" + str(event.get("liquidityClob")) + "\n";

    tags_str = "Tags: ";
    for tag in event.get("tags", []) {
        tags_str += str(tag.get("slug", "")) + ", ";
    }
    tags_str += "\n";

    markets = event.get("markets", []);
    if not markets or len(markets) == 0 {
        return d1 + tags_str + "No markets found for this event.";
    }

    d2 = "Markets:\n";
    for market in markets {
        d2 += "  Question: " + str(market.get("question")) + "\n";
        d2 += "    Liquidity: " + str(market.get("liquidity")) + "\n";
        d2 += "    Outcomes: " + str(market.get("outcomes")) + "\n";
        d2 += "    Outcome Prices: " + str(market.get("outcomePrices")) + "\n";
        d2 += "    Active: " + str(market.get("active")) + "\n";
        d2 += "    Closed: " + str(market.get("closed")) + "\n";
        d2 += "    Volume: " + str(market.get("volume")) + "\n";
        d2 += "    Volume 24h: $" + str(market.get("volume24hr")) + "\n";
        d2 += "    Volume 1wk: $" + str(market.get("volume1wk")) + "\n";
        d2 += "    Volume 1mo: $" + str(market.get("volume1mo")) + "\n";
        d2 += "    Volume 1yr: $" + str(market.get("volume1yr")) + "\n";
        d2 += "    Start Date: " + str(market.get("startDate")) + "\n";
        d2 += "    Creation Date: " + str(market.get("creationDate")) + "\n";
    }

    return d1 + tags_str + d2;
}


# Search for Polymarket events by keyword query
def search_events(query: str) -> str {
    url = "https://gamma-api.polymarket.com/events?title=" + query + "&limit=10";
    data = _fetch_from_api(url);

    if not data {
        return "No events found for query: " + query;
    }

    results: list = [];
    for event in data {
        slug = event.get("slug", "");
        title = event.get("title", "");
        volume = event.get("volume", "0");
        results.append("- " + title + " (slug: " + slug + ", volume: $" + str(volume) + ")");
    }

    return "Found " + str(len(results)) + " events:\n" + "\n".join(results);
}
