"""Investigation Engine V2 — Tree of Thought with DFS + Backtracking.
Uses recursive DFS with by deepseek_llm() for LLM calls.
Tools from amar_tools.jac (26 Polymarket API tools).
State tracked via plain dicts (no graph nodes needed).
"""
import os;
import sys;
import time as _time;
import json;
import from pathlib { Path }
def _log(msg: str) {
    print(msg);
    sys.stdout.flush();
    try {
        with open("investigation_debug.log", "a") as f {
            f.write(msg + "\n");
        }
    } except Exception {
        0;
    }
}
import from byllm.lib { Model }
import from services.amar_tools {
    ToolRegistry, TOOL_REGISTRY,
    get_market_info, get_market_trades, get_market_price_history,
    clear_investigation_cache
}
# ── DeepSeek LLM setup ─────────────────────────────────────────
def _load_secret(key_name: str) -> str {
    token = os.environ.get(key_name, "");
    if token {
        return token;
    }
    env_path = Path(__file__).resolve().parent.parent / ".env";
    if env_path.exists() {
        for line in env_path.read_text().splitlines() {
            if line.startswith(key_name + "=") {
                return line.split("=", 1)[1].strip();
            }
        }
    }
    return "";
}
glob DEEPSEEK_KEY: str = _load_secret("DEEPSEEK_API_KEY");
glob deepseek_llm = Model(
    model_name="deepseek/deepseek-chat",
    api_key=DEEPSEEK_KEY
);
# ── Constants ───────────────────────────────────────────────────
glob MAX_DEPTH: int = 3;
glob MAX_CHILDREN: int = 4;
glob MAX_TOOL_CALLS: int = 25;
glob MIN_ROOT_TOOLS: int = 8;
glob MIN_ROOT_CATEGORIES: int = 3;
glob MAX_CONSECUTIVE_DUPLICATES: int = 2;
glob TOOL_CATEGORIES: dict = {
    "get_market_info": "market", "get_market_price_history": "market",
    "get_market_trades": "market", "get_large_trades": "market",
    "get_pre_event_trades": "market", "get_market_movers": "market",
    "compute_abnormal_volume": "statistical", "compute_price_run_up": "statistical",
    "score_trade_timing": "statistical", "compare_trader_to_peers": "statistical",
    "find_synchronized_traders": "statistical", "score_top_suspicious_wallets": "statistical",
    "search_news": "news", "get_event_news_timeline": "news",
    "check_pre_news_trades": "news", "correlate_market_trades_with_news": "news",
    "get_news_sentiment_around_event": "news", "analyze_pre_news_trading": "news",
    "get_wallet_profile": "wallet", "get_wallet_trade_history": "wallet",
    "get_wallet_pnl": "wallet", "get_wallet_win_rate_by_market_type": "wallet",
    "get_wallet_first_activity": "wallet",
    "find_linked_wallets": "network", "build_trader_network": "network",
    "trace_fund_flows": "network"
};
# ── LLM return types ───────────────────────────────────────────
obj PlanResult {
    has tool_name: str = "";
    has tool_args: dict[str, str] = {};
    has child_hypothesis: str = "";
    has child_question: str = "";
    has child_notes: str = "";
    has data_visible_to_ai: bool = False;
}
obj EvalResult {
    has should_close: bool = False;
    has conclusion: str = "";
    has reasoning: str = "";
}
obj CombinedDecision {
    has should_close: bool = False;
    has conclusion: str = "";
    has reasoning: str = "";
    has tool_name: str = "";
    has tool_args: dict[str, str] = {};
    has child_hypothesis: str = "";
    has child_question: str = "";
    has child_notes: str = "";
    has data_visible_to_ai: bool = False;
}
# ── LLM-powered decision functions (return str, we parse JSON) ──
def _plan_first_step_llm(
    investigation_goal: str,
    initial_artifacts_summary: str,
    available_tools_with_descriptions: str,
    respond_with_json_containing_tool_name_tool_args_child_hypothesis_child_question_child_notes_data_visible_to_ai: str = "Return ONLY valid JSON with keys: tool_name, tool_args, child_hypothesis, child_question, child_notes, data_visible_to_ai"
) -> str by deepseek_llm();
def _evaluate_and_plan_llm(
    investigation_goal: str,
    artifacts_summary: str,
    node_hypothesis: str,
    node_question: str,
    node_notes: str,
    conclusions_from_closed_children: str,
    tools_already_used_at_this_node: str,
    available_tools_with_descriptions: str,
    respond_with_json_containing_all_decision_fields: str = "Return ONLY valid JSON with these keys: should_close (bool), conclusion (string - fill if closing), reasoning (string), tool_name (string - next tool if NOT closing, empty string if closing), tool_args (object - args for next tool), child_hypothesis (string), child_question (string), child_notes (string), data_visible_to_ai (bool). IMPORTANT: Be VERY reluctant to close. Only set should_close=true if the question has been THOROUGHLY answered with evidence from multiple tool categories (market, statistical, news, wallet, network). If you have only used 1-2 categories, set should_close to false and plan the next tool from an unexplored category."
) -> str by deepseek_llm();
def _summarize_llm(
    investigation_goal: str,
    market_id: str,
    all_conclusions_from_tree: str,
    tool_categories_used: str,
    evidence_ledger_with_ids: str = "",
    report_format_instructions: str = "Write a structured investigation report with these sections:\n\n1. EXECUTIVE SUMMARY - 2-3 sentence overview of findings\n\n2. KEY FINDINGS - Each finding MUST cite evidence as [A1], [A2] etc. Example: 'No trades above $1,000 were detected before the news broke [A3].' Every factual claim needs a citation.\n\n3. EVIDENCE ANALYSIS - Walk through the most important evidence items, citing each by ID. Explain what the data shows and what it means.\n\n4. LIMITATIONS & GAPS - What data was missing or unavailable? What couldn't be determined?\n\n5. RECOMMENDED NEXT STEPS - What should a human investigator look into next? Be specific: which wallets to examine, what on-chain data to pull, what time periods to focus on, what exchanges to subpoena.\n\nIMPORTANT: You MUST use [A1], [A2] etc. citations throughout. Every claim about trades, wallets, volumes, or patterns must reference the evidence ID it came from."
) -> str by deepseek_llm();
def _parse_json(text: str) -> dict {
    # Extract JSON from LLM response (may be wrapped in ```json blocks)
    cleaned = text.strip();
    if "```json" in cleaned {
        start = cleaned.index("```json") + 7;
        end = cleaned.index("```", start);
        cleaned = cleaned[start:end].strip();
    } elif "```" in cleaned {
        start = cleaned.index("```") + 3;
        end = cleaned.index("```", start);
        cleaned = cleaned[start:end].strip();
    }
    try {
        return json.loads(cleaned);
    } except Exception {
        return {};
    }
}
def plan_first_step(goal: str, artifacts: str, tools: str) -> PlanResult {
    raw = _plan_first_step_llm(goal, artifacts, tools);
    _log("[JSON] plan_first_step raw: " + raw[:200]);
    d = _parse_json(raw);
    _log("[JSON] parsed: " + str(d)[:200]);
    return PlanResult(
        tool_name=d.get("tool_name", ""),
        tool_args=d.get("tool_args", {}),
        child_hypothesis=d.get("child_hypothesis", ""),
        child_question=d.get("child_question", ""),
        child_notes=d.get("child_notes", ""),
        data_visible_to_ai=d.get("data_visible_to_ai", False)
    );
}
def evaluate_and_plan(goal: str, artifacts: str, hypothesis: str, question: str, notes: str, conclusions: str, used: str, tools: str) -> CombinedDecision {
    raw = _evaluate_and_plan_llm(goal, artifacts, hypothesis, question, notes, conclusions, used, tools);
    _log("[JSON] evaluate_and_plan raw: " + raw[:200]);
    d = _parse_json(raw);
    return CombinedDecision(
        should_close=d.get("should_close", False),
        conclusion=d.get("conclusion", ""),
        reasoning=d.get("reasoning", ""),
        tool_name=d.get("tool_name", ""),
        tool_args=d.get("tool_args", {}),
        child_hypothesis=d.get("child_hypothesis", ""),
        child_question=d.get("child_question", ""),
        child_notes=d.get("child_notes", ""),
        data_visible_to_ai=d.get("data_visible_to_ai", False)
    );
}
def summarize_investigation(goal: str, market_id: str, conclusions: str, categories: str, evidence: str = "") -> str {
    return _summarize_llm(goal, market_id, conclusions, categories, evidence);
}
# ── Helper functions ────────────────────────────────────────────
def _format_artifacts(artifacts: list) -> str {
    if not artifacts {
        return "No evidence collected yet.";
    }
    parts: list = [];
    for a in artifacts {
        if isinstance(a, dict) {
            line = "- [" + str(a.get("tool", "?")) + "] " + str(a.get("summary", ""))[:300];
            if a.get("data_visible_to_ai") and a.get("data") {
                line = line + "\n  Data: " + str(a["data"])[:500];
            }
            parts.append(line);
        } else {
            parts.append("- " + str(a)[:200]);
        }
    }
    return "\n".join(parts);
}
def _format_tools(tools: ToolRegistry) -> str {
    tools_list = tools.list_tools();
    parts: list = [];
    for t in tools_list {
        param_strs: list = [];
        for p in t.get("params", []) {
            req = " (required)" if p.get("required") else "";
            param_strs.append(p["name"] + ": " + p.get("type", "str") + req);
        }
        parts.append("- " + t["name"] + ": " + t["description"] + "\n  Params: " + ", ".join(param_strs));
    }
    return "\n".join(parts);
}
# ── Shared investigation state ──────────────────────────────────
# ── Live progress (global, polled by frontend) ─────────────────

glob PROGRESS_FILE: str = "investigation_progress.json";

def _write_progress(data: dict) {
    try {
        tmp = PROGRESS_FILE + ".tmp";
        with open(tmp, "w") as f {
            json.dump(data, f);
        }
        os.replace(tmp, PROGRESS_FILE);
    } except Exception {
        0;
    }
}

def _read_progress() -> dict {
    try {
        with open(PROGRESS_FILE, "r") as f {
            return json.load(f);
        }
    } except Exception {
        return {"running": False, "tree": [], "total_tool_calls": 0, "total_llm_calls": 0, "categories": [], "status": "idle"};
    }
}

glob _live_progress: dict = {
    "running": False,
    "tree": [],
    "total_tool_calls": 0,
    "total_llm_calls": 0,
    "categories": [],
    "status": "idle"
};

glob STOP_FILE: str = "investigation_stop.flag";

def:priv get_investigation_progress() -> dict {
    return _read_progress();
}

def:priv stop_investigation() -> dict {
    try {
        with open(STOP_FILE, "w") as f {
            f.write("stop");
        }
    } except Exception {
        0;
    }
    return {"stopped": True};
}

def _should_stop() -> bool {
    try {
        with open(STOP_FILE, "r") as f {
            return True;
        }
    } except Exception {
        return False;
    }
}


obj InvestigationContext {
    has goal: str = "";
    has market_id: str = "";
    has event_timestamp: str = "";
    has tools: ToolRegistry = ToolRegistry();
    has tools_desc: str = "";
    has total_tool_calls: int = 0;
    has total_llm_calls: int = 0;
    has categories_used: list = [];
    has all_conclusions: list = [];
    has tree_nodes: list = [];
    has all_artifacts: list = [];
}
# ── Recursive DFS investigation ────────────────────────────────
def _investigate_node(
    ctx: InvestigationContext,
    depth: int,
    is_root: bool,
    hypothesis: str,
    question: str,
    notes: str,
    artifacts: list,
    conclusions: list,
    parent_id: str = "",
    incoming_tool: str = "",
    incoming_result: str = "",
    incoming_category: str = ""
) -> list {
    # Returns updated conclusions list
    pad = "  " * depth;
    node_id = "root" if is_root else "d" + str(depth) + "_" + str(ctx.total_tool_calls);
    # Track this node in the tree
    tree_node = {
        "id": node_id,
        "parent": parent_id,
        "depth": depth,
        "hypothesis": hypothesis[:150] if hypothesis else "",
        "question": question[:150] if question else "",
        "tool": incoming_tool,
        "result": incoming_result,
        "status": "active",
        "category": incoming_category,
        "children": []
    };
    ctx.tree_nodes.append(tree_node);
    _log(pad + "[ENTER " + node_id + " depth=" + str(depth) + "]");
    # ── Pre-LLM structural checks ──
    # If this node is already at max depth, don't waste an LLM call
    if not is_root and depth >= MAX_DEPTH {
        _log(pad + "  [MAX DEPTH — skipped LLM]");
        tree_node["status"] = "closed";
        return conclusions;
    }
    edges_used: list = [];
    child_count = 0;
    is_open = True;
    iterations = 0;
    max_iterations = 8;
    consecutive_duplicates = 0;
    while is_open {
        iterations += 1;
        if iterations > max_iterations {
            _log(pad + "  [MAX ITER]");
            break;
        }
        # Stop check
        if _should_stop() {
            conclusions.append("Investigation stopped by user.");
            _log(pad + "  [STOPPED BY USER]");
            break;
        }
        # Budget check
        if ctx.total_tool_calls >= MAX_TOOL_CALLS {
            _log(pad + "  [BUDGET]");
            break;
        }
        # Max children check BEFORE LLM call
        if child_count >= MAX_CHILDREN {
            _log(pad + "  [MAX CHILDREN]");
            break;
        }
        # STEP 2: Root first iteration — plan first step
        if is_root and child_count == 0 {
            ctx.total_llm_calls += 1;
            artifacts_str = _format_artifacts(artifacts);

_log(pad + "  [LLM] plan_first_step...");
            plan = plan_first_step(ctx.goal, artifacts_str, ctx.tools_desc);

_log(pad + "  [PLAN] tool=" + plan.tool_name);
        } else {
            # COMBINED: Evaluate node + plan next step in ONE LLM call
            ctx.total_llm_calls += 1;
            artifacts_str = _format_artifacts(artifacts);
            conclusions_str = "\n".join(conclusions) if conclusions else "No conclusions yet.";
            used_str = ", ".join(edges_used) if edges_used else "None";
            # Inject priority guidance for unexplored categories
            missing_cats = [c for c in ["market", "statistical", "news", "wallet", "network"] if c not in ctx.categories_used];
            priority_notes = notes;
            if missing_cats {
                priority_notes = priority_notes + "\nPRIORITY: You have not yet explored these categories: " + ", ".join(missing_cats) + ". Choose a tool from an unexplored category to broaden the investigation.";
            }

_log(pad + "  [LLM] evaluate_and_plan...");
            decision = evaluate_and_plan(
                ctx.goal, artifacts_str, hypothesis,
                question, priority_notes, conclusions_str,
                used_str, ctx.tools_desc
            );
            # STEP 6: Close and backtrack
            if decision.should_close {
                # Block premature root closure
                if is_root and (ctx.total_tool_calls < MIN_ROOT_TOOLS or len(ctx.categories_used) < MIN_ROOT_CATEGORIES) {
                    missing_cats = [c for c in ["market", "statistical", "news", "wallet", "network"] if c not in ctx.categories_used];

_log(pad + "  [ROOT CLOSE BLOCKED] " + str(ctx.total_tool_calls) + " tools, " + str(len(ctx.categories_used)) + " cats. Need: " + str(MIN_ROOT_TOOLS) + " tools, " + str(MIN_ROOT_CATEGORIES) + " cats. Missing: " + ", ".join(missing_cats));
                    notes = notes + "\nYou must investigate more before closing. Categories not yet explored: " + ", ".join(missing_cats) + ". Use tools from those categories.";
                } else {
                    if decision.conclusion {
                        conclusions.append(decision.conclusion);
                    }

_log(pad + "  [CLOSED] " + decision.reasoning[:80]);
                    break;
                }
            }
            # Use the plan portion of the combined decision
            plan = PlanResult(
                tool_name=decision.tool_name,
                tool_args=decision.tool_args,
                child_hypothesis=decision.child_hypothesis,
                child_question=decision.child_question,
                child_notes=decision.child_notes,
                data_visible_to_ai=decision.data_visible_to_ai
            );

_log(pad + "  [PLAN] tool=" + plan.tool_name);
        }
        # ── Execute tool ──
        tool_name = plan.tool_name;
        tool_args = plan.tool_args if plan.tool_args else {};
        # Error: invalid tool
        if tool_name not in TOOL_REGISTRY {

_log(pad + "  [ERROR] Invalid tool: " + tool_name);
            notes = notes + "\nError: tool '" + tool_name + "' does not exist. Valid: " + ", ".join(list(TOOL_REGISTRY.keys()));
            continue;
        }
        # Error: duplicate — with consecutive limit to prevent retry spiral
        call_key = tool_name + "(" + json.dumps(tool_args, sort_keys=True) + ")";
        if call_key in edges_used {
            consecutive_duplicates += 1;

_log(pad + "  [DUPLICATE " + str(consecutive_duplicates) + "/" + str(MAX_CONSECUTIVE_DUPLICATES) + "] " + call_key[:60]);
            if consecutive_duplicates >= MAX_CONSECUTIVE_DUPLICATES {
                _log(pad + "  [DUPLICATE LIMIT — closing node]");
                conclusions.append("Branch exhausted: repeated planning produced no new actions.");
                break;
            }
            notes = notes + "\nError: already called " + tool_name + " with these args. You MUST choose a DIFFERENT tool or DIFFERENT arguments. Already used: " + used_str;
            continue;
        }
        # Reset duplicate counter on successful new tool
        consecutive_duplicates = 0;
        # Inject market_id and event_timestamp
        tool_params = [p["name"] for p in TOOL_REGISTRY[tool_name]["params"]];
        if "market_id" in tool_params {
            tool_args["market_id"] = ctx.market_id;
        }
        if "event_timestamp" in tool_params {
            tool_args["event_timestamp"] = ctx.event_timestamp;
        }
        # Execute
        
_log(pad + "  [TOOL] " + tool_name);
        result = ctx.tools.call(tool_name, tool_args);
        ctx.total_tool_calls += 1;
        edges_used.append(call_key);
        # Track category
        cat = TOOL_CATEGORIES.get(tool_name, "other");
        if cat not in ctx.categories_used {
            ctx.categories_used.append(cat);
        }
        # Update live progress
        _live_progress["total_tool_calls"] = ctx.total_tool_calls;
        _live_progress["total_llm_calls"] = ctx.total_llm_calls;
        _live_progress["categories"] = list(ctx.categories_used);
        _live_progress["tree"] = list(ctx.tree_nodes);
        _live_progress["status"] = "tool: " + tool_name;
        # Artifact summaries for live viewer (no raw data — too large for JSON file)
        _live_progress["artifacts"] = [{"id": a["id"], "tool": a["tool"], "category": a["category"], "summary": a["summary"], "data": a["data"]} for a in ctx.all_artifacts];
        _write_progress(_live_progress);
        # Error: tool failed
        if "error" in result {
            
_log(pad + "  [TOOL ERROR] " + str(result["error"])[:80]);
            notes = notes + "\nTool " + tool_name + " failed: " + str(result["error"])[:200];
            continue;
        }
        summary = result.get("summary", "");
        
_log(pad + "  [RESULT] " + summary[:80]);
        # Build artifact
        artifact = {
            "tool": tool_name,
            "summary": summary,
            "data": result.get("data") if plan.data_visible_to_ai else None,
            "data_visible_to_ai": plan.data_visible_to_ai
        };
        # Collect artifact with full data for viewer
        ctx.all_artifacts.append({
            "id": "A" + str(len(ctx.all_artifacts) + 1),
            "tool": tool_name,
            "category": cat,
            "summary": summary,
            "data": result.get("data"),
            "node_id": node_id,
            "depth": depth
        });
        # STEP 3: Create child — recurse (DFS)
        # Tool info goes on the CHILD node (incoming edge)
        child_conclusions: list = [];
        child_conclusions = _investigate_node(
            ctx=ctx,
            depth=depth + 1,
            is_root=False,
            hypothesis=plan.child_hypothesis if plan.child_hypothesis else "",
            question=plan.child_question if plan.child_question else "",
            notes=plan.child_notes if plan.child_notes else "",
            artifacts=artifacts + [artifact],
            conclusions=child_conclusions,
            parent_id=node_id,
            incoming_tool=tool_name,
            incoming_result=summary[:150],
            incoming_category=cat
        );
        child_count += 1;
        # Record child in tree
        tree_node["children"].append("d" + str(depth + 1) + "_" + str(ctx.total_tool_calls - 1));
        # STEP 7: Backtrack — add child conclusions to this node
        for c in child_conclusions {
            conclusions.append("[child] " + c);
            ctx.all_conclusions.append(c);
        }
        
_log(pad + "  [BACKTRACK] " + str(len(child_conclusions)) + " conclusions from child");
    }
    tree_node["status"] = "closed";
    return conclusions;
}
# ── Background runner ───────────────────────────────────────────

import threading;

def _run_investigation_bg(market_id: str, event_timestamp: str, goal: str) {
    try {
        clear_investigation_cache();
        _log("\n" + "=" * 60);
        _log("  PolyWatch Investigation Engine V2");
        _log("  Market: " + market_id);
        _log("  Timestamp: " + event_timestamp);
        _log("=" * 60);
        # Bootstrap artifacts
        market_result = get_market_info(market_id);
        trades_result = get_market_trades(market_id, None, None);
        price_result = get_market_price_history(market_id, None, None);
        _log("[INIT] Market: " + market_result.get("summary", "N/A")[:80]);
        _log("[INIT] Trades: " + trades_result.get("summary", "N/A")[:80]);
        _log("[INIT] Price:  " + price_result.get("summary", "N/A")[:80]);
        _live_progress["status"] = "investigating";
        _write_progress(_live_progress);
        bootstrap = [
            {"tool": "get_market_info", "summary": market_result.get("summary", ""), "data": market_result.get("data"), "data_visible_to_ai": True},
            {"tool": "get_market_trades", "summary": trades_result.get("summary", ""), "data": None, "data_visible_to_ai": False},
            {"tool": "get_market_price_history", "summary": price_result.get("summary", ""), "data": None, "data_visible_to_ai": False},
        ];
        # Create context (tools_desc computed once, reused for all LLM calls)
        _tools_reg = ToolRegistry();
        ctx = InvestigationContext(
            goal=goal, market_id=market_id, event_timestamp=event_timestamp,
            tools=_tools_reg,
            tools_desc=_format_tools(_tools_reg)
        );
        start = _time.monotonic();
        # Run recursive DFS
        root_conclusions: list = [];
        root_conclusions = _investigate_node(
            ctx=ctx, depth=0, is_root=True,
            hypothesis="", question="", notes="",
            artifacts=bootstrap, conclusions=root_conclusions
        );
        elapsed = _time.monotonic() - start;
        # Generate final summary
        _log("\n[REPORT] Generating final summary...");
        _live_progress["status"] = "generating report";
        _write_progress(_live_progress);
        all_conclusions_str = "\n".join(ctx.all_conclusions) if ctx.all_conclusions else "No conclusions reached.";
        categories_str = ", ".join(sorted(ctx.categories_used));
        # Build evidence ledger for LLM citations
        evidence_lines: list = [];
        for a in ctx.all_artifacts {
            evidence_lines.append("[" + a["id"] + "] " + a["tool"] + " (" + a["category"] + "): " + a["summary"][:200]);
        }
        evidence_ledger_str = "\n".join(evidence_lines) if evidence_lines else "No evidence collected.";
        final_text = summarize_investigation(goal, market_id, all_conclusions_str, categories_str, evidence_ledger_str);
        # Write log
        try {
            log_lines = [
                "=" * 60, "INVESTIGATION LOG",
                "Market: " + market_id, "Timestamp: " + event_timestamp,
                "Goal: " + goal, "Elapsed: " + str(round(elapsed, 1)) + "s",
                "Tool Calls: " + str(ctx.total_tool_calls),
                "LLM Calls: " + str(ctx.total_llm_calls),
                "Categories: " + categories_str, "=" * 60, "",
                "CONCLUSIONS:",
            ];
            for c in ctx.all_conclusions {
                log_lines.append("  - " + c);
            }
            log_lines.append("");
            log_lines.append("FINAL REPORT:");
            log_lines.append(final_text);
            with open("investigation.log", "w") as f {
                f.write("\n".join(log_lines));
            }
        } except Exception as e {
            _log("[LOG] Failed: " + str(e));
        }
        _log("INVESTIGATION COMPLETE — " + str(round(elapsed, 1)) + "s, " + str(ctx.total_tool_calls) + " tools");
        # Collect price history and trade data for frontend charts
        chart_price_history = price_result.get("data", []);
        chart_trades = trades_result.get("data", []);
        # Build daily volume buckets from trades for chart
        daily_volume: dict = {};
        for t in chart_trades {
            ts = t.get("timestamp", 0);
            if isinstance(ts, (int, float)) and ts > 0 {
                day_key = str(int(ts) // 86400 * 86400);
                daily_volume.setdefault(day_key, {"timestamp": int(ts) // 86400 * 86400, "volume_usdc": 0.0, "trade_count": 0});
                daily_volume[day_key]["volume_usdc"] = daily_volume[day_key]["volume_usdc"] + t.get("size_usdc", 0);
                daily_volume[day_key]["trade_count"] = daily_volume[day_key]["trade_count"] + 1;
            }
        }
        daily_volume_list = sorted(daily_volume.values(), key=lambda x: x["timestamp"]);
        # Compute abnormal threshold (mean + 2*std of volume)
        if len(daily_volume_list) > 1 {
            vols = [d["volume_usdc"] for d in daily_volume_list];
            mean_vol = sum(vols) / len(vols);
            std_vol = (sum((v - mean_vol) ** 2 for v in vols) / len(vols)) ** 0.5;
            abnormal_threshold = mean_vol + 2 * std_vol;
            for d in daily_volume_list {
                d["abnormal"] = d["volume_usdc"] > abnormal_threshold;
            }
        } else {
            for d in daily_volume_list {
                d["abnormal"] = False;
            }
        }
        # Collect news articles with URLs from artifacts
        news_articles = [];
        for a in ctx.all_artifacts {
            if a.get("category") == "news" and a.get("data") {
                adata = a["data"];
                if isinstance(adata, dict) {
                    arts = adata.get("articles", []);
                    for na in arts {
                        if isinstance(na, dict) and na.get("title") {
                            news_articles.append({
                                "title": na.get("title", ""),
                                "source": na.get("source", ""),
                                "published_at": na.get("published_at", ""),
                                "url": na.get("url", ""),
                                "description": na.get("description", ""),
                                "relevance_score": na.get("relevance_score", 0)
                            });
                        }
                    }
                    # Also check timeline items
                    tl = adata.get("timeline", []);
                    for ti in tl {
                        if isinstance(ti, dict) and ti.get("headline") {
                            news_articles.append({
                                "title": ti.get("headline", ""),
                                "source": ti.get("source", ""),
                                "published_at": ti.get("timestamp", ""),
                                "url": ti.get("url", ""),
                                "description": "",
                                "relevance_score": ti.get("relevance_score", 0)
                            });
                        }
                    }
                }
            }
        }
        # Deduplicate news articles by title
        seen_titles: set = set();
        unique_articles: list = [];
        for na in news_articles {
            title_key = na.get("title", "").strip().lower();
            if title_key and title_key not in seen_titles {
                seen_titles.add(title_key);
                unique_articles.append(na);
            }
        }
        news_articles = unique_articles;
        # Store final result in progress
        _live_progress["result"] = {
            "summary": final_text,
            "market_id": market_id,
            "event_timestamp": event_timestamp,
            "total_tool_calls": ctx.total_tool_calls,
            "total_llm_calls": ctx.total_llm_calls,
            "evidence_count": len(ctx.all_conclusions),
            "promoted_count": len(ctx.all_conclusions),
            "confidence": "HIGH" if len(ctx.categories_used) >= 4 else ("MEDIUM" if len(ctx.categories_used) >= 3 else "LOW"),
            "categories": sorted(ctx.categories_used),
            "elapsed": round(elapsed, 1),
            "tree": list(ctx.tree_nodes),
            "artifacts": list(ctx.all_artifacts),
            "price_history": chart_price_history,
            "daily_volume": daily_volume_list,
            "news_articles": news_articles,
            "market_title": market_result.get("data", {}).get("title", market_id)
        };
        _live_progress["running"] = False;
        _live_progress["status"] = "complete";
        _live_progress["tree"] = list(ctx.tree_nodes);
        _live_progress["artifacts"] = [{"id": a["id"], "tool": a["tool"], "category": a["category"], "summary": a["summary"][:200], "data": a["data"]} for a in ctx.all_artifacts];
        _write_progress(_live_progress);
        # Save completed investigation to history
        _save_investigation(_live_progress["result"]);
    } except Exception as e {
        _log("[ERROR] Investigation failed: " + str(e));
        _live_progress["running"] = False;
        _live_progress["status"] = "error: " + str(e)[:100];
        _write_progress(_live_progress);
    }
}


# ���─ Investigation History ──────────────────────────────────────
glob HISTORY_DIR: str = "investigation_history";

def _ensure_history_dir() {
    try {
        os.makedirs(HISTORY_DIR, exist_ok=True);
    } except Exception {
        0;
    }
}

def _save_investigation(result: dict) {
    _ensure_history_dir();
    try {
        market_id = result.get("market_id", "unknown");
        ts = str(int(_time.time()));
        filename = market_id.replace("/", "_").replace(" ", "_")[:50] + "_" + ts + ".json";
        filepath = os.path.join(HISTORY_DIR, filename);
        with open(filepath, "w") as f {
            json.dump(result, f);
        }
        _log("[HISTORY] Saved: " + filepath);
    } except Exception as e {
        _log("[HISTORY] Save failed: " + str(e));
    }
}

def:priv list_investigations() -> dict {
    _ensure_history_dir();
    investigations: list = [];
    try {
        for fname in sorted(os.listdir(HISTORY_DIR), reverse=True) {
            if fname.endswith(".json") {
                filepath = os.path.join(HISTORY_DIR, fname);
                try {
                    with open(filepath, "r") as f {
                        data = json.load(f);
                    }
                    investigations.append({
                        "filename": fname,
                        "market_id": data.get("market_id", ""),
                        "market_title": data.get("market_title", data.get("market_id", "")),
                        "confidence": data.get("confidence", ""),
                        "elapsed": data.get("elapsed", 0),
                        "total_tool_calls": data.get("total_tool_calls", 0),
                        "categories": data.get("categories", []),
                        "event_timestamp": data.get("event_timestamp", "")
                    });
                } except Exception {
                    0;
                }
            }
        }
    } except Exception {
        0;
    }
    return {"investigations": investigations};
}

def:priv load_investigation(filename: str) -> dict {
    _ensure_history_dir();
    try {
        filepath = os.path.join(HISTORY_DIR, filename);
        with open(filepath, "r") as f {
            data = json.load(f);
        }
        return {"result": data};
    } except Exception as e {
        return {"error": str(e)};
    }
}

# ── Service functions ───────────────────────────────────────────

def:priv start_investigation(market_id: str, event_timestamp: str, goal: str = "") -> dict {
    if not goal {
        goal = "Look for any insider trading in this Polymarket market. Investigate abnormal trading patterns, coordinated wallet activity, suspicious timing relative to news events, and price manipulation signals.";
    }
    # Reset progress
    _live_progress["running"] = True;
    _live_progress["tree"] = [];
    _live_progress["total_tool_calls"] = 0;
    _live_progress["total_llm_calls"] = 0;
    _live_progress["categories"] = [];
    _live_progress["status"] = "bootstrapping";
    _live_progress["result"] = None;
    _write_progress(_live_progress);
    # Clear stop flag
    try {
        import os as _os2;
        _os2.remove(STOP_FILE);
    } except Exception {
        0;
    }
    # Launch in background thread
    t = threading.Thread(target=_run_investigation_bg, args=(market_id, event_timestamp, goal));
    t.daemon = True;
    t.start();
    return {"started": True, "market_id": market_id};
}
