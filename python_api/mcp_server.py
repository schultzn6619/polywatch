"""PolyWatch MCP Server — exposes Polymarket tools to Claude Code."""

import subprocess
import requests
from datetime import datetime
from typing import Optional
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("polywatch")


# --- Polymarket API helpers ---

def _fetch_from_api(url: str) -> Optional[list[dict]]:
    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        return response.json()
    except requests.RequestException as e:
        return None


def _find_event_by_slug(slug: str) -> list[dict]:
    url = f"https://gamma-api.polymarket.com/events?slug={slug}"
    data = _fetch_from_api(url)
    return data if data else []


# --- MCP Tools ---

@mcp.tool()
def get_event_info(slug: str) -> str:
    """Get detailed information about a Polymarket prediction market event by its slug.

    Returns event description, metadata, liquidity, volume stats, tags, and all market outcomes with prices.
    Example slugs: "us-x-iran-ceasefire-by", "will-bitcoin-hit-100k"
    """
    events = _find_event_by_slug(slug)

    if not events:
        return f"No event found for slug: {slug}"

    event = events[0]

    d1 = f"""Event: "{event.get("slug")}"
Description: {event.get("description")}
AI Generated Context: {event.get("eventMetadata", {}).get("context_description")}
AI Context Updated: {event.get("eventMetadata", {}).get("context_updated_at")}
Today's Date: {datetime.now()}
Start Date: {event.get("startDate")}
Creation Date: {event.get("creationDate")}
End Date: {event.get("endDate")}
Liquidity: ${event.get("liquidity")}
Volume: ${event.get("volume")}
Volume 24h: ${event.get("volume24hr")}
Volume 1wk: ${event.get("volume1wk")}
Volume 1mo: ${event.get("volume1mo")}
Volume 1yr: ${event.get("volume1yr")}
Liquidity Clob: ${event.get("liquidityClob")}
"""

    tags = "Tags: " + ", ".join(tag.get("slug", "") for tag in event.get("tags", [])) + "\n"

    markets = event.get("markets", [])
    if not markets:
        return d1 + tags + "No markets found for this event."

    d2 = "Markets:\n"
    for market in markets:
        d2 += f"""  Question: {market.get("question")}
    Liquidity: {market.get("liquidity")}
    Outcomes: {market.get("outcomes")}
    Outcome Prices: {market.get("outcomePrices")}
    Active: {market.get("active")}
    Closed: {market.get("closed")}
    Volume: {market.get("volume")}
    Volume 24h: ${market.get("volume24hr")}
    Volume 1wk: ${market.get("volume1wk")}
    Volume 1mo: ${market.get("volume1mo")}
    Volume 1yr: ${market.get("volume1yr")}
    Start Date: {market.get("startDate")}
    Creation Date: {market.get("creationDate")}
"""

    return d1 + tags + d2


@mcp.tool()
def search_polymarket_events(query: str) -> str:
    """Search for Polymarket events by keyword query.

    Returns a list of matching event slugs and titles.
    """
    url = f"https://gamma-api.polymarket.com/events?title={query}&limit=10"
    data = _fetch_from_api(url)

    if not data:
        return f"No events found for query: {query}"

    results = []
    for event in data:
        slug = event.get("slug", "")
        title = event.get("title", "")
        volume = event.get("volume", "0")
        results.append(f"- {title} (slug: {slug}, volume: ${volume})")

    return f"Found {len(results)} events:\n" + "\n".join(results)


@mcp.tool()
def jac_run(command: str) -> str:
    """Run a jac CLI command and return the output.

    Examples: 'jac check main.jac', 'jac format services/appService.jac'
    Only allows read-only / safe jac commands (check, format, info).
    """
    allowed_prefixes = ["jac check", "jac format", "jac info", "jac --version", "jac --help"]
    if not any(command.startswith(prefix) for prefix in allowed_prefixes):
        return f"Command not allowed. Permitted prefixes: {', '.join(allowed_prefixes)}"

    try:
        result = subprocess.run(
            command.split(),
            capture_output=True,
            text=True,
            timeout=30,
            cwd="/home/nathansc/Documents/Hackathon/polywatch",
        )
        output = result.stdout
        if result.stderr:
            output += "\nSTDERR:\n" + result.stderr
        return output or "(no output)"
    except subprocess.TimeoutExpired:
        return "Command timed out after 30 seconds."
    except Exception as e:
        return f"Error running command: {e}"


if __name__ == "__main__":
    mcp.run()
