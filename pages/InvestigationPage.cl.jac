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
    has result: any = None;
    has auto_started: bool = False;

    navigate = useNavigate();

    # Auto-start if slug is in URL params (runs only once)
    if not auto_started and phase == "input" and not loading {
        auto_started = True;
        search_str = window.location.search;
        if search_str and search_str.indexOf("slug=") >= 0 {
            slug_start = search_str.indexOf("slug=") + 5;
            rest = search_str.substring(slug_start);
            amp_idx = rest.indexOf("&");
            if amp_idx >= 0 {
                rest = rest.substring(0, amp_idx);
            }
            slug = decodeURIComponent(rest);
            run_investigation();
        }
    }

    def handle_logout() -> None {
        jacLogout();
        navigate("/login");
    }

    def on_slug_change(e: any) -> None {
        slug = e.target.value;
    }

    def on_goal_change(e: any) -> None {
        goal = e.target.value;
    }

    def tick() -> None {
        elapsed = elapsed + 1;
    }

    async def run_investigation() -> None {
        phase = "loading";
        loading = True;
        error = "";
        elapsed = 0;

        timer_id = setInterval(tick, 1000);

        try {
            inv_goal = goal;
            if not inv_goal {
                inv_goal = "Investigate this Polymarket event for signs of insider trading, market manipulation, or informed trading ahead of news events.";
            }
            now_ts = str(Math.floor(Date.now() / 1000));
            res = await __doFuncFetch("start_investigation", {
                "market_id": slug,
                "event_timestamp": now_ts,
                "goal": inv_goal,
                "max_depth": 4,
                "max_children": 4
            });

            if timer_id {
                clearInterval(timer_id);
            }

            if res and res["error"] {
                error = str(res["error"]);
                phase = "input";
            } else {
                result = res;
                phase = "results";
            }
        } except Exception as ex {
            if timer_id {
                clearInterval(timer_id);
            }
            msg = str(ex);
            if "UNAUTHORIZED" in msg {
                jacLogout();
                navigate("/login");
            } else {
                error = "Investigation failed: " + msg;
                phase = "input";
            }
        }
        loading = False;
    }

    async def handle_start(e: any) -> None {
        e.preventDefault();
        if not slug {
            error = "Please enter a Polymarket event slug.";
            return;
        }
        run_investigation();
    }

    def handle_new() -> None {
        phase = "input";
        result = None;
        error = "";
        slug = "";
        goal = "";
        elapsed = 0;
        auto_started = False;
        navigate("/dashboard");
    }

    can with exit {
        if timer_id {
            clearInterval(timer_id);
        }
    }

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
                        <button className="btn btn-ghost" onClick={handle_logout}>
                            {"Sign out"}
                        </button>
                    </div>

                    <div className="card investigation-form-card">
                        <h2>Start Investigation</h2>
                        <p className="text-sm text-muted-foreground mb-2">
                            {"Enter a Polymarket event slug and optional goal to begin."}
                        </p>
                        <form onSubmit={handle_start} className="investigation-form">
                            <div>
                                <label className="label">Polymarket Event Slug</label>
                                <input
                                    className="input"
                                    type="text"
                                    value={slug}
                                    onChange={on_slug_change}
                                    placeholder="e.g. us-x-iran-ceasefire-by"
                                    disabled={loading}
                                />
                            </div>
                            <div>
                                <label className="label">Investigation Goal (optional)</label>
                                <textarea
                                    className="investigation-textarea"
                                    value={goal}
                                    onChange={on_goal_change}
                                    placeholder="e.g. Investigate for signs of insider trading ahead of news events..."
                                    disabled={loading}
                                />
                            </div>
                            <button
                                className="btn btn-primary w-full h-12 mt-1"
                                type="submit"
                                disabled={loading or not slug}
                            >
                                {"Start Investigation"}
                            </button>
                        </form>
                        {error and (
                            <div className="error-box mt-3">{error}</div>
                        )}
                    </div>
                </div>
            </div>
        );
    }

    # ---- LOADING PHASE ----
    if phase == "loading" {
        progress_pct = elapsed * 1.5;
        if progress_pct > 95 {
            progress_pct = 95;
        }

        return (
            <div className="page">
                <div className="page-container">
                    <div className="card investigation-loading-card">
                        <div className="loading-spinner" />
                        <h2>Investigation in Progress</h2>
                        <p className="text-muted-foreground">
                            {"Exploring hypothesis branches... " + str(elapsed) + "s elapsed"}
                        </p>
                        <div className="loading-progress-bar">
                            <div
                                className="loading-progress-fill"
                                style={{"width": str(progress_pct) + "%"}}
                            />
                        </div>
                        <div className="loading-steps">
                            <p>{"Fetching event data from Polymarket"}</p>
                            <p>{"Building investigation tree with DFS"}</p>
                            <p>{"Evaluating hypotheses across branches"}</p>
                            <p>{"Generating final summary"}</p>
                        </div>
                    </div>
                </div>
            </div>
        );
    }

    # ---- RESULTS PHASE ----
    return (
        <div className="page">
            <div className="page-container investigation-results-container">
                <div className="page-header">
                    <div>
                        <h1>Investigation Complete</h1>
                        <p className="text-sm text-muted-foreground">
                            {"Market: " + str(result["market_id"] or "") + " | Confidence: " + str(result["confidence"] or "N/A") + " | " + str(result["elapsed"] or 0) + "s"}
                        </p>
                    </div>
                    <button className="btn" onClick={handle_new}>
                        {"Back to Dashboard"}
                    </button>
                </div>

                <div className="card investigation-summary-card">
                    <h2>Investigation Report</h2>
                    <pre className="whitespace-pre-wrap text-sm text-foreground">{str(result["summary"] or "")}</pre>
                    <div className="investigation-stats">
                        <span>{"Tool Calls: " + str(result["total_tool_calls"] or 0)}</span>
                        <span>{"LLM Calls: " + str(result["total_llm_calls"] or 0)}</span>
                        <span>{"Evidence: " + str(result["promoted_count"] or 0) + "/" + str(result["evidence_count"] or 0) + " promoted"}</span>
                        <span>{"Categories: " + str(result["categories"] or [])}</span>
                    </div>
                </div>
            </div>
        </div>
    );
}
