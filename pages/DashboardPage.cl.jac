import from "@jac/runtime" { jacLogout, useNavigate, __doFuncFetch }

def:pub page() -> JsxElement {
    has query: str = "";
    has events: list = [];
    has loading: bool = False;
    has searched: bool = False;

    navigate = useNavigate();

    def handle_logout() -> None {
        jacLogout();
        navigate("/login");
    }

    def on_query_change(e: any) -> None {
        query = e.target.value;
    }

    async def handle_search(e: any) -> None {
        e.preventDefault();
        if not query {
            return;
        }
        loading = True;
        searched = True;
        try {
            res = await __doFuncFetch("search_polymarket", {"query": query});
            events = res.get("events", []);
        } except Exception as err {
            events = [];
        }
        loading = False;
    }

    def format_volume(vol: str) -> str {
        try {
            n = float(vol);
            if n >= 1000000 {
                return "$" + str(round(n / 1000000, 1)) + "M";
            }
            if n >= 1000 {
                return "$" + str(round(n / 1000, 1)) + "K";
            }
            return "$" + str(round(n, 0));
        } except {
            return "$0";
        }
    }

    return (
        <div className="page">
            <div className="page-container">
                <div className="page-header">
                    <div>
                        <h1>PolyWatch</h1>
                        <p className="text-sm text-muted-foreground">Search and explore Polymarket events</p>
                    </div>
                    <button className="btn btn-ghost" onClick={handle_logout}>
                        Sign out
                    </button>
                </div>

                <form className="search-bar" onSubmit={handle_search}>
                    <input
                        className="input search-input"
                        type="text"
                        placeholder="Search events... (e.g. election, bitcoin, fed)"
                        value={query}
                        onChange={on_query_change}
                    />
                    <button className="btn btn-primary" type="submit" disabled={loading}>
                        {loading and "Searching..." or "Search"}
                    </button>
                </form>

                {loading and (
                    <div className="search-status">
                        <p className="text-muted-foreground">Searching Polymarket...</p>
                    </div>
                )}

                {not loading and searched and len(events) == 0 and (
                    <div className="search-status">
                        <p className="text-muted-foreground">No events found. Try a different search term.</p>
                    </div>
                )}

                {len(events) > 0 and (
                    <div className="event-grid">
                        {[
                            <div className="event-card" key={ev.get("slug", "")}>
                                <div className="event-card-header">
                                    <h3 className="event-card-title">{ev.get("title", "")}</h3>
                                    <span className={"event-badge " + (ev.get("active", False) and "event-badge-active" or "event-badge-closed")}>
                                        {ev.get("active", False) and "Active" or "Closed"}
                                    </span>
                                </div>
                                <div className="event-card-stats">
                                    <div className="event-stat">
                                        <span className="event-stat-label">Volume</span>
                                        <span className="event-stat-value">{format_volume(str(ev.get("volume", "0")))}</span>
                                    </div>
                                    <div className="event-stat">
                                        <span className="event-stat-label">Liquidity</span>
                                        <span className="event-stat-value">{format_volume(str(ev.get("liquidity", "0")))}</span>
                                    </div>
                                    <div className="event-stat">
                                        <span className="event-stat-label">Markets</span>
                                        <span className="event-stat-value">{str(ev.get("markets_count", 0))}</span>
                                    </div>
                                </div>
                                <button className="btn btn-primary event-card-btn" onClick={lambda: navigate("/investigation?slug=" + ev.get("slug", ""))}>
                                    Investigate
                                </button>
                            </div>
                            for ev in events
                        ]}
                    </div>
                )}

                {not searched and (
                    <div className="search-status">
                        <p className="text-muted-foreground">Search for Polymarket events to get started.</p>
                    </div>
                )}
            </div>
        </div>
    );
}
