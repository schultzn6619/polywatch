"""Investigation page — start and view Tree of Thought investigations."""

import from "@jac/runtime" { jacLogout, useNavigate, __doFuncFetch }

def:pub page() -> JsxElement {
    has phase: str = "input";
    has slug: str = "";
    has goal: str = "";
    has loading: bool = False;
    has error: str = "";
    has elapsed: int = 0;
    has timer_id: any = None;
    has poll_id: any = None;
    has result: any = None;
    has auto_started: bool = False;
    has live_tree: list = [];
    has live_status: str = "";
    has live_tool_calls: int = 0;
    has live_llm_calls: int = 0;
    has live_categories: list = [];
    has live_artifacts: list = [];
    has selected_artifact: any = None;
    has auto_scroll: bool = True;
    has tree_view_mode: str = "list";
    has prev_investigations: list = [];
    has prev_loaded: bool = False;
    has active_tab: str = "overview";
    has is_running: bool = False;

    navigate = useNavigate();

    # Expose citation click handler on window
    window.__polywatch_open_cite = lambda aid: handle_citation_click(aid);

    # Global click listener for citation links. This body runs on every render,
    # so bind once and dispatch through the window handler refreshed above.
    def _setup_cite_listener() -> None {
        if window.__polywatch_cite_bound { return; }
        window.__polywatch_cite_bound = True;
        document.addEventListener("click", lambda e: (
            e.target.classList.contains("citation-link") and
            e.target.getAttribute("data-aid") and
            window.__polywatch_open_cite(e.target.getAttribute("data-aid"))
        ));
    }
    _setup_cite_listener();

    # Load previous investigations on mount
    if not prev_loaded {
        prev_loaded = True;
        async def _load_prev() -> None {
            try {
                res = await __doFuncFetch("list_investigations", {});
                if res and res["investigations"] {
                    prev_investigations = res["investigations"];
                }
            } except Exception as e {
                console.log("[PREV] Error:", e);
            }
        }
        _load_prev();
    }

    # Auto-start if slug is in URL params (runs only once)
    if not auto_started and phase == "input" and not loading {
        auto_started = True;
        full_url = String(window.location.href);
        search_part = String(window.location.search);
        src = search_part if search_part and search_part.length > 1 else full_url;
        idx = src.indexOf("slug=");
        if idx >= 0 {
            rest = src.substring(idx + 5);
            amp = rest.indexOf("&");
            if amp >= 0 { rest = rest.substring(0, amp); }
            hash_pos = rest.indexOf("#");
            if hash_pos >= 0 { rest = rest.substring(0, hash_pos); }
            parsed_slug = decodeURIComponent(rest);
            if parsed_slug and parsed_slug.length > 0 {
                slug = parsed_slug;
                run_investigation(parsed_slug);
            }
        }
    }

    def handle_logout() -> None {
        jacLogout();
        navigate("/login");
    }

    def on_slug_change(e: any) -> None { slug = e.target.value; }
    def on_goal_change(e: any) -> None { goal = e.target.value; }

    def tick() -> None {
        st = window.__polywatch_start_time;
        if st and st > 0 {
            elapsed = Math.floor((Date.now() - st) / 1000);
        }
    }

    def open_artifact(art: any) -> None { selected_artifact = art; }
    def close_artifact() -> None { selected_artifact = None; }
    def toggle_auto_scroll() -> None { auto_scroll = not auto_scroll; }
    def set_tree_view(mode: str) -> None { tree_view_mode = mode; }
    def switch_tab(tab: str) -> None { active_tab = tab; }

    async def end_investigation() -> None {
        try { await __doFuncFetch("stop_investigation", {}); }
        except Exception as e { console.log("[STOP] Error:", e); }
    }

    def handle_citation_click(aid: str) -> None {
        arts = window.__polywatch_artifacts or [];
        for i in range(len(arts)) {
            if arts[i]["id"] == aid {
                open_artifact(arts[i]);
                return;
            }
        }
    }

    def render_report_with_citations(text: str) -> str {
        html = text;
        html = html.split("&").join("&amp;");
        html = html.split("<").join("&lt;");
        html = html.split(">").join("&gt;");
        for i in range(50, 0, -1) {
            aid = "A" + str(i);
            placeholder = "@@CITE_" + str(i) + "@@";
            if html.indexOf(aid) >= 0 { html = html.split(aid).join(placeholder); }
        }
        for i in range(1, 51) {
            aid = "A" + str(i);
            placeholder = "@@CITE_" + str(i) + "@@";
            if html.indexOf(placeholder) >= 0 {
                html = html.split(placeholder).join("<span class='citation-link' data-aid='" + aid + "'>" + aid + "</span>");
            }
        }
        html = html.split("\n").join("<br/>");
        return html;
    }

    def find_active_node_idx(tree: list) -> int {
        last_active = -1;
        for i in range(len(tree)) {
            if tree[i]["status"] == "active" { last_active = i; }
        }
        return last_active;
    }

    def format_timestamp(ts: any) -> str {
        if not ts { return "N/A"; }
        try {
            s = String(ts);
            if s.indexOf("T") >= 0 { return s.substring(0, 10); }
            if s.length > 16 and isNaN(Number(s)) { return s.substring(0, 16); }
        } except Exception { 0; }
        return String(ts);
    }

    def get_tool_description(status: str) -> str {
        if not status { return "Investigating market activity..."; }
        tool = String(status).toLowerCase();
        if tool.startsWith("tool: ") { tool = tool.substring(6).trim(); }
        descs = {
            "get_market_movers": "Checking major market movers...",
            "get_large_trades": "Tracking large trades...",
            "find_synchronized_traders": "Searching for coordinated trading...",
            "build_trader_network": "Mapping the trader network...",
            "get_wallet_profile": "Profiling a trader wallet...",
            "get_wallet_history": "Reviewing wallet history...",
            "get_wallet_pnl": "Analyzing wallet profit and loss...",
            "get_event_news_timeline": "Scanning news timeline...",
            "correlate_market_trades_with_news": "Comparing trades against news...",
            "search_news": "Searching news sources...",
            "analyze_pre_news_trading": "Looking for trades before news broke...",
            "get_market_price_history": "Pulling price history...",
            "detect_abnormal_volume": "Checking for abnormal volume...",
            "detect_unusual_timing_patterns": "Analyzing trade timing patterns...",
            "compare_market_vs_external": "Comparing market vs external data...",
            "get_cluster_summary": "Reviewing trader clusters...",
            "get_market_summary": "Summarizing market overview...",
            "find_whale_wallets": "Looking for whale wallets...",
            "get_orderbook_depth": "Checking orderbook depth...",
            "get_recent_trades": "Scanning recent trades..."
        };
        if descs[tool] { return descs[tool]; }
        if tool.indexOf("news") >= 0 { return "Scanning news sources..."; }
        if tool.indexOf("wallet") >= 0 { return "Investigating wallet activity..."; }
        if tool.indexOf("trade") >= 0 or tool.indexOf("market") >= 0 { return "Analyzing market activity..."; }
        if tool.indexOf("network") >= 0 or tool.indexOf("cluster") >= 0 { return "Mapping connections..."; }
        if tool.indexOf("volume") >= 0 { return "Checking volume patterns..."; }
        if tool.indexOf("price") >= 0 { return "Reviewing price data..."; }
        if tool == "generating report" { return "Writing the report..."; }
        if tool == "bootstrapping" { return "Setting up the investigation..."; }
        if tool == "investigating" { return "Investigating leads..."; }
        if tool == "starting..." { return "Starting up..."; }
        return "Investigating market activity...";
    }

    def get_funny_phrase(status: str) -> str {
        if not status { return "Warming up the magnifying glass..."; }
        tool = String(status).toLowerCase();
        if tool.startsWith("tool: ") { tool = tool.substring(6).trim(); }
        phrases = {
            "get_market_movers": ["Following the biggest players...", "Checking who moved the market...", "Finding the heavy hitters..."],
            "get_large_trades": ["Looking for fat stacks...", "Spotting the big fish...", "Who dropped serious money?"],
            "find_synchronized_traders": ["Searching for bad guys...", "Looking for coordinated moves...", "Checking who's moving together..."],
            "build_trader_network": ["Connecting the dots...", "Drawing the suspect web...", "Mapping who knows who..."],
            "get_wallet_profile": ["Digging into a wallet...", "Profiling the usual suspect...", "Checking a trader's habits..."],
            "get_wallet_history": ["Reading their diary...", "Going through the receipts...", "Checking their paper trail..."],
            "get_wallet_pnl": ["Counting their money...", "Following the profit trail...", "Checking who got rich..."],
            "get_event_news_timeline": ["Reading all the headlines...", "Checking what the papers said...", "Scanning the newswire..."],
            "correlate_market_trades_with_news": ["Matching trades to headlines...", "Comparing receipts...", "Lining up timelines..."],
            "search_news": ["Digging through articles...", "Reading the fine print...", "Checking the rumor mill..."],
            "analyze_pre_news_trading": ["Who knew before the news?", "Looking for time travelers...", "Checking for crystal ball users..."],
            "get_market_price_history": ["Watching the chart wiggle...", "Studying price moves...", "Watching the chart do suspicious things..."],
            "detect_abnormal_volume": ["Spotting volume spikes...", "Something looks sus here...", "That volume is not normal..."],
            "detect_unusual_timing_patterns": ["Checking suspicious timing...", "Who traded at weird hours?", "Looking for pattern breakers..."],
            "get_cluster_summary": ["Grouping the suspects...", "Finding the cliques...", "Who's in cahoots?"],
            "find_whale_wallets": ["Looking for whale behavior...", "Hunting for big wallets...", "Finding the ocean's biggest fish..."],
            "get_orderbook_depth": ["Peeking at the orderbook...", "Checking supply and demand...", "Diving into the book..."],
            "get_recent_trades": ["Scanning the tape...", "Who just traded?", "Checking recent action..."]
        };
        if phrases[tool] {
            arr = phrases[tool];
            idx = Math.floor(Math.random() * len(arr));
            return arr[idx];
        }
        if tool.indexOf("news") >= 0 { return "Checking the headlines..."; }
        if tool.indexOf("wallet") >= 0 { return "Snooping through wallets..."; }
        if tool.indexOf("trade") >= 0 or tool.indexOf("market") >= 0 { return "Following the money..."; }
        if tool.indexOf("network") >= 0 or tool.indexOf("cluster") >= 0 { return "Looking for connections..."; }
        if tool.indexOf("volume") >= 0 { return "That volume looks suspicious..."; }
        if tool == "generating report" { return "Writing up the findings..."; }
        if tool == "bootstrapping" { return "Putting on the detective hat..."; }
        if tool == "investigating" { return "Sniffing around..."; }
        if tool == "starting..." { return "Warming up the magnifying glass..."; }
        return "Doing detective work...";
    }

    def get_tool_name_from_status(status: str) -> str {
        if not status { return ""; }
        tool = String(status);
        if tool.toLowerCase().startsWith("tool: ") { return tool.substring(6).trim(); }
        return tool;
    }

    def get_stable_funny_phrase(status: str) -> str {
        now = Date.now();
        tool_key = get_tool_name_from_status(status);
        prev_tool = window.__pw_phrase_tool or "";
        prev_time = window.__pw_phrase_time or 0;
        prev_phrase = window.__pw_phrase or "";
        if tool_key != prev_tool {
            phrase = get_funny_phrase(status);
            window.__pw_phrase = phrase;
            window.__pw_phrase_tool = tool_key;
            window.__pw_phrase_time = now;
            return phrase;
        }
        if prev_phrase and (now - prev_time) < 3000 {
            return prev_phrase;
        }
        phrase = get_funny_phrase(status);
        window.__pw_phrase = phrase;
        window.__pw_phrase_time = now;
        return phrase;
    }

    def extract_live_news(artifacts: list) -> list {
        news: list = [];
        seen_titles: list = [];
        for i in range(len(artifacts)) {
            art = artifacts[i];
            cat = String(art["category"] or "");
            tool = String(art["tool"] or "");
            if cat == "news" or tool.toLowerCase().indexOf("news") >= 0 {
                data = art["data"];
                if not data { continue; }
                sources: list = [];
                if data["articles"] and Array.isArray(data["articles"]) { sources = data["articles"]; }
                if data["timeline"] and Array.isArray(data["timeline"]) {
                    for t in range(len(data["timeline"])) {
                        item = data["timeline"][t];
                        sources.append({
                            "title": item["headline"] or item["title"] or "",
                            "url": item["url"] or "",
                            "source": item["source"] or "",
                            "published_at": item["timestamp"] or item["published_at"] or "",
                            "description": ""
                        });
                    }
                }
                for j in range(len(sources)) {
                    a = sources[j];
                    title = String(a["title"] or a["headline"] or "");
                    if title and title.length > 0 and seen_titles.indexOf(title) < 0 {
                        seen_titles.append(title);
                        news.append({
                            "title": title,
                            "url": String(a["url"] or a["link"] or ""),
                            "source": String(a["source"] or a["publisher"] or ""),
                            "published_at": String(a["published_at"] or a["date"] or a["timestamp"] or ""),
                            "description": String(a["description"] or a["snippet"] or "")
                        });
                    }
                }
            }
        }
        return news;
    }

    async def load_prev_investigation(filename: str) -> None {
        loading = True;
        try {
            res = await __doFuncFetch("load_investigation", {"filename": filename});
            if res and res["result"] {
                result = res["result"];
                window.__polywatch_artifacts = res["result"]["artifacts"] or [];
                is_running = False;
                phase = "active";
                active_tab = "overview";
            } else { error = "Failed to load investigation"; }
        } except Exception as e {
            error = "Error loading investigation: " + str(e);
        }
        loading = False;
    }

    async def poll_progress() -> None {
        # Skip this tick if the previous poll is still in flight.
        if window.__polywatch_polling { return; }
        window.__polywatch_polling = True;
        try {
            prog = await __doFuncFetch("get_investigation_progress", {});
            if prog {
                if prog["tree"] { live_tree = prog["tree"]; }
                live_status = prog["status"] or "";
                live_tool_calls = prog["total_tool_calls"] or 0;
                live_llm_calls = prog["total_llm_calls"] or 0;
                if prog["categories"] { live_categories = prog["categories"]; }
                if prog["artifacts"] {
                    live_artifacts = prog["artifacts"];
                    window.__polywatch_artifacts = prog["artifacts"];
                }
                if auto_scroll and active_tab == "tree" {
                    scroll_el = document.getElementById("tree-scroll-container");
                    if scroll_el { scroll_el.scrollTop = scroll_el.scrollHeight; }
                }
                if prog["status"] == "complete" and prog["result"] {
                    if timer_id { clearInterval(timer_id); }
                    if poll_id { clearInterval(poll_id); }
                    result = prog["result"];
                    window.__polywatch_artifacts = prog["result"]["artifacts"] or [];
                    loading = False;
                    is_running = False;
                    try {
                        prev_res = await __doFuncFetch("list_investigations", {});
                        if prev_res and prev_res["investigations"] { prev_investigations = prev_res["investigations"]; }
                    } except Exception { 0; }
                }
                if prog["status"] and prog["status"].startsWith("error") {
                    if timer_id { clearInterval(timer_id); }
                    if poll_id { clearInterval(poll_id); }
                    error = prog["status"];
                    loading = False;
                    is_running = False;
                    phase = "input";
                }
            }
        } except Exception as e { console.log("[POLL ERROR]", e); }
        window.__polywatch_polling = False;
    }

    async def run_investigation(override_slug: str = "") -> None {
        actual_slug = override_slug if override_slug else slug;
        phase = "active";
        active_tab = "overview";
        loading = True;
        is_running = True;
        error = "";
        elapsed = 0;
        result = None;
        window.__polywatch_start_time = Date.now();
        live_tree = [];
        live_status = "starting...";
        live_tool_calls = 0;
        live_llm_calls = 0;
        live_categories = [];
        live_artifacts = [];

        timer_id = setInterval(tick, 500);
        poll_id = setInterval(poll_progress, 2000);

        try {
            inv_goal = goal;
            if not inv_goal {
                inv_goal = "Investigate this Polymarket event for signs of insider trading, market manipulation, or informed trading ahead of news events.";
            }
            now_ts = str(Math.floor(Date.now() / 1000));
            await __doFuncFetch("start_investigation", {
                "market_id": actual_slug,
                "event_timestamp": now_ts,
                "goal": inv_goal
            });
        } except Exception as ex {
            msg = str(ex);
            if "UNAUTHORIZED" in msg { jacLogout(); navigate("/login"); }
            else { console.log("[INFO] start_investigation returned:", msg); }
        }
        loading = False;
    }

    async def handle_start(e: any) -> None {
        e.preventDefault();
        if not slug { error = "Please enter a Polymarket event slug."; return; }
        run_investigation(slug);
    }

    def handle_new() -> None {
        phase = "input";
        result = None;
        error = "";
        slug = "";
        goal = "";
        elapsed = 0;
        is_running = False;
        auto_started = False;
        navigate("/dashboard");
    }

    can with exit {
        if timer_id { clearInterval(timer_id); }
        if poll_id { clearInterval(poll_id); }
    }

    # ── Helper: render volume chart as inline SVG ──
    def render_volume_chart(daily_volume: list) -> JsxElement {
        if not daily_volume or len(daily_volume) == 0 {
            return <p className="text-muted-foreground text-sm">{"No volume data available."}</p>;
        }
        chart_w = 700;
        chart_h = 220;
        pad_l = 60;
        pad_r = 20;
        pad_t = 20;
        pad_b = 40;
        draw_w = chart_w - pad_l - pad_r;
        draw_h = chart_h - pad_t - pad_b;
        n = len(daily_volume);
        max_vol = 0;
        for i in range(n) {
            v = daily_volume[i]["volume_usdc"] or 0;
            if v > max_vol { max_vol = v; }
        }
        if max_vol == 0 { max_vol = 1; }
        bar_w = Math.max(4, Math.floor(draw_w / n) - 2);
        bars: list = [];
        for i in range(n) {
            d = daily_volume[i];
            v = d["volume_usdc"] or 0;
            is_abnormal = d["abnormal"] or False;
            bh = (v / max_vol) * draw_h;
            bx = pad_l + (i * (draw_w / n)) + 1;
            by = pad_t + draw_h - bh;
            fill = "#ef4444" if is_abnormal else "#3b82f6";
            bars.append(<rect key={str(i)} x={str(bx)} y={str(by)} width={str(bar_w)} height={str(Math.max(1, bh))} fill={fill} rx="2" opacity="0.85" />);
        }
        y_labels: list = [];
        for i in range(5) {
            val = max_vol * (1 - i / 4);
            yp = pad_t + (i / 4) * draw_h;
            label = "$" + str(Math.round(val));
            if val >= 1000 { label = "$" + str(Math.round(val / 1000)) + "K"; }
            y_labels.append(<text key={"yl" + str(i)} x={str(pad_l - 8)} y={str(yp + 4)} fill="#6b6b6b" fontSize="10" textAnchor="end">{label}</text>);
            y_labels.append(<line key={"yg" + str(i)} x1={str(pad_l)} y1={str(yp)} x2={str(chart_w - pad_r)} y2={str(yp)} stroke="#252525" strokeWidth="1" />);
        }
        return (
            <svg viewBox={"0 0 " + str(chart_w) + " " + str(chart_h)} className="volume-chart-svg">
                {y_labels}
                {bars}
                <line x1={str(pad_l)} y1={str(pad_t + draw_h)} x2={str(chart_w - pad_r)} y2={str(pad_t + draw_h)} stroke="#252525" strokeWidth="1" />
            </svg>
        );
    }

    # ── Helper: render price history chart as inline SVG ──
    def render_price_chart(price_history: list) -> JsxElement {
        if not price_history or len(price_history) == 0 {
            return <p className="text-muted-foreground text-sm">{"No price history data available."}</p>;
        }
        chart_w = 700;
        chart_h = 260;
        pad_l = 60;
        pad_r = 20;
        pad_t = 20;
        pad_b = 40;
        draw_w = chart_w - pad_l - pad_r;
        draw_h = chart_h - pad_t - pad_b;
        n = len(price_history);
        yes_points: list = [];
        no_points: list = [];
        min_p = 1.0;
        max_p = 0.0;
        for i in range(n) {
            yp = price_history[i]["price_yes"];
            np_val = price_history[i]["price_no"];
            if yp != None and yp != undefined {
                if yp < min_p { min_p = yp; }
                if yp > max_p { max_p = yp; }
            }
            if np_val != None and np_val != undefined {
                if np_val < min_p { min_p = np_val; }
                if np_val > max_p { max_p = np_val; }
            }
        }
        price_range = max_p - min_p;
        if price_range < 0.01 { price_range = 0.01; min_p = max_p - 0.01; }
        for i in range(n) {
            x = pad_l + (i / Math.max(n - 1, 1)) * draw_w;
            yp = price_history[i]["price_yes"];
            np_val = price_history[i]["price_no"];
            if yp != None and yp != undefined {
                y = pad_t + draw_h - ((yp - min_p) / price_range) * draw_h;
                yes_points.append(str(Math.round(x * 10) / 10) + "," + str(Math.round(y * 10) / 10));
            }
            if np_val != None and np_val != undefined {
                y = pad_t + draw_h - ((np_val - min_p) / price_range) * draw_h;
                no_points.append(str(Math.round(x * 10) / 10) + "," + str(Math.round(y * 10) / 10));
            }
        }
        yes_path = "M" + " L".join(yes_points) if len(yes_points) > 0 else "";
        no_path = "M" + " L".join(no_points) if len(no_points) > 0 else "";
        y_labels: list = [];
        for i in range(5) {
            val = max_p - (i / 4) * price_range;
            yp2 = pad_t + (i / 4) * draw_h;
            label = str(Math.round(val * 100)) + "%";
            y_labels.append(<text key={"yl" + str(i)} x={str(pad_l - 8)} y={str(yp2 + 4)} fill="#6b6b6b" fontSize="10" textAnchor="end">{label}</text>);
            y_labels.append(<line key={"yg" + str(i)} x1={str(pad_l)} y1={str(yp2)} x2={str(chart_w - pad_r)} y2={str(yp2)} stroke="#252525" strokeWidth="1" />);
        }
        return (
            <svg viewBox={"0 0 " + str(chart_w) + " " + str(chart_h)} className="price-chart-svg">
                {y_labels}
                <line x1={str(pad_l)} y1={str(pad_t + draw_h)} x2={str(chart_w - pad_r)} y2={str(pad_t + draw_h)} stroke="#252525" strokeWidth="1" />
                {yes_path and (
                    <path d={yes_path} fill="none" stroke="#34d399" strokeWidth="2" opacity="0.9" />
                )}
                {no_path and (
                    <path d={no_path} fill="none" stroke="#ef4444" strokeWidth="2" opacity="0.7" />
                )}
            </svg>
        );
    }

    # ── Helper: render graph-based investigation tree ──
    def render_graph_tree(tree: list) -> JsxElement {
        if not tree or len(tree) == 0 {
            return <p className="text-muted-foreground text-sm">{"No tree data available."}</p>;
        }
        n = len(tree);
        node_h = 56;
        node_w = 320;
        gap_y = 20;
        indent_x = 32;
        base_x = 40;
        svg_w = 700;
        svg_h = n * (node_h + gap_y) + 40;
        elements: list = [];
        for i in range(n) {
            nd = tree[i];
            depth = nd["depth"] or 0;
            cat = nd["category"] or "default";
            x_offset = base_x + depth * indent_x;
            y_pos = 20 + i * (node_h + gap_y);
            if i > 0 {
                prev_depth = tree[i - 1]["depth"] or 0;
                prev_x = base_x + prev_depth * indent_x;
                prev_y_bottom = 20 + (i - 1) * (node_h + gap_y) + node_h;
                conn_x1 = prev_x;
                conn_y1 = prev_y_bottom;
                conn_x2 = x_offset;
                conn_y2 = y_pos + node_h / 2;
                elements.append(
                    <path key={"conn" + str(i)}
                          d={"M" + str(conn_x1) + "," + str(conn_y1) + " L" + str(conn_x1) + "," + str(conn_y2) + " L" + str(conn_x2) + "," + str(conn_y2)}
                          fill="none" stroke="#3a3a3a" strokeWidth="2" />
                );
            }
            colors = {"market": "#3b82f6", "statistical": "#a855f7", "news": "#22c55e", "wallet": "#f59e0b", "network": "#ef4444", "default": "#6b6b6b"};
            c = colors[cat] if cat in colors else "#6b6b6b";
            is_active = nd["status"] == "active";
            elements.append(
                <g key={"node" + str(i)}>
                    <rect x={str(x_offset)} y={str(y_pos)} width={str(node_w)} height={str(node_h)}
                          rx="8" fill="#141414" stroke={c} strokeWidth={is_active and "2.5" or "1.5"} opacity="0.95" />
                    <circle cx={str(x_offset + 16)} cy={str(y_pos + node_h / 2)} r="5" fill={c} />
                    <text x={str(x_offset + 28)} y={str(y_pos + 20)} fill="#f5f0e8" fontSize="11" fontWeight="600">
                        {str(nd["hypothesis"] or nd["tool"] or "Node " + str(i))[:40]}
                    </text>
                    <text x={str(x_offset + 28)} y={str(y_pos + 38)} fill="#6b6b6b" fontSize="9" fontFamily="monospace">
                        {str(nd["tool"] or "") + "  D" + str(depth)}
                    </text>
                    <text x={str(x_offset + node_w - 10)} y={str(y_pos + 20)} fill={c} fontSize="9" textAnchor="end" fontWeight="700">
                        {str(nd["status"] or "")}
                    </text>
                </g>
            );
        }
        return (
            <div className="graph-tree-container">
                <svg viewBox={"0 0 " + str(svg_w) + " " + str(svg_h)} className="graph-tree-svg" style={{"width": "100%", "height": str(svg_h) + "px"}}>
                    {elements}
                </svg>
            </div>
        );
    }

    # Derive display data: use result when available, live data during run
    disp_tree = result["tree"] if result and result["tree"] else live_tree;
    disp_artifacts = result["artifacts"] if result and result["artifacts"] else live_artifacts;
    disp_tool_calls = result["total_tool_calls"] if result else live_tool_calls;
    disp_llm_calls = result["total_llm_calls"] if result else live_llm_calls;
    disp_categories = result["categories"] if result and result["categories"] else live_categories;
    disp_news = result["news_articles"] if result and result["news_articles"] else extract_live_news(disp_artifacts);

    # ---- INPUT PHASE ----
    if phase == "input" {
        return (
            <div className="page">
                <div className="page-container">
                    <div className="page-header">
                        <div>
                            <h1>Investigation Engine</h1>
                            <p className="text-sm text-muted-foreground">
                                {"Analyze Polymarket events with Tree of Thought reasoning"}
                            </p>
                        </div>
                        <button className="btn btn-ghost" onClick={handle_logout}>{"Sign out"}</button>
                    </div>
                    <div className="card investigation-form-card">
                        <h2>Start Investigation</h2>
                        <p className="text-sm text-muted-foreground mb-2">
                            {"Enter a Polymarket event slug and optional goal to begin."}
                        </p>
                        <form onSubmit={handle_start} className="investigation-form">
                            <div>
                                <label className="label">Polymarket Event Slug</label>
                                <input className="input" type="text" value={slug} onChange={on_slug_change}
                                       placeholder="e.g. us-x-iran-ceasefire-by" disabled={loading} />
                            </div>
                            <div>
                                <label className="label">Investigation Goal (optional)</label>
                                <textarea className="investigation-textarea" value={goal} onChange={on_goal_change}
                                          placeholder="e.g. Investigate for signs of insider trading ahead of news events..."
                                          disabled={loading} />
                            </div>
                            <button className="btn btn-primary w-full h-12 mt-1" type="submit" disabled={loading or not slug}>
                                {"Start Investigation"}
                            </button>
                        </form>
                        {error and (<div className="error-box mt-3">{error}</div>)}
                    </div>
                    {prev_investigations and len(prev_investigations) > 0 and (
                        <div className="card p-6 mb-4">
                            <h2 className="text-base font-semibold text-primary mb-3">{"Previous Investigations"}</h2>
                            <div className="prev-investigation-list">
                                {[
                                    <div key={str(pidx)} className="prev-investigation-item" onClick={lambda: load_prev_investigation(prev_investigations[pidx]["filename"])}>
                                        <div className="prev-inv-title">{str(prev_investigations[pidx]["market_title"] or prev_investigations[pidx]["market_id"] or "Unknown")}</div>
                                        <div className="prev-inv-meta">
                                            <span className={"prev-inv-confidence prev-inv-confidence-" + str(prev_investigations[pidx]["confidence"] or "").toLowerCase()}>
                                                {str(prev_investigations[pidx]["confidence"] or "N/A")}
                                            </span>
                                            <span className="text-muted-foreground text-xs">{str(prev_investigations[pidx]["total_tool_calls"] or 0) + " tools"}</span>
                                            <span className="text-muted-foreground text-xs">{str(prev_investigations[pidx]["elapsed"] or 0) + "s"}</span>
                                        </div>
                                    </div>
                                    for pidx in range(len(prev_investigations))
                                ]}
                            </div>
                        </div>
                    )}
                </div>
            </div>
        );
    }

    # ---- ACTIVE PHASE (running + results, with persistent tabs) ----
    return (
        <div className="page">
            <div className="page-container investigation-results-container">
                <div className="inv-header">
                    <div className="inv-header-left">
                        <h1 className="inv-title">{str(result["market_title"] or result["market_id"] or slug or "") if result else str(slug or "Investigation")}</h1>
                        <div className="inv-header-stats">
                            {is_running and (
                                <span className="inv-status-badge inv-status-running">
                                    <span className="inv-status-dot" />
                                    {str(elapsed) + "s | " + get_tool_description(live_status)}
                                </span>
                            )}
                            {not is_running and result and (
                                <span className="inv-status-badge inv-status-complete">{"Complete"}</span>
                            )}
                            <span className="inv-stat-pill">{str(disp_tool_calls) + " tools"}</span>
                            <span className="inv-stat-pill">{str(disp_llm_calls) + " LLM"}</span>
                            {result and result["confidence"] and (
                                <span className={"inv-confidence-badge inv-confidence-" + str(result["confidence"] or "").toLowerCase()}>
                                    {str(result["confidence"] or "")}
                                </span>
                            )}
                        </div>
                    </div>
                    <div className="inv-header-right">
                        {is_running and (
                            <button className="btn inv-stop-btn" onClick={end_investigation}>{"Stop"}</button>
                        )}
                        <button className="btn btn-ghost" onClick={handle_new}>{"Back"}</button>
                    </div>
                </div>

                <div className="inv-tab-bar">
                    <button className={"inv-tab" + (" inv-tab-active" if active_tab == "overview" else "")} onClick={lambda: switch_tab("overview")}>{"Overview"}</button>
                    <button className={"inv-tab" + (" inv-tab-active" if active_tab == "report" else "")} onClick={lambda: switch_tab("report")}>{"Report"}</button>
                    <button className={"inv-tab" + (" inv-tab-active" if active_tab == "evidence" else "")} onClick={lambda: switch_tab("evidence")}>
                        {"Evidence" + (" (" + str(len(disp_artifacts)) + ")" if len(disp_artifacts) > 0 else "")}
                    </button>
                    <button className={"inv-tab" + (" inv-tab-active" if active_tab == "news" else "")} onClick={lambda: switch_tab("news")}>
                        {"News" + (" (" + str(len(disp_news)) + ")" if len(disp_news) > 0 else "")}
                    </button>
                    <button className={"inv-tab" + (" inv-tab-active" if active_tab == "tree" else "")} onClick={lambda: switch_tab("tree")}>
                        {"Tree" + (" (" + str(len(disp_tree)) + ")" if len(disp_tree) > 0 else "")}
                    </button>
                    <button className={"inv-tab" + (" inv-tab-active" if active_tab == "previous" else "")} onClick={lambda: switch_tab("previous")}>{"Previous"}</button>
                </div>

                {active_tab == "overview" and (
                    <div className="inv-tab-panel">
                        <div className="overview-stats-row">
                            <div className="results-stat-card">
                                <div className="results-stat-label">Tool Calls</div>
                                <div className="results-stat-value">{str(disp_tool_calls)}</div>
                            </div>
                            <div className="results-stat-card">
                                <div className="results-stat-label">LLM Calls</div>
                                <div className="results-stat-value">{str(disp_llm_calls)}</div>
                            </div>
                            <div className="results-stat-card">
                                <div className="results-stat-label">Evidence</div>
                                <div className="results-stat-value">{str(len(disp_artifacts))}</div>
                            </div>
                            <div className="results-stat-card">
                                <div className="results-stat-label">Articles</div>
                                <div className="results-stat-value">{str(len(disp_news))}</div>
                            </div>
                            <div className="results-stat-card">
                                <div className="results-stat-label">Nodes</div>
                                <div className="results-stat-value">{str(len(disp_tree))}</div>
                            </div>
                            <div className="results-stat-card">
                                <div className="results-stat-label">Duration</div>
                                <div className="results-stat-value">{str(result["elapsed"] or 0) + "s" if result else str(elapsed) + "s"}</div>
                            </div>
                        </div>

                        {is_running and (
                            <div className="card p-4 mb-4" style={{"textAlign": "center"}}>
                                <div className="loading-spinner" style={{"margin": "0 auto 0.5rem"}} />
                                <p className="text-sm" style={{"color": "var(--color-primary)"}}>{get_stable_funny_phrase(live_status)}</p>
                                <p className="text-xs text-muted-foreground" style={{"marginTop": "0.25rem", "fontFamily": "monospace"}}>
                                    {get_tool_name_from_status(live_status)}
                                </p>
                            </div>
                        )}

                        <div className="overview-two-col">
                            <div className="card overview-section-card">
                                <h3 className="overview-section-title">Confidence Computation</h3>
                                <div className="overview-confidence-display">
                                    <span className={"overview-confidence-level overview-confidence-" + str(result["confidence"] or "").toLowerCase() if result else "overview-confidence-level"}>
                                        {str(result["confidence"] or "Pending") if result else "Pending"}
                                    </span>
                                </div>
                                <div className="overview-confidence-details">
                                    <div className="overview-detail-row">
                                        <span className="overview-detail-label">Evidence Artifacts</span>
                                        <span className="overview-detail-value">{str(len(disp_artifacts))}</span>
                                    </div>
                                    <div className="overview-detail-row">
                                        <span className="overview-detail-label">Categories Covered</span>
                                        <span className="overview-detail-value">{str(len(disp_categories))}</span>
                                    </div>
                                    <div className="overview-detail-row">
                                        <span className="overview-detail-label">Tree Depth</span>
                                        <span className="overview-detail-value">{str(disp_tree[len(disp_tree) - 1]["depth"] or 0) if len(disp_tree) > 0 else "0"}</span>
                                    </div>
                                    {disp_categories and len(disp_categories) > 0 and (
                                        <div className="overview-detail-row">
                                            <span className="overview-detail-label">Categories</span>
                                            <span className="overview-detail-value text-xs">{", ".join(disp_categories)}</span>
                                        </div>
                                    )}
                                </div>
                            </div>
                            <div className="card overview-section-card">
                                <h3 className="overview-section-title">Investigation Steps</h3>
                                {len(disp_tree) > 0 and (
                                    <div className="overview-steps-list">
                                        {[
                                            <div key={str(sidx)} className="overview-step-item">
                                                <span className={"overview-step-dot overview-step-" + str(disp_tree[sidx]["status"] or "closed")} />
                                                <div className="overview-step-content">
                                                    <span className="overview-step-text">{str(disp_tree[sidx]["hypothesis"] or disp_tree[sidx]["tool"] or "Step " + str(sidx + 1))}</span>
                                                    {disp_tree[sidx]["tool"] and (
                                                        <span className="overview-step-tool">{str(disp_tree[sidx]["tool"])}</span>
                                                    )}
                                                </div>
                                            </div>
                                            for sidx in range(len(disp_tree))
                                        ]}
                                    </div>
                                )}
                                {len(disp_tree) == 0 and (
                                    <p className="text-sm text-muted-foreground">{"Steps will appear as the investigation runs..."}</p>
                                )}
                            </div>
                        </div>

                        {result and result["price_history"] and len(result["price_history"]) > 0 and (
                            <div className="card p-6 mb-4">
                                <h2 className="text-base font-semibold text-primary mb-1">Price History</h2>
                                <div className="chart-legend mb-3">
                                    <span className="chart-legend-item"><span className="chart-legend-line" style={{"background": "#34d399"}} />{"YES Price"}</span>
                                    <span className="chart-legend-item"><span className="chart-legend-line" style={{"background": "#ef4444"}} />{"NO Price"}</span>
                                </div>
                                <div className="chart-container">
                                    {render_price_chart(result["price_history"])}
                                </div>
                            </div>
                        )}

                        {result and result["daily_volume"] and len(result["daily_volume"]) > 0 and (
                            <div className="card p-6 mb-4">
                                <h2 className="text-base font-semibold text-primary mb-1">Daily Trading Volume</h2>
                                <div className="chart-legend mb-3">
                                    <span className="chart-legend-item"><span className="chart-legend-swatch" style={{"background": "#3b82f6"}} />{"Normal"}</span>
                                    <span className="chart-legend-item"><span className="chart-legend-swatch" style={{"background": "#ef4444"}} />{"Abnormal"}</span>
                                </div>
                                <div className="chart-container">
                                    {render_volume_chart(result["daily_volume"])}
                                </div>
                            </div>
                        )}

                        {not is_running and (not result or (not result["price_history"] and not result["daily_volume"])) and (
                            <div className="card p-6 mb-4" style={{"textAlign": "center"}}>
                                <p className="text-muted-foreground text-sm">{"Charts will appear when the investigation completes."}</p>
                            </div>
                        )}
                    </div>
                )}

                {active_tab == "report" and (
                    <div className="inv-tab-panel">
                        {result and result["summary"] and (
                            <div className="card investigation-summary-card">
                                <div className="report-text text-sm text-foreground" dangerouslySetInnerHTML={{"__html": render_report_with_citations(str(result["summary"] or ""))}} />
                            </div>
                        )}
                        {(not result or not result["summary"]) and (
                            <div className="card p-6 mb-4" style={{"textAlign": "center"}}>
                                {is_running and (<div className="loading-spinner" style={{"margin": "0 auto 0.75rem"}} />)}
                                <p className="text-muted-foreground text-sm">{is_running and "Report will appear when the investigation completes..." or "No report available."}</p>
                            </div>
                        )}
                    </div>
                )}

                {active_tab == "news" and (
                    <div className="inv-tab-panel">
                        {len(disp_news) > 0 and (
                            <div className="card p-6 mb-4">
                                <h2 className="text-base font-semibold text-primary mb-3">{"News Articles (" + str(len(disp_news)) + ")"}</h2>
                                <div className="news-article-list">
                                    {[
                                        <div key={str(nidx)} className="news-article-item">
                                            {disp_news[nidx]["url"] and (
                                                <a href={str(disp_news[nidx]["url"])} target="_blank" rel="noopener noreferrer" className="news-article-title">
                                                    {str(disp_news[nidx]["title"] or "Untitled")}
                                                    <span className="news-external-icon">{" \u2197"}</span>
                                                </a>
                                            )}
                                            {not disp_news[nidx]["url"] and (
                                                <span className="news-article-title-nolink">{str(disp_news[nidx]["title"] or "Untitled")}</span>
                                            )}
                                            <div className="news-article-meta">
                                                <span className="news-source">{str(disp_news[nidx]["source"] or "")}</span>
                                                <span className="news-date">{format_timestamp(disp_news[nidx]["published_at"])}</span>
                                            </div>
                                            {disp_news[nidx]["description"] and (
                                                <p className="news-description">{str(disp_news[nidx]["description"])[:200]}</p>
                                            )}
                                        </div>
                                        for nidx in range(len(disp_news))
                                    ]}
                                </div>
                            </div>
                        )}
                        {len(disp_news) == 0 and (
                            <div className="card p-6 mb-4" style={{"textAlign": "center"}}>
                                {is_running and (<div className="loading-spinner" style={{"margin": "0 auto 0.75rem"}} />)}
                                <p className="text-muted-foreground text-sm">{is_running and "News articles will appear as they are found..." or "No news articles found."}</p>
                            </div>
                        )}
                    </div>
                )}

                {active_tab == "evidence" and (
                    <div className="inv-tab-panel">
                        {len(disp_artifacts) > 0 and (
                            <div className="card p-6 mb-4">
                                <h2 className="text-base font-semibold text-primary mb-3">{"Evidence Collected (" + str(len(disp_artifacts)) + " artifacts)"}</h2>
                                <div className="artifact-list">
                                    {[
                                        <div key={str(aidx)} className={"artifact-item artifact-cat-" + (disp_artifacts[aidx]["category"] or "default")} onClick={lambda: open_artifact(disp_artifacts[aidx])}>
                                            <span className="artifact-id">{str(disp_artifacts[aidx]["id"] or "")}</span>
                                            <span className="artifact-tool">{str(disp_artifacts[aidx]["tool"] or "")}</span>
                                            <span className="artifact-summary">{str(disp_artifacts[aidx]["summary"] or "")[:120]}</span>
                                        </div>
                                        for aidx in range(len(disp_artifacts))
                                    ]}
                                </div>
                            </div>
                        )}
                        {len(disp_artifacts) == 0 and (
                            <div className="card p-6 mb-4" style={{"textAlign": "center"}}>
                                {is_running and (<div className="loading-spinner" style={{"margin": "0 auto 0.75rem"}} />)}
                                <p className="text-muted-foreground text-sm">{is_running and "Evidence is being collected..." or "No evidence available."}</p>
                            </div>
                        )}
                    </div>
                )}

                {active_tab == "tree" and (
                    <div className="inv-tab-panel">
                        {len(disp_tree) > 0 and (
                            <div className="card p-6 mb-4">
                                <div className="tree-header-row">
                                    <h2 className="text-base font-semibold text-primary">{"Investigation Tree \u2014 " + str(len(disp_tree)) + " nodes"}</h2>
                                    <div style={{"display": "flex", "alignItems": "center", "gap": "0.75rem"}}>
                                        {is_running and (
                                            <label className="tree-autoscroll-toggle">
                                                <input type="checkbox" checked={auto_scroll} onChange={toggle_auto_scroll} />
                                                <span className="text-xs text-muted-foreground">{"Auto-scroll"}</span>
                                            </label>
                                        )}
                                        <div className="tree-view-toggle">
                                            <button className={"tree-toggle-btn" + (" tree-toggle-active" if tree_view_mode == "list" else "")} onClick={lambda: set_tree_view("list")}>{"List"}</button>
                                            <button className={"tree-toggle-btn" + (" tree-toggle-active" if tree_view_mode == "graph" else "")} onClick={lambda: set_tree_view("graph")}>{"Graph"}</button>
                                        </div>
                                    </div>
                                </div>
                                <div className="tree-legend" style={{"marginTop": "0.75rem"}}>
                                    <span className="tree-legend-dot tree-badge-market" /><span className="tree-legend-label">Market</span>
                                    <span className="tree-legend-dot tree-badge-statistical" /><span className="tree-legend-label">Statistical</span>
                                    <span className="tree-legend-dot tree-badge-news" /><span className="tree-legend-label">News</span>
                                    <span className="tree-legend-dot tree-badge-wallet" /><span className="tree-legend-label">Wallet</span>
                                    <span className="tree-legend-dot tree-badge-network" /><span className="tree-legend-label">Network</span>
                                </div>
                                {tree_view_mode == "list" and (
                                    <div className="tree-viz-list" id="tree-scroll-container">
                                        {[
                                            <div key={str(idx)}
                                                 className={"tree-node-card" + (" tree-active" if disp_tree[idx]["status"] == "active" and idx == find_active_node_idx(disp_tree) else " tree-closed") + " tree-border-" + (disp_tree[idx]["category"] or "default")}
                                                 style={{"marginLeft": str((disp_tree[idx]["depth"] or 0) * 24) + "px"}}>
                                                <div className="tree-node-title">
                                                    {disp_tree[idx]["status"] == "active" and idx == find_active_node_idx(disp_tree) and (
                                                        <span className="tree-active-dot" />
                                                    )}
                                                    {disp_tree[idx]["hypothesis"] or ("Root: " + str(disp_tree[idx]["tool"] or "Initializing...")) if disp_tree[idx]["depth"] == 0 else (disp_tree[idx]["hypothesis"] or str(disp_tree[idx]["tool"] or "..."))}
                                                </div>
                                                <div className="tree-node-meta">
                                                    {disp_tree[idx]["tool"] and (
                                                        <span className={"tree-tool-badge tree-badge-" + (disp_tree[idx]["category"] or "default")}>{str(disp_tree[idx]["tool"] or "")}</span>
                                                    )}
                                                    <span className="tree-depth-badge">{"D" + str(disp_tree[idx]["depth"] or 0)}</span>
                                                    {disp_tree[idx]["status"] == "active" and idx == find_active_node_idx(disp_tree) and (
                                                        <span className="tree-tool-badge" style={{"background": "rgba(239,68,68,0.3)", "color": "#f87171"}}>ACTIVE</span>
                                                    )}
                                                </div>
                                                {disp_tree[idx]["question"] and (
                                                    <div className="tree-section">
                                                        <div className="tree-section-label">{is_running and disp_tree[idx]["status"] == "active" and "Unanswered Question" or "Question Investigated"}</div>
                                                        <div className="tree-section-text">{str(disp_tree[idx]["question"] or "")}</div>
                                                    </div>
                                                )}
                                                {disp_tree[idx]["result"] and (
                                                    <div className="tree-node-result">{str(disp_tree[idx]["result"] or "")}</div>
                                                )}
                                            </div>
                                            for idx in range(len(disp_tree))
                                        ]}
                                    </div>
                                )}
                                {tree_view_mode == "graph" and (
                                    render_graph_tree(disp_tree)
                                )}
                            </div>
                        )}
                        {len(disp_tree) == 0 and (
                            <div className="card p-6 mb-4" style={{"textAlign": "center"}}>
                                {is_running and (<div className="loading-spinner" style={{"margin": "0 auto 0.75rem"}} />)}
                                <p className="text-muted-foreground text-sm">{is_running and "Building investigation tree..." or "No tree data available."}</p>
                            </div>
                        )}
                    </div>
                )}

                {active_tab == "previous" and (
                    <div className="inv-tab-panel">
                        {prev_investigations and len(prev_investigations) > 0 and (
                            <div className="card p-6 mb-4">
                                <h2 className="text-base font-semibold text-primary mb-3">{"Previous Investigations"}</h2>
                                <div className="prev-investigation-list">
                                    {[
                                        <div key={str(pidx)} className="prev-investigation-item" onClick={lambda: load_prev_investigation(prev_investigations[pidx]["filename"])}>
                                            <div className="prev-inv-title">{str(prev_investigations[pidx]["market_title"] or prev_investigations[pidx]["market_id"] or "Unknown")}</div>
                                            <div className="prev-inv-meta">
                                                <span className={"prev-inv-confidence prev-inv-confidence-" + str(prev_investigations[pidx]["confidence"] or "").toLowerCase()}>
                                                    {str(prev_investigations[pidx]["confidence"] or "N/A")}
                                                </span>
                                                <span className="text-muted-foreground text-xs">{str(prev_investigations[pidx]["total_tool_calls"] or 0) + " tools"}</span>
                                                <span className="text-muted-foreground text-xs">{str(prev_investigations[pidx]["elapsed"] or 0) + "s"}</span>
                                            </div>
                                        </div>
                                        for pidx in range(len(prev_investigations))
                                    ]}
                                </div>
                            </div>
                        )}
                        {(not prev_investigations or len(prev_investigations) == 0) and (
                            <div className="card p-6 mb-4" style={{"textAlign": "center"}}>
                                <p className="text-muted-foreground text-sm">{"No previous investigations found."}</p>
                            </div>
                        )}
                    </div>
                )}

                {selected_artifact and (
                    <div className="artifact-modal-overlay" onClick={close_artifact}>
                        <div className="artifact-modal" onClick={lambda e: e.stopPropagation()}>
                            <div className="artifact-modal-header">
                                <h3>{str(selected_artifact["tool"] or "Artifact")}</h3>
                                <button className="btn btn-ghost" onClick={close_artifact}>{"X"}</button>
                            </div>
                            <div className="artifact-modal-summary">
                                <div className="tree-section-label">Summary</div>
                                {str(selected_artifact["summary"] or "")}
                            </div>
                            <div className="artifact-modal-data">
                                <div className="tree-section-label">Full Data</div>
                                <pre className="whitespace-pre-wrap text-xs">{JSON.stringify(selected_artifact["data"], null, 2) if selected_artifact["data"] else "Data not available."}</pre>
                            </div>
                        </div>
                    </div>
                )}
            </div>
        </div>
    );
}
