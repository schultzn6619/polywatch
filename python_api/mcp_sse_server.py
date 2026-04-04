"""PolyWatch MCP Server (SSE transport) — for use with claude.ai via localhost.run tunnel.

Run:
    uv run --with "mcp[cli]" --with requests python3 python_api/mcp_sse_server.py

Then tunnel with: ssh -R 80:localhost:8089 localhost.run
Add the resulting https://xxxxx.lhr.life/sse URL to claude.ai integrations.
"""

import os
import subprocess
import requests
from datetime import datetime
from pathlib import Path
from typing import Optional
from mcp.server.fastmcp import FastMCP

PROJECT_ROOT = Path(__file__).resolve().parent.parent
WEBZ_TOKEN = os.environ.get("WEBZ_TOKEN", "")

mcp = FastMCP("polywatch", host="0.0.0.0", port=8089)


# --- Polymarket API helpers ---

def _fetch_from_api(url: str) -> Optional[list[dict]]:
    try:
        response = requests.get(url, timeout=10)
        response.raise_for_status()
        return response.json()
    except requests.RequestException:
        return None


# --- MCP Tools ---

@mcp.tool()
def get_event_info(slug: str) -> str:
    """Get detailed info about a Polymarket event by slug.

    Returns description, metadata, liquidity, volume, tags, and market outcomes.
    Example slugs: "us-x-iran-ceasefire-by", "will-bitcoin-hit-100k"
    """
    url = f"https://gamma-api.polymarket.com/events?slug={slug}"
    data = _fetch_from_api(url)

    if not data:
        return f"No event found for slug: {slug}"

    event = data[0]

    info = f"""Event: "{event.get("slug")}"
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

    tags = "Tags: " + ", ".join(t.get("slug", "") for t in event.get("tags", [])) + "\n"

    markets = event.get("markets", [])
    if not markets:
        return info + tags + "No markets found."

    market_info = "Markets:\n"
    for m in markets:
        market_info += f"""  Question: {m.get("question")}
    Liquidity: {m.get("liquidity")}
    Outcomes: {m.get("outcomes")}
    Outcome Prices: {m.get("outcomePrices")}
    Active: {m.get("active")}
    Closed: {m.get("closed")}
    Volume: {m.get("volume")}
    Volume 24h: ${m.get("volume24hr")}
    Volume 1wk: ${m.get("volume1wk")}
    Volume 1mo: ${m.get("volume1mo")}
    Volume 1yr: ${m.get("volume1yr")}
    Start Date: {m.get("startDate")}
    Creation Date: {m.get("creationDate")}
"""

    return info + tags + market_info


@mcp.tool()
def search_polymarket_events(query: str) -> str:
    """Search Polymarket events by keyword. Returns matching slugs, titles, and volumes."""
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
    """Run a jac CLI command in the project directory.

    Allowed commands: jac check, jac format, jac info, jac --version, jac --help, jac start.
    Example: 'jac check main.jac'
    """
    allowed_prefixes = [
        "jac check", "jac format", "jac info",
        "jac --version", "jac --help", "jac start",
    ]
    if not any(command.startswith(p) for p in allowed_prefixes):
        return f"Command not allowed. Permitted: {', '.join(allowed_prefixes)}"

    try:
        result = subprocess.run(
            command.split(),
            capture_output=True,
            text=True,
            timeout=30,
            cwd=str(PROJECT_ROOT),
        )
        output = result.stdout
        if result.stderr:
            output += "\nSTDERR:\n" + result.stderr
        return output or "(no output)"
    except subprocess.TimeoutExpired:
        return "Command timed out after 30 seconds."
    except Exception as e:
        return f"Error: {e}"


@mcp.tool()
def read_project_file(path: str) -> str:
    """Read a file from the PolyWatch project.

    Path is relative to the project root. Example: 'main.jac', 'services/appService.jac'
    """
    file_path = (PROJECT_ROOT / path).resolve()

    # Prevent path traversal
    if not str(file_path).startswith(str(PROJECT_ROOT)):
        return "Error: path must be within the project directory."

    if not file_path.exists():
        return f"File not found: {path}"

    if not file_path.is_file():
        return f"Not a file: {path}"

    try:
        return file_path.read_text()
    except Exception as e:
        return f"Error reading file: {e}"


@mcp.tool()
def list_project_files(directory: str = "") -> str:
    """List files in the PolyWatch project directory.

    Pass empty string or '.' for root. Example: 'services', 'pages', 'components'
    """
    dir_path = (PROJECT_ROOT / directory).resolve()

    if not str(dir_path).startswith(str(PROJECT_ROOT)):
        return "Error: path must be within the project directory."

    if not dir_path.exists():
        return f"Directory not found: {directory}"

    entries = []
    for item in sorted(dir_path.iterdir()):
        if item.name.startswith(".") or item.name == "node_modules" or item.name == "__pycache__":
            continue
        prefix = "📁" if item.is_dir() else "📄"
        entries.append(f"  {prefix} {item.name}")

    return f"Contents of {directory or '.'}:\n" + "\n".join(entries)


@mcp.tool()
def write_project_file(path: str, content: str) -> str:
    """Write/update a file in the PolyWatch project.

    Path is relative to project root. Creates parent directories if needed.
    Example: 'services/marketService.jac'
    """
    file_path = (PROJECT_ROOT / path).resolve()

    if not str(file_path).startswith(str(PROJECT_ROOT)):
        return "Error: path must be within the project directory."

    try:
        file_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.write_text(content)
        return f"Successfully wrote {path} ({len(content)} bytes)"
    except Exception as e:
        return f"Error writing file: {e}"


@mcp.tool()
def search_news(query: str, size: int = 10, sort: str = "relevancy") -> str:
    """Search news articles using webz.io News API Lite.

    Query supports filters like: title:(Bitcoin) sentiment:positive language:english site_type:news
    Available sorts: relevancy, published, performance_score, domain_rank
    """
    if not WEBZ_TOKEN:
        return "Error: WEBZ_TOKEN not set. Export it before starting the server."

    params = {"token": WEBZ_TOKEN, "q": query}
    try:
        resp = requests.get("https://api.webz.io/newsApiLite", params=params, timeout=15)
        resp.raise_for_status()
        data = resp.json()
    except requests.RequestException as e:
        return f"News API error: {e}"

    total = data.get("totalResults", 0)
    posts = data.get("posts", [])

    if not posts:
        return f"No news found for: {query}"

    result = f"Found {total} results (showing {len(posts)}):\n\n"
    for post in posts:
        thread = post.get("thread", {})
        result += f"Title: {thread.get('title', 'N/A')}\n"
        result += f"Site: {thread.get('site_full', 'N/A')}\n"
        result += f"Published: {post.get('published', 'N/A')}\n"
        result += f"Sentiment: {post.get('sentiment', 'N/A')}\n"
        result += f"URL: {thread.get('url', 'N/A')}\n"
        text = post.get("text", "")
        if text:
            result += f"Snippet: {text[:300]}...\n" if len(text) > 300 else f"Text: {text}\n"
        result += "\n"

    return result


if __name__ == "__main__":
    mcp.run(transport="sse")
