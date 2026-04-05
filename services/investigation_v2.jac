"""Investigation Engine V2 — Tree of Thought with DFS + Backtracking.

Uses recursive DFS with by deepseek_llm() for LLM calls.
Tools from amar_tools.jac (26 Polymarket API tools).
State tracked via plain dicts (no graph nodes needed).
"""

import os;
import time as _time;
import json;
import from pathlib { Path }
import from byllm.lib { Model }
import from services.amar_tools {
    ToolRegistry, TOOL_REGISTRY,
    get_market_info, get_market_trades, get_market_price_history
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

glob MAX_DEPTH: int = 5;
glob MAX_CHILDREN: int = 4;
glob MAX_TOOL_CALLS: int = 20;
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


# ── LLM-powered decision functions ─────────────────────────────

def plan_first_step(
    investigation_goal: str,
    initial_artifacts_summary: str,
    available_tools_with_descriptions: str
) -> PlanResult by deepseek_llm();

def evaluate_node(
    investigation_goal: str,
    artifacts_summary: str,
    node_hypothesis: str,
    node_question: str,
    node_notes: str,
    conclusions_from_closed_children: str
) -> EvalResult by deepseek_llm();

def plan_next_step(
    investigation_goal: str,
    artifacts_summary: str,
    current_hypothesis: str,
    current_question: str,
    current_notes: str,
    conclusions_from_closed_children: str,
    tools_already_used_at_this_node: str,
    available_tools_with_descriptions: str
) -> PlanResult by deepseek_llm();

def _summarize_llm(
    investigation_goal: str,
    market_id: str,
    all_conclusions_from_tree: str,
    tool_categories_used: str
) -> str by deepseek_llm();

def summarize_investigation(goal: str, market_id: str, conclusions: str, categories: str) -> str {
    return _summarize_llm(goal, market_id, conclusions, categories);
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

obj InvestigationContext {
    has goal: str = "";
    has market_id: str = "";
    has event_timestamp: str = "";
    has tools: ToolRegistry = ToolRegistry();
    has total_tool_calls: int = 0;
    has total_llm_calls: int = 0;
    has categories_used: list = [];
    has all_conclusions: list = [];
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
    conclusions: list
) -> list {
    # Returns updated conclusions list

    pad = "  " * depth;
    node_id = "root" if is_root else "d" + str(depth) + "_" + str(ctx.total_tool_calls);
    print(pad + "[ENTER " + node_id + " depth=" + str(depth) + "]");

    edges_used: list = [];
    child_count = 0;
    is_open = True;

    while is_open {

        # Budget check
        if ctx.total_tool_calls >= MAX_TOOL_CALLS {
            conclusions.append("Budget exhausted (" + str(MAX_TOOL_CALLS) + " tool calls).");
            print(pad + "  [BUDGET]");
            break;
        }

        # STEP 2: Root first iteration — plan first step
        if is_root and child_count == 0 {
            ctx.total_llm_calls += 1;
            tools_desc = _format_tools(ctx.tools);
            artifacts_str = _format_artifacts(artifacts);
            print(pad + "  [LLM] plan_first_step...");
            plan = plan_first_step(ctx.goal, artifacts_str, tools_desc);
            print(pad + "  [PLAN] tool=" + plan.tool_name);
        } else {
            # STEP 4: Evaluate node
            ctx.total_llm_calls += 1;
            artifacts_str = _format_artifacts(artifacts);
            conclusions_str = "\n".join(conclusions) if conclusions else "No conclusions yet.";
            print(pad + "  [LLM] evaluate_node...");
            eval_result = evaluate_node(
                ctx.goal, artifacts_str, hypothesis,
                question, notes, conclusions_str
            );

            # STEP 6: Close and backtrack
            if eval_result.should_close {
                if eval_result.conclusion {
                    conclusions.append(eval_result.conclusion);
                }
                print(pad + "  [CLOSED] " + eval_result.reasoning[:80]);
                break;
            }

            # Max depth
            if depth >= MAX_DEPTH {
                conclusions.append("Max depth reached.");
                print(pad + "  [MAX DEPTH]");
                break;
            }

            # Max children
            if child_count >= MAX_CHILDREN {
                conclusions.append("Max children reached.");
                print(pad + "  [MAX CHILDREN]");
                break;
            }

            # STEP 5/8: Plan next step
            ctx.total_llm_calls += 1;
            used_str = ", ".join(edges_used) if edges_used else "None";
            tools_desc = _format_tools(ctx.tools);
            print(pad + "  [LLM] plan_next_step...");
            plan = plan_next_step(
                ctx.goal, artifacts_str, hypothesis,
                question, notes, conclusions_str,
                used_str, tools_desc
            );
            print(pad + "  [PLAN] tool=" + plan.tool_name);
        }

        # ── Execute tool ──
        tool_name = plan.tool_name;
        tool_args = plan.tool_args if plan.tool_args else {};

        # Error: invalid tool
        if tool_name not in TOOL_REGISTRY {
            print(pad + "  [ERROR] Invalid tool: " + tool_name);
            notes = notes + "\nError: tool '" + tool_name + "' does not exist. Valid: " + ", ".join(list(TOOL_REGISTRY.keys()));
            continue;
        }

        # Error: duplicate
        call_key = tool_name + "(" + json.dumps(tool_args, sort_keys=True) + ")";
        if call_key in edges_used {
            print(pad + "  [DUPLICATE] " + call_key[:60]);
            notes = notes + "\nError: already called " + tool_name + " with these args.";
            continue;
        }

        # Inject market_id and event_timestamp
        tool_params = [p["name"] for p in TOOL_REGISTRY[tool_name]["params"]];
        if "market_id" in tool_params {
            tool_args["market_id"] = ctx.market_id;
        }
        if "event_timestamp" in tool_params {
            tool_args["event_timestamp"] = ctx.event_timestamp;
        }

        # Execute
        print(pad + "  [TOOL] " + tool_name);
        result = ctx.tools.call(tool_name, tool_args);
        ctx.total_tool_calls += 1;
        edges_used.append(call_key);

        # Track category
        cat = TOOL_CATEGORIES.get(tool_name, "other");
        if cat not in ctx.categories_used {
            ctx.categories_used.append(cat);
        }

        # Error: tool failed
        if "error" in result {
            print(pad + "  [TOOL ERROR] " + str(result["error"])[:80]);
            notes = notes + "\nTool " + tool_name + " failed: " + str(result["error"])[:200];
            continue;
        }

        summary = result.get("summary", "");
        print(pad + "  [RESULT] " + summary[:80]);

        # Build artifact
        artifact = {
            "tool": tool_name,
            "summary": summary,
            "data": result.get("data") if plan.data_visible_to_ai else None,
            "data_visible_to_ai": plan.data_visible_to_ai
        };

        # STEP 3: Create child — recurse (DFS)
        child_conclusions: list = [];
        child_conclusions = _investigate_node(
            ctx=ctx,
            depth=depth + 1,
            is_root=False,
            hypothesis=plan.child_hypothesis if plan.child_hypothesis else "",
            question=plan.child_question if plan.child_question else "",
            notes=plan.child_notes if plan.child_notes else "",
            artifacts=artifacts + [artifact],
            conclusions=child_conclusions
        );
        child_count += 1;

        # STEP 7: Backtrack — add child conclusions to this node
        for c in child_conclusions {
            conclusions.append("[child] " + c);
            ctx.all_conclusions.append(c);
        }
        print(pad + "  [BACKTRACK] " + str(len(child_conclusions)) + " conclusions from child");
    }

    return conclusions;
}


# ── Service function ────────────────────────────────────────────

def:priv start_investigation(market_id: str, event_timestamp: str, goal: str = "", max_depth: int = 5, max_children: int = 4) -> dict {
    if not goal {
        goal = "Look for any insider trading in this Polymarket market. Investigate abnormal trading patterns, coordinated wallet activity, suspicious timing relative to news events, and price manipulation signals.";
    }

    print("\n" + "=" * 60);
    print("  PolyWatch Investigation Engine V2");
    print("  Market: " + market_id);
    print("  Timestamp: " + event_timestamp);
    print("=" * 60);

    # Bootstrap artifacts
    market_result = get_market_info(market_id);
    trades_result = get_market_trades(market_id, None, None);
    price_result = get_market_price_history(market_id, None, None);

    print("[INIT] Market: " + market_result.get("summary", "N/A")[:80]);
    print("[INIT] Trades: " + trades_result.get("summary", "N/A")[:80]);
    print("[INIT] Price:  " + price_result.get("summary", "N/A")[:80]);

    bootstrap = [
        {"tool": "get_market_info", "summary": market_result.get("summary", ""), "data": market_result.get("data"), "data_visible_to_ai": True},
        {"tool": "get_market_trades", "summary": trades_result.get("summary", ""), "data": None, "data_visible_to_ai": False},
        {"tool": "get_market_price_history", "summary": price_result.get("summary", ""), "data": None, "data_visible_to_ai": False},
    ];

    # Create context
    ctx = InvestigationContext(
        goal=goal, market_id=market_id, event_timestamp=event_timestamp,
        tools=ToolRegistry()
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
    print("\n[REPORT] Generating final summary...");
    all_conclusions_str = "\n".join(ctx.all_conclusions) if ctx.all_conclusions else "No conclusions reached.";
    categories_str = ", ".join(sorted(ctx.categories_used));

    final_text = summarize_investigation(goal, market_id, all_conclusions_str, categories_str);

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
        print("[LOG] Written to investigation.log");
    } except Exception as e {
        print("[LOG] Failed: " + str(e));
    }

    print("\n" + "=" * 60);
    print("INVESTIGATION COMPLETE");
    print("  Elapsed: " + str(round(elapsed, 1)) + "s");
    print("  Tool Calls: " + str(ctx.total_tool_calls));
    print("  LLM Calls: " + str(ctx.total_llm_calls));
    print("  Categories: " + categories_str);
    print("=" * 60);

    return {
        "summary": final_text,
        "market_id": market_id,
        "event_timestamp": event_timestamp,
        "total_tool_calls": ctx.total_tool_calls,
        "total_llm_calls": ctx.total_llm_calls,
        "evidence_count": len(ctx.all_conclusions),
        "promoted_count": len(ctx.all_conclusions),
        "confidence": "HIGH" if len(ctx.categories_used) >= 4 else ("MEDIUM" if len(ctx.categories_used) >= 3 else "LOW"),
        "categories": sorted(ctx.categories_used),
        "elapsed": round(elapsed, 1)
    };
}
