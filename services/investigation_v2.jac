"""Investigation Engine V2 — simplified walker + byllm.

Uses Jac walkers with by deepseek_llm() for LLM calls.
Tools from amar_tools.jac (26 real Polymarket API tools).
~300 lines vs 1,845 in the original.
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


# ── Tool category mapping ──────────────────────────────────────

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

glob MIN_TOOLS_BEFORE_CLOSE: int = 6;
glob MIN_CATEGORIES_BEFORE_CLOSE: int = 3;


# ── LLM return types ───────────────────────────────────────────

obj PlanResult {
    has tool_name: str = "";
    has tool_args: dict = {};
    has hypothesis: str = "";
    has question: str = "";
}

obj EvalResult {
    has should_close: bool = False;
    has conclusion: str = "";
    has reasoning: str = "";
}


# ── LLM-powered functions (by deepseek_llm) ────────────────────

def plan_first_step(
    investigation_goal: str,
    market_summary: str,
    available_tools: str
) -> PlanResult by deepseek_llm();

def plan_next_step(
    investigation_goal: str,
    evidence_collected_so_far: str,
    current_hypothesis: str,
    current_question: str,
    tools_already_used: str,
    available_tools: str
) -> PlanResult by deepseek_llm();

def evaluate_branch(
    investigation_goal: str,
    evidence_collected_so_far: str,
    current_hypothesis: str,
    current_question: str,
    conclusions_from_children: str
) -> EvalResult by deepseek_llm();

def _write_report_llm(
    investigation_goal: str,
    market_id: str,
    all_evidence_and_findings: str,
    tool_categories_used: str
) -> str by deepseek_llm();

def write_final_report(goal: str, market_id: str, findings: str, categories: str) -> str {
    return _write_report_llm(goal, market_id, findings, categories);
}


# ── Graph structures ───────────────────────────────────────────

node InvestigationNode {
    has goal: str = "";
    has hypothesis: str = "";
    has question: str = "";
    has artifacts: list = [];
    has conclusions: list = [];
    has depth: int = 0;
    has is_open: bool = True;
    has is_root: bool = False;
    has child_count: int = 0;
    has node_id: str = "";
    has used_tools: list = [];
}

edge InvestigatedWith {
    has tool_name: str = "";
}


# ── Investigator walker ────────────────────────────────────────

walker Investigator {
    has goal: str = "";
    has market_id: str = "";
    has event_timestamp: str = "";
    has max_depth: int = 4;
    has max_children: int = 4;
    has max_tool_calls: int = 20;

    has tools: ToolRegistry = ToolRegistry();
    has total_tool_calls: int = 0;
    has total_llm_calls: int = 0;
    has categories_used: set = set();
    has all_findings: list = [];
    has start_time: float = 0.0;

    can on_entry with InvestigationNode entry {
        pad = "  " * here.depth;
        print(pad + "[NODE " + here.node_id + " depth=" + str(here.depth) + "]");

        while here.is_open and self.total_tool_calls < self.max_tool_calls {

            # ── EVALUATE: should we close this branch? ──
            if not here.is_root or here.child_count > 0 {
                evidence_str = self._format_artifacts(here.artifacts);
                conclusions_str = "\n".join(here.conclusions) if here.conclusions else "None yet.";

                self.total_llm_calls += 1;
                eval_result = evaluate_branch(
                    self.goal, evidence_str, here.hypothesis,
                    here.question, conclusions_str
                );

                if eval_result.should_close {
                    # Block root close if insufficient evidence
                    if here.is_root and (self.total_tool_calls < MIN_TOOLS_BEFORE_CLOSE or len(self.categories_used) < MIN_CATEGORIES_BEFORE_CLOSE) {
                        print(pad + "  [ROOT CLOSE BLOCKED] " + str(self.total_tool_calls) + " calls, " + str(len(self.categories_used)) + " categories");
                    } else {
                        here.is_open = False;
                        if eval_result.conclusion {
                            here.conclusions.append(eval_result.conclusion);
                        }
                        print(pad + "  [CLOSED] " + eval_result.reasoning[:60]);
                        break;
                    }
                }
            }

            # ── Check child limits ──
            if here.child_count >= self.max_children {
                here.is_open = False;
                here.conclusions.append("Max children reached.");
                break;
            }
            if here.depth >= self.max_depth {
                here.is_open = False;
                here.conclusions.append("Max depth reached.");
                break;
            }

            # ── PLAN: decide next tool ──
            self.total_llm_calls += 1;
            if here.is_root and here.child_count == 0 {
                tools_desc = self._format_tools();
                market_summary = self._format_artifacts(here.artifacts);
                plan = plan_first_step(self.goal, market_summary, tools_desc);
            } else {
                evidence_str = self._format_artifacts(here.artifacts);
                used_str = ", ".join(here.used_tools) if here.used_tools else "None";
                tools_desc = self._format_tools();
                plan = plan_next_step(
                    self.goal, evidence_str, here.hypothesis,
                    here.question, used_str, tools_desc
                );
            }

            tool_name = plan.tool_name;
            tool_args = plan.tool_args if plan.tool_args else {};

            # Validate tool exists
            if tool_name not in TOOL_REGISTRY {
                print(pad + "  [INVALID TOOL] " + tool_name);
                here.conclusions.append("LLM suggested invalid tool: " + tool_name);
                here.is_open = False;
                break;
            }

            # Inject market_id and event_timestamp if needed
            tool_params = [p["name"] for p in TOOL_REGISTRY[tool_name]["params"]];
            if "market_id" in tool_params {
                tool_args["market_id"] = self.market_id;
            }
            if "event_timestamp" in tool_params {
                tool_args["event_timestamp"] = self.event_timestamp;
            }

            # ── EXECUTE: run the tool ──
            print(pad + "  [TOOL] " + tool_name + "(" + str(tool_args) + ")");
            result = self.tools.call(tool_name, tool_args);
            self.total_tool_calls += 1;
            here.used_tools.append(tool_name);

            # Track category
            cat = TOOL_CATEGORIES.get(tool_name, "other");
            self.categories_used.add(cat);

            # Check for error
            if "error" in result {
                print(pad + "  [ERROR] " + str(result["error"])[:80]);
                here.conclusions.append("Tool " + tool_name + " failed: " + str(result["error"])[:100]);
                continue;
            }

            summary = result.get("summary", "");
            print(pad + "  [RESULT] " + summary[:80]);

            # Store finding
            finding = {
                "tool": tool_name,
                "category": cat,
                "summary": summary,
                "depth": here.depth
            };
            self.all_findings.append(finding);

            # ── CREATE CHILD: recurse into subtree ──
            child_id = tool_name + "_" + str(self.total_tool_calls);
            child = InvestigationNode(
                goal=self.goal,
                hypothesis=plan.hypothesis if plan.hypothesis else "",
                question=plan.question if plan.question else "",
                artifacts=here.artifacts + [{"tool": tool_name, "summary": summary, "data": result.get("data")}],
                depth=here.depth + 1,
                is_root=False,
                node_id=child_id,
                used_tools=list(here.used_tools)
            );
            here ++> InvestigatedWith(tool_name=tool_name) ++> child;
            here.child_count += 1;

            visit child;
        }

        # If still open after loop, force close
        if here.is_open {
            here.is_open = False;
            here.conclusions.append("Tool budget exhausted (" + str(self.total_tool_calls) + " calls).");
        }
    }

    can on_exit with InvestigationNode exit {
        # Bubble conclusions up to parent
        if not here.is_root and here.conclusions {
            combined = "; ".join(here.conclusions);
            # Find parent via edge traversal
            for parent in [n for n in here.__jac__.edges if hasattr(n, "conclusions")] {
                parent.conclusions.append("[" + here.node_id + "] " + combined);
            }
        }
    }

    def _format_artifacts(artifacts: list) -> str {
        if not artifacts {
            return "No evidence collected yet.";
        }
        parts: list = [];
        for a in artifacts {
            if isinstance(a, dict) {
                parts.append("- [" + str(a.get("tool", "?")) + "] " + str(a.get("summary", ""))[:200]);
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

def:priv start_investigation(market_id: str, event_timestamp: str, goal: str = "", max_depth: int = 4, max_children: int = 4) -> dict {
    if not goal {
        goal = "Detect insider trading patterns in this Polymarket market. Look for: abnormal volume before news events, coordinated wallet activity, suspicious timing of large trades, and price manipulation signals.";
    }

    print("\n" + "=" * 60);
    print("  PolyWatch Investigation Engine V2");
    print("  Market: " + market_id);
    print("  Event:  " + event_timestamp);
    print("=" * 60);

    # Bootstrap: resolve market and get initial data
    tools = ToolRegistry();

    market_result = get_market_info(market_id);
    market_summary = market_result.get("summary", "No market data");
    print("[INIT] Market: " + market_summary[:80]);

    trades_result = get_market_trades(market_id, None, None);
    trades_summary = trades_result.get("summary", "No trades");
    print("[INIT] Trades: " + trades_summary[:80]);

    price_result = get_market_price_history(market_id, None, None);
    price_summary = price_result.get("summary", "No price data");
    print("[INIT] Price: " + price_summary[:80]);

    bootstrap_artifacts = [
        {"tool": "get_market_info", "summary": market_summary, "data": market_result.get("data")},
        {"tool": "get_market_trades", "summary": trades_summary, "data": None},
        {"tool": "get_market_price_history", "summary": price_summary, "data": None},
    ];

    # Create root node
    root = InvestigationNode(
        goal=goal, is_root=True, is_open=True, depth=0,
        node_id="root", artifacts=bootstrap_artifacts
    );

    # Create and spawn walker
    start = _time.monotonic();
    investigator = Investigator(
        goal=goal, market_id=market_id, event_timestamp=event_timestamp,
        max_depth=max_depth, max_children=max_children,
        max_tool_calls=20, tools=tools
    );
    investigator.start_time = start;

    root spawn investigator;

    elapsed = _time.monotonic() - start;

    # Generate final report
    print("\n[REPORT] Generating final report...");
    findings_str = "";
    for f in investigator.all_findings {
        findings_str += "[" + f["category"] + "] " + f["tool"] + ": " + f["summary"] + "\n";
    }
    if not findings_str {
        findings_str = "No tool results collected.";
    }

    categories_str = ", ".join(sorted(list(investigator.categories_used)));
    investigator.total_llm_calls += 1;
    final_text = write_final_report(goal, market_id, findings_str, categories_str);

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
        "evidence_count": len(investigator.all_findings),
        "promoted_count": len(investigator.all_findings),
        "confidence": "MEDIUM" if len(investigator.categories_used) >= 3 else "LOW",
        "categories": sorted(list(investigator.categories_used)),
        "elapsed": round(elapsed, 1)
    };
}
