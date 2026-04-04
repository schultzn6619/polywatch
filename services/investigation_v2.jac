"""Investigation Engine V2 — Tree of Thought with DFS + Backtracking.

Based on: https://arxiv.org/pdf/2305.10601
Uses Jac walkers with by deepseek_llm() for all LLM calls.
Tools from amar_tools.jac (26 Polymarket API tools).

Data structure:
- Nodes store: artifacts, hypothesis, question, notes, conclusions, goal
- Edges are unique per node — each corresponds to a tool call
- Walker traverses DFS, backtracks when nodes close
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
import from services.api { resolve_market }


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
    has tool_args: dict = {};
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

# Step 2: At the root node, decide the first tool and generate
# hypothesis/question/notes for the first child node.
def plan_first_step(
    investigation_goal: str,
    initial_artifacts_summary: str,
    available_tools_with_descriptions: str
) -> PlanResult by deepseek_llm();

# Step 4-5: At a non-root node, evaluate whether it should stay
# open or close, given its hypothesis, question, artifacts, and
# any conclusions from children that backtracked.
def evaluate_node(
    investigation_goal: str,
    artifacts_summary: str,
    node_hypothesis: str,
    node_question: str,
    node_notes: str,
    conclusions_from_closed_children: str
) -> EvalResult by deepseek_llm();

# Step 5/8: If the node stays open, plan the next tool to call
# and generate hypothesis/question/notes for the next child.
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

# Step 9: When root closes, summarize the entire investigation.
def _summarize_llm(
    investigation_goal: str,
    market_id: str,
    all_conclusions_from_tree: str,
    tool_categories_used: str
) -> str by deepseek_llm();

def summarize_investigation(goal: str, market_id: str, conclusions: str, categories: str) -> str {
    return _summarize_llm(goal, market_id, conclusions, categories);
}


# ── Graph structures ───────────────────────────────────────────

node InvestigationNode {
    has goal: str = "";
    has hypothesis: str = "";
    has question: str = "";
    has notes: str = "";
    has artifacts: list = [];
    has conclusions: list = [];
    has depth: int = 0;
    has is_open: bool = True;
    has is_root: bool = False;
    has child_count: int = 0;
    has node_id: str = "";
    has edges_used: set = set();
}

edge InvestigatedWith {
    has tool_name: str = "";
}


# ── Investigator walker ────────────────────────────────────────

walker Investigator {
    has goal: str = "";
    has market_id: str = "";
    has event_timestamp: str = "";

    has tools: ToolRegistry = ToolRegistry();
    has total_tool_calls: int = 0;
    has total_llm_calls: int = 0;
    has categories_used: set = set();
    has all_conclusions: list = [];
    has start_time: float = 0.0;

    can on_entry with InvestigationNode entry {
        pad = "  " * here.depth;
        print(pad + "[ENTER " + here.node_id + " d=" + str(here.depth) + "]");

        while here.is_open {

            # ── Budget check ──
            if self.total_tool_calls >= MAX_TOOL_CALLS {
                here.is_open = False;
                here.conclusions.append("Investigation budget exhausted (" + str(MAX_TOOL_CALLS) + " tool calls).");
                print(pad + "  [BUDGET] Max tool calls reached");
                break;
            }

            # ── STEP 2 (root, first iteration): Plan first step ──
            if here.is_root and here.child_count == 0 {
                self.total_llm_calls += 1;
                tools_desc = self._format_tools();
                artifacts_str = self._format_artifacts(here.artifacts);
                plan = plan_first_step(self.goal, artifacts_str, tools_desc);

                # Execute tool and create child (Step 3)
                ok = self._execute_and_spawn_child(here, plan, pad);
                if not ok {
                    continue;
                }
                continue;
            }

            # ── STEP 4: Evaluate current node ──
            self.total_llm_calls += 1;
            artifacts_str = self._format_artifacts(here.artifacts);
            conclusions_str = "\n".join(here.conclusions) if here.conclusions else "No conclusions yet.";

            eval_result = evaluate_node(
                self.goal, artifacts_str, here.hypothesis,
                here.question, here.notes, conclusions_str
            );

            # ── STEP 6: Close and backtrack ──
            if eval_result.should_close {
                here.is_open = False;
                if eval_result.conclusion {
                    here.conclusions.append(eval_result.conclusion);
                }
                print(pad + "  [CLOSED] " + eval_result.reasoning[:80]);
                break;
            }

            # ── Max depth: force backtrack (Step 6 variant) ──
            if here.depth >= MAX_DEPTH {
                here.is_open = False;
                here.conclusions.append("Max depth reached — forced backtrack.");
                print(pad + "  [MAX DEPTH] Forced close");
                break;
            }

            # ── Max children: force close ──
            if here.child_count >= MAX_CHILDREN {
                here.is_open = False;
                here.conclusions.append("Max children reached — all paths explored.");
                print(pad + "  [MAX CHILDREN] Forced close");
                break;
            }

            # ── STEP 5/8: Plan next step ──
            self.total_llm_calls += 1;
            used_str = ", ".join(list(here.edges_used)) if here.edges_used else "None";
            tools_desc = self._format_tools();

            plan = plan_next_step(
                self.goal, artifacts_str, here.hypothesis,
                here.question, here.notes, conclusions_str,
                used_str, tools_desc
            );

            # Execute tool and create child (Step 3)
            ok = self._execute_and_spawn_child(here, plan, pad);
            if not ok {
                # Error handling: tool failed, LLM gets error context.
                # Loop continues — LLM will see the error in notes and try different tool.
                continue;
            }
        }
    }

    can on_exit with InvestigationNode exit {
        # STEP 6-7: Backtracking — bubble conclusions to parent
        if here.conclusions {
            combined = here.node_id + ": " + "; ".join(here.conclusions);
            self.all_conclusions.append(combined);
            print("  " * here.depth + "  [BACKTRACK] " + combined[:80]);
        }
    }

    # ── Execute tool, handle errors, create child node (Step 3) ──
    def _execute_and_spawn_child(current: InvestigationNode, plan: PlanResult, pad: str) -> bool {
        tool_name = plan.tool_name;
        tool_args = plan.tool_args if plan.tool_args else {};

        # Error handling: invalid tool name
        if tool_name not in TOOL_REGISTRY {
            print(pad + "  [ERROR] Invalid tool: " + tool_name);
            current.notes = current.notes + "\nError: tool '" + tool_name + "' does not exist. Choose from: " + ", ".join(list(TOOL_REGISTRY.keys()));
            return False;
        }

        # Error handling: duplicate edge (each edge at each node must be unique)
        call_key = tool_name + "(" + json.dumps(tool_args, sort_keys=True) + ")";
        if call_key in current.edges_used {
            print(pad + "  [DUPLICATE] " + call_key[:60]);
            current.notes = current.notes + "\nError: already called " + tool_name + " with these args. Try a different tool or different arguments.";
            return False;
        }

        # Inject market_id and event_timestamp
        tool_params = [p["name"] for p in TOOL_REGISTRY[tool_name]["params"]];
        if "market_id" in tool_params {
            tool_args["market_id"] = self.market_id;
        }
        if "event_timestamp" in tool_params {
            tool_args["event_timestamp"] = self.event_timestamp;
        }

        # Execute tool
        print(pad + "  [TOOL] " + tool_name);
        result = self.tools.call(tool_name, tool_args);
        self.total_tool_calls += 1;
        current.edges_used.add(call_key);

        # Track category
        cat = TOOL_CATEGORIES.get(tool_name, "other");
        self.categories_used.add(cat);

        # Error handling: tool execution failed
        if "error" in result {
            print(pad + "  [TOOL ERROR] " + str(result["error"])[:80]);
            current.notes = current.notes + "\nTool " + tool_name + " failed: " + str(result["error"])[:200] + ". Try a different approach.";
            return False;
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

        # Create child node (Step 3)
        child_id = tool_name + "_" + str(self.total_tool_calls);
        child = InvestigationNode(
            goal=self.goal,
            hypothesis=plan.child_hypothesis if plan.child_hypothesis else "",
            question=plan.child_question if plan.child_question else "",
            notes=plan.child_notes if plan.child_notes else "",
            artifacts=current.artifacts + [artifact],
            depth=current.depth + 1,
            is_root=False,
            node_id=child_id
        );

        current ++> InvestigatedWith(tool_name=tool_name) ++> child;
        current.child_count += 1;

        # DFS: visit child
        visit child;

        # Step 7: Back from child — its conclusions are now in self.all_conclusions
        # and will be added to current.conclusions via on_exit.
        # The while loop will re-evaluate this node (Step 7-8).
        return True;
    }

    def _format_artifacts(artifacts: list) -> str {
        if not artifacts {
            return "No evidence collected yet.";
        }
        parts: list = [];
        for a in artifacts {
            if isinstance(a, dict) {
                line = "- [" + str(a.get("tool", "?")) + "] " + str(a.get("summary", ""))[:300];
                if a.get("data_visible_to_ai") and a.get("data") {
                    line += "\n  Data: " + str(a["data"])[:500];
                }
                parts.append(line);
            } else {
                parts.append("- " + str(a)[:200]);
            }
        }
        return "\n".join(parts);
    }

    def _format_tools() -> str {
        tools_list = self.tools.list_tools();
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

    # Bootstrap root artifacts: event data, market data, trade data
    market_result = get_market_info(market_id);
    trades_result = get_market_trades(market_id, None, None);
    price_result = get_market_price_history(market_id, None, None);

    print("[INIT] Market: " + market_result.get("summary", "N/A")[:80]);
    print("[INIT] Trades: " + trades_result.get("summary", "N/A")[:80]);
    print("[INIT] Price:  " + price_result.get("summary", "N/A")[:80]);

    root_artifacts = [
        {"tool": "get_market_info", "summary": market_result.get("summary", ""), "data": market_result.get("data"), "data_visible_to_ai": True},
        {"tool": "get_market_trades", "summary": trades_result.get("summary", ""), "data": None, "data_visible_to_ai": False},
        {"tool": "get_market_price_history", "summary": price_result.get("summary", ""), "data": None, "data_visible_to_ai": False},
    ];

    # Create root node
    root = InvestigationNode(
        goal=goal, is_root=True, is_open=True, depth=0,
        node_id="root", artifacts=root_artifacts,
        hypothesis="", question="", notes=""
    );

    # Create and spawn walker
    start = _time.monotonic();
    investigator = Investigator(
        goal=goal, market_id=market_id, event_timestamp=event_timestamp,
        tools=ToolRegistry()
    );
    investigator.start_time = start;

    root spawn investigator;

    elapsed = _time.monotonic() - start;

    # Step 9: Root closed — generate final summary
    print("\n[REPORT] Generating final summary...");
    all_conclusions_str = "\n".join(investigator.all_conclusions) if investigator.all_conclusions else "No conclusions reached.";
    categories_str = ", ".join(sorted(list(investigator.categories_used)));

    final_text = summarize_investigation(goal, market_id, all_conclusions_str, categories_str);

    print("\n" + "=" * 60);
    print("INVESTIGATION COMPLETE");
    print("  Elapsed: " + str(round(elapsed, 1)) + "s");
    print("  Tool Calls: " + str(investigator.total_tool_calls));
    print("  LLM Calls: " + str(investigator.total_llm_calls));
    print("  Categories: " + categories_str);
    print("=" * 60);

    return {
        "summary": final_text,
        "market_id": market_id,
        "event_timestamp": event_timestamp,
        "total_tool_calls": investigator.total_tool_calls,
        "total_llm_calls": investigator.total_llm_calls,
        "evidence_count": len(investigator.all_conclusions),
        "promoted_count": len(investigator.all_conclusions),
        "confidence": "HIGH" if len(investigator.categories_used) >= 4 else ("MEDIUM" if len(investigator.categories_used) >= 3 else "LOW"),
        "categories": sorted(list(investigator.categories_used)),
        "elapsed": round(elapsed, 1)
    };
}
