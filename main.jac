"""Fullstack Starter - Entry Point.

Imports server-side symbols and mounts the client app.
"""

import from services.appService { greet }
import from services.newsService { search_news_lite, search_news_full, get_next_page }

cl import from .index { ClientApp }

cl {
    def:pub app() -> JsxElement {
        return <ClientApp />;
    }
}
