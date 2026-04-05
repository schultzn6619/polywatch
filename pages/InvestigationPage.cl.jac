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

    navigate = useNavigate();

    # Expose citation click handler on window
    window.__polywatch_open_cite = lambda aid: handle_citation_click(aid);

    # Auto-start if slug is in URL params (runs only once)
    if not auto_started and phase == "input" and not loading {
        auto_started = True;
        full_url = String(window.location.href);
        search_part = String(window.location.search);
        console.log("[DEBUG] href:", full_url);
        console.log("[DEBUG] search:", search_part);

        # Try search first (has ?slug=...), then fall back to href
        src = search_part if search_part and search_part.length > 1 else full_url;
        idx = src.indexOf("slug=");
        console.log("[DEBUG] src:", src, "idx:", idx);

        if idx >= 0 {
            rest = src.substring(idx + 5);
            amp = rest.indexOf("&");
            if amp >= 0 {
                rest = rest.substring(0, amp);
            }
            hash_pos = rest.indexOf("#");
            if hash_pos >= 0 {
                rest = rest.substring(0, hash_pos);
            }
            parsed_slug = decodeURIComponent(rest);
            console.log("[DEBUG] parsed_slug:", parsed_slug);
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

    def on_slug_change(e: any) -> None {
        slug = e.target.value;
    }

    def on_goal_change(e: any) -> None {
        goal = e.target.value;
    }

    def tick() -> None {
        st = window.__polywatch_start_time;
        if st and st > 0 {
            elapsed = Math.floor((Date.now() - st) / 1000);
        }
    }

    def open_artifact(art: any) -> None {
        selected_artifact = art;
    }

    def close_artifact() -> None {
        selected_artifact = None;
    }

    def toggle_auto_scroll() -> None {
        auto_scroll = not auto_scroll;
    }

    async def end_investigation() -> None {
        try {
            await __doFuncFetch("stop_investigation", {});
        } except Exception as e {
            console.log("[STOP] Error:", e);
        }
    }

    def find_artifact_by_id(aid: str, artifacts: list) -> any {
        for i in range(len(artifacts)) {
            if artifacts[i]["id"] == aid {
                return artifacts[i];
            }
        }
        return None;
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
        # Escape HTML
        html = html.split("&").join("&amp;");
        html = html.split("<").join("&lt;");
        html = html.split(">").join("&gt;");
        # Phase 1: Replace A## with unique placeholders (longest first to avoid A1 matching inside A10)
        for i in range(50, 0, -1) {
            aid = "A" + str(i);
            placeholder = "@@CITE_" + str(i) + "@@";
            if html.indexOf(aid) >= 0 {
                html = html.split(aid).join(placeholder);
            }
        }
        # Phase 2: Replace placeholders with clickable HTML
        for i in range(1, 51) {
            aid = "A" + str(i);
            placeholder = "@@CITE_" + str(i) + "@@";
            if html.indexOf(placeholder) >= 0 {
                html = html.split(placeholder).join("<span class='citation-link' onclick='window.__polywatch_open_cite(\"" + aid + "\")'>" + aid + "</span>");
            }
        }
        html = html.split("\n").join("<br/>");
        return html;
    }

    def find_active_node_idx(tree: list) -> int {
        # Find the LAST node with status "active" — that's the one being worked on
        last_active = -1;
        for i in range(len(tree)) {
            if tree[i]["status"] == "active" {
                last_active = i;
            }
        }
        return last_active;
    }

    async def poll_progress() -> None {
        try {
            prog = await __doFuncFetch("get_investigation_progress", {});
            if prog {
                if prog["tree"] {
                    live_tree = prog["tree"];
                }
                live_status = prog["status"] or "";
                live_tool_calls = prog["total_tool_calls"] or 0;
                live_llm_calls = prog["total_llm_calls"] or 0;
                if prog["categories"] {
                    live_categories = prog["categories"];
                }
                if prog["artifacts"] {
                    live_artifacts = prog["artifacts"];
                    window.__polywatch_artifacts = prog["artifacts"];
                }
                # Auto-scroll tree to bottom
                if auto_scroll {
                    scroll_el = document.getElementById("tree-scroll-container");
                    if scroll_el {
                        scroll_el.scrollTop = scroll_el.scrollHeight;
                    }
                }
                # Check if investigation is complete
                if prog["status"] == "complete" and prog["result"] {
                    if timer_id { clearInterval(timer_id); }
                    if poll_id { clearInterval(poll_id); }
                    result = prog["result"];
                    window.__polywatch_artifacts = prog["result"]["artifacts"] or [];
                    loading = False;
                    phase = "results";
                }
                if prog["status"] and prog["status"].startsWith("error") {
                    if timer_id { clearInterval(timer_id); }
                    if poll_id { clearInterval(poll_id); }
                    error = prog["status"];
                    loading = False;
                    phase = "input";
                }
            }
        } except Exception as e {
            console.log("[POLL ERROR]", e);
        }
    }

    async def run_investigation(override_slug: str = "") -> None {
        actual_slug = override_slug if override_slug else slug;
        console.log("[DEBUG] run_investigation actual_slug:", actual_slug);

        phase = "loading";
        loading = True;
        error = "";
        elapsed = 0;
        window.__polywatch_start_time = Date.now();
        live_tree = [];
        live_status = "starting...";
        live_tool_calls = 0;
        live_llm_calls = 0;
        live_categories = [];

        timer_id = setInterval(tick, 500);
        poll_id = setInterval(poll_progress, 2000);

        try {
            inv_goal = goal;
            if not inv_goal {
                inv_goal = "Investigate this Polymarket event for signs of insider trading, market manipulation, or informed trading ahead of news events.";
            }
            now_ts = str(Math.floor(Date.now() / 1000));
            # Fire and forget — investigation runs in background thread
            await __doFuncFetch("start_investigation", {
                "market_id": actual_slug,
                "event_timestamp": now_ts,
                "goal": inv_goal
            });
            # Don't set results here — polling will detect completion
        } except Exception as ex {
            msg = str(ex);
            if "UNAUTHORIZED" in msg {
                jacLogout();
                navigate("/login");
            } else {
                # Non-fatal — the investigation may have started anyway
                console.log("[INFO] start_investigation returned:", msg);
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
        run_investigation(slug);
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
                            {str(elapsed) + "s elapsed | " + str(live_tool_calls) + " tools | " + str(live_llm_calls) + " LLM calls"}
                        </p>
                        <p className="text-sm" style={{"color": "var(--color-primary)", "marginTop": "0.25rem"}}>
                            {live_status or "starting..."}
                        </p>
                        {live_categories and len(live_categories) > 0 and (
                            <p className="text-sm text-muted-foreground" style={{"marginTop": "0.25rem"}}>
                                {"Categories: " + ", ".join(live_categories)}
                            </p>
                        )}
                        <button className="btn" style={{"marginTop": "0.75rem", "background": "rgba(239,68,68,0.15)", "color": "#f87171", "border": "1px solid rgba(239,68,68,0.3)"}} onClick={end_investigation}>
                            {"End Investigation Early"}
                        </button>
                    </div>

                    {live_tree and len(live_tree) > 0 and (
                        <div className="card p-6 mb-4">
                            <h2 className="text-base font-semibold text-primary mb-3">{"Live Investigation Tree (" + str(len(live_tree)) + " nodes)"}</h2>
                            <div className="tree-legend">
                                <span className="tree-legend-dot tree-badge-market" /><span className="tree-legend-label">Market</span>
                                <span className="tree-legend-dot tree-badge-statistical" /><span className="tree-legend-label">Statistical</span>
                                <span className="tree-legend-dot tree-badge-news" /><span className="tree-legend-label">News</span>
                                <span className="tree-legend-dot tree-badge-wallet" /><span className="tree-legend-label">Wallet</span>
                                <span className="tree-legend-dot tree-badge-network" /><span className="tree-legend-label">Network</span>
                            </div>
                            <div className="tree-scroll-controls">
                                <label className="tree-autoscroll-toggle">
                                    <input type="checkbox" checked={auto_scroll} onChange={toggle_auto_scroll} />
                                    <span className="text-xs text-muted-foreground">{"Auto-scroll"}</span>
                                </label>
                            </div>
                            <div className="tree-viz-scroll" id="tree-scroll-container">
                                {[
                                    <div key={str(idx)}
                                         className={"tree-node-card" + (" tree-active" if live_tree[idx]["status"] == "active" and idx == find_active_node_idx(live_tree) else " tree-closed") + " tree-border-" + (live_tree[idx]["category"] or "default")}
                                         style={{"marginLeft": str((live_tree[idx]["depth"] or 0) * 24) + "px"}}>
                                        <div className="tree-node-title">
                                            {idx == find_active_node_idx(live_tree) and (
                                                <span className="tree-active-dot" />
                                            )}
                                            {live_tree[idx]["hypothesis"] or ("Root: " + str(live_tree[idx]["tool"] or "Initializing...")) if live_tree[idx]["depth"] == 0 else (live_tree[idx]["hypothesis"] or str(live_tree[idx]["tool"] or "..."))}
                                        </div>
                                        <div className="tree-node-meta">
                                            {live_tree[idx]["tool"] and (
                                                <span className={"tree-tool-badge tree-badge-" + (live_tree[idx]["category"] or "default")}>{str(live_tree[idx]["tool"] or "")}</span>
                                            )}
                                            <span className="tree-depth-badge">{"D" + str(live_tree[idx]["depth"] or 0)}</span>
                                            {idx == find_active_node_idx(live_tree) and (
                                                <span className="tree-tool-badge" style={{"background": "rgba(239,68,68,0.3)", "color": "#f87171"}}>ACTIVE</span>
                                            )}
                                        </div>
                                        {live_tree[idx]["question"] and (
                                            <div className="tree-section">
                                                <div className="tree-section-label">Unanswered Question</div>
                                                <div className="tree-section-text">{str(live_tree[idx]["question"] or "")}</div>
                                            </div>
                                        )}
                                        {live_tree[idx]["result"] and (
                                            <div className="tree-node-result">{str(live_tree[idx]["result"] or "")}</div>
                                        )}
                                    </div>
                                    for idx in range(len(live_tree))
                                ]}
                            </div>
                        </div>
                    )}

                    {live_artifacts and len(live_artifacts) > 0 and (
                        <div className="card p-6 mb-4">
                            <h2 className="text-base font-semibold text-primary mb-3">{"Evidence Collected (" + str(len(live_artifacts)) + ")"}</h2>
                            <div className="artifact-list">
                                {[
                                    <div key={str(aidx)} className={"artifact-item artifact-cat-" + (live_artifacts[aidx]["category"] or "default")} onClick={lambda: open_artifact(live_artifacts[aidx])}>
                                        <span className="artifact-id">{str(live_artifacts[aidx]["id"] or "")}</span>
                                        <span className="artifact-tool">{str(live_artifacts[aidx]["tool"] or "")}</span>
                                        <span className="artifact-summary">{str(live_artifacts[aidx]["summary"] or "")[:100]}</span>
                                    </div>
                                    for aidx in range(len(live_artifacts))
                                ]}
                            </div>
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
                                    <pre className="whitespace-pre-wrap text-xs">{JSON.stringify(selected_artifact["data"], null, 2) if selected_artifact["data"] else "Data not available — tool may have returned summary only."}</pre>
                                </div>
                            </div>
                        </div>
                    )}
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
                    <div className="report-text text-sm text-foreground" dangerouslySetInnerHTML={{"__html": render_report_with_citations(str(result["summary"] or ""))}} />
                    <div className="investigation-stats">
                        <span>{"Tool Calls: " + str(result["total_tool_calls"] or 0)}</span>
                        <span>{"LLM Calls: " + str(result["total_llm_calls"] or 0)}</span>
                        <span>{"Evidence: " + str(result["promoted_count"] or 0) + "/" + str(result["evidence_count"] or 0) + " promoted"}</span>
                        <span>{"Categories: " + str(result["categories"] or [])}</span>
                    </div>
                </div>

                {result and result["tree"] and len(result["tree"]) > 0 and (
                    <div className="card p-6 mb-4">
                        <h2 className="text-base font-semibold text-primary mb-3">{"Investigation Tree — " + str(len(result["tree"])) + " nodes explored"}</h2>
                        <div className="tree-legend">
                            <span className="tree-legend-dot tree-badge-market" /><span className="tree-legend-label">Market</span>
                            <span className="tree-legend-dot tree-badge-statistical" /><span className="tree-legend-label">Statistical</span>
                            <span className="tree-legend-dot tree-badge-news" /><span className="tree-legend-label">News</span>
                            <span className="tree-legend-dot tree-badge-wallet" /><span className="tree-legend-label">Wallet</span>
                            <span className="tree-legend-dot tree-badge-network" /><span className="tree-legend-label">Network</span>
                        </div>
                        <div className="tree-viz-scroll">
                            {[
                                <div key={str(idx)}
                                     className={"tree-node-card tree-closed tree-border-" + (result["tree"][idx]["category"] or "default")}
                                     style={{"marginLeft": str((result["tree"][idx]["depth"] or 0) * 24) + "px"}}>
                                    <div className="tree-node-title">
                                        {result["tree"][idx]["hypothesis"] or ("Root: " + str(result["tree"][idx]["tool"] or "")) if result["tree"][idx]["depth"] == 0 else (result["tree"][idx]["hypothesis"] or str(result["tree"][idx]["tool"] or ""))}
                                    </div>
                                    <div className="tree-node-meta">
                                        {result["tree"][idx]["tool"] and (
                                            <span className={"tree-tool-badge tree-badge-" + (result["tree"][idx]["category"] or "default")}>{str(result["tree"][idx]["tool"] or "")}</span>
                                        )}
                                        <span className="tree-depth-badge">{"D" + str(result["tree"][idx]["depth"] or 0)}</span>
                                    </div>
                                    {result["tree"][idx]["question"] and (
                                        <div className="tree-section">
                                            <div className="tree-section-label">Question Investigated</div>
                                            <div className="tree-section-text">{str(result["tree"][idx]["question"] or "")}</div>
                                        </div>
                                    )}
                                    {result["tree"][idx]["result"] and (
                                        <div className="tree-node-result">{str(result["tree"][idx]["result"] or "")}</div>
                                    )}
                                </div>
                                for idx in range(len(result["tree"]))
                            ]}
                        </div>
                    </div>
                )}

                {result and result["artifacts"] and len(result["artifacts"]) > 0 and (
                    <div className="card p-6 mb-4">
                        <h2 className="text-base font-semibold text-primary mb-3">{"Evidence Collected (" + str(len(result["artifacts"])) + " artifacts)"}</h2>
                        <div className="artifact-list">
                            {[
                                <div key={str(aidx)} className={"artifact-item artifact-cat-" + (result["artifacts"][aidx]["category"] or "default")} onClick={lambda: open_artifact(result["artifacts"][aidx])}>
                                    <span className="artifact-id">{str(result["artifacts"][aidx]["id"] or "")}</span>
                                    <span className="artifact-tool">{str(result["artifacts"][aidx]["tool"] or "")}</span>
                                    <span className="artifact-summary">{str(result["artifacts"][aidx]["summary"] or "")[:120]}</span>
                                </div>
                                for aidx in range(len(result["artifacts"]))
                            ]}
                        </div>
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
                                <pre className="whitespace-pre-wrap text-xs">{JSON.stringify(selected_artifact["data"], null, 2) if selected_artifact["data"] else "Data not available — tool may have returned summary only."}</pre>
                            </div>
                        </div>
                    </div>
                )}
            </div>
        </div>
    );
}
