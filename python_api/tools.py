import requests
from typing import Dict, List, Any, Optional
from datetime import datetime

# Helper function for reusable API calls
def _fetch_from_api(url: str) -> Optional[List[Dict]]:
    """Generic API fetcher with error handling."""
    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        return response.json()
    except requests.RequestException as e:
        print(f"API error: {e}")
        return None

def _find_event_by_slug(slug: str) -> List[Dict]:
    """Find all markets matching a given slug."""
    url = f"https://gamma-api.polymarket.com/events?slug={slug}"
    data = _fetch_from_api(url)
    return data if data else []

def get_event_info(slug: str):
    events = _find_event_by_slug(slug)

    if not events or len(events) == 0:
        raise Exception("No event found for slug")
    
    event = events[0]

    d1 = f"""Below is a full description for the event "{event.get("slug")}"
Description: {event.get("description")}
AI Generated Context: {event.get("eventMetadata").get("context_description")}
AI Gen Context Generation Date: {event.get("eventMetadata").get("context_updated_at")}
Today's Date: {datetime.now()}
Start Date: {event.get("startDate")}
Creation Date: {event.get("creationDate")}
End Date: {event.get("endDate")}
Liquidity: ${event.get("liquidity")}
Volume: ${event.get("volume")}
Volume 24h: ${event.get("volume24hr")}
Volume 1wk: ${event.get("volume1wk")}
Volume 1mo: ${event.get("volume1mo")}
Volume 1ye: ${event.get("volume1yr")}
Liquidity Clob: ${event.get("liquidityClob")}
"""
    
    t = "Tag Slugs: "
    for tag in event.get("tags"):
        t += tag.get("slug") + ", "
    t += "\n"
    
    markets = event.get("markets")
    if not markets or len(markets) == 0:
        raise Exception("No markets found for event")

    d2 = "Markets:\n"
    for market in markets:
        d = f"""   Question: {market.get("question")}
    • Liquidity: {market.get("liquidity")}
    • Outcomes: {market.get("outcomes")}
    • Outcome Prices: {market.get("outcomePrices")}
    • Active: {market.get("active")}
    • Closed: {market.get("closed")}
    • Volume: {market.get("volume")}
    • Volume 24h: ${market.get("volume24hr")}
    • Volume 1wk: ${event.get("volume1wk")}
    • Volume 1mo: ${market.get("volume1mo")}
    • Volume 1ye: ${market.get("volume1yr")}
    • Start Date: {market.get("startDate")}
    • Creation Date: {market.get("creationDate")}
"""
        d2 += d

    description = d1 + t + d2
    return description


# Example usage
if __name__ == "__main__":
    # Example 1: Using slug (multiple markets possible)
    slug_example = "us-x-iran-ceasefire-by"
    print(get_event_info(slug_example))
