"""Fullstack Starter - Entry Point.

Imports server-side symbols and mounts the client app.
"""

import from services.appService { greet }
import from services.newsService { search_news_lite, search_news_full, get_next_page }
import from services.investigation { run_investigation }
import from services.tools { TOOL_REGISTRY, TOOL_DESCRIPTIONS }

cl import from .index { ClientApp }

cl {
    def:pub app() -> JsxElement {
        return <ClientApp />;
    }
}
