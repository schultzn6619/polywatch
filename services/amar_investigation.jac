"""
PolyWatch — Insider Trading Investigation Engine (Jac)
Tree of Thought (DFS + Backtracking) Investigation Engine

V11: Full Jac implementation with:
  - Evidence ledger with 5-tier quality system and promotion gates
  - Strict confidence computation (LOW/MEDIUM/HIGH)
  - Context integrity enforcement (market_id + event_timestamp immutable)
  - Legal language sanitization
  - Corroboration-driven conclusion gating
  - Source-aware tool filtering
  - Dynamic budget expansion
  - Deterministic report generation with 10+ appendix sections
  - Wallet/network tools derive real data from trades
"""

import sys;
import os;
import random;
import json;
import time as _time;

import from services.llm { LLMEngine }
import from services.amar_tools { ToolRegistry, TOOL_REGISTRY, get_market_info, get_market_price_history, get_market_trades }
import from services.logger { InvestigationLogger }
import from services.evidence { EVIDENCE_TIERS, UNAVAILABILITY_MARKERS, classify_evidence_tier, Artifact, EvidenceItem }


# ─────────────────────────────────────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────────────────────────────────────

glob TOOL_CATEGORIES: dict = {
    "market":      ["get_market_info", "get_market_price_history", "get_market_trades",
                    "get_large_trades", "get_pre_event_trades", "get_market_movers"],
    "statistical": ["compute_abnormal_volume", "compute_price_run_up", "score_trade_timing",
                    "compare_trader_to_peers", "find_synchronized_traders",
                    "score_top_suspicious_wallets"],
    "news":        ["search_news", "get_event_news_timeline", "check_pre_news_trades",
                    "correlate_market_trades_with_news", "get_news_sentiment_around_event",
                    "analyze_pre_news_trading"],
    "wallet":      ["get_wallet_profile", "get_wallet_trade_history", "get_wallet_pnl",
                    "get_wallet_win_rate_by_market_type", "get_wallet_first_activity"],
    "network":     ["find_linked_wallets", "build_trader_network", "trace_fund_flows"]
};

glob MIN_TOOL_CALLS_FOR_ROOT_CLOSE: int = 3;
glob MIN_TOOL_CATEGORIES_FOR_ROOT_CLOSE: int = 2;
glob MIN_EVIDENCE_ITEMS_FOR_SUFFICIENT: int = 3;
glob MIN_TOOL_CATEGORIES_FOR_HIGH_CONFIDENCE: int = 3;
glob MIN_PROMOTED_FOR_HIGH: int = 8;
glob MIN_INDEPENDENT_CATEGORIES_FOR_HIGH: int = 3;
glob EXPECTED_EVIDENCE_CATEGORIES: set = {"market", "statistical", "news", "wallet", "network"};

glob LEGAL_THRESHOLDS: dict = {
    "sar_filing": {
        "min_confidence": "HIGH",
        "min_independent_signals": 3,
        "requires_wallet_linkage": True
    },
    "regulatory_referral": {
        "min_confidence": "HIGH",
        "requires_pre_news_trading": True,
        "requires_wallet_identity": True
    },
    "enforcement_action": {"allowed": False}
};

glob STRONG_LEGAL_PHRASES: list = [
    "mandatory sar", "sar filing required", "file a sar",
    "immediate enforcement", "enforcement action",
    "threshold met for referral", "must be referred",
    "criminal referral", "prosecut"
];


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def tool_category(tool_name: str) -> str {
    for (cat, tools) in TOOL_CATEGORIES.items() {
        if tool_name in tools {
            return cat;
        }
    }
    return "unknown";
}

def make_call_key(tool_name: str, tool_args: dict) -> str {
    return f"{tool_name}:{tuple(sorted([(k, str(v)) for (k, v) in tool_args.items()]))}";
}


# ─────────────────────────────────────────────────────────────────────────────
# Data types (Artifact & EvidenceItem imported from .evidence)
# ─────────────────────────────────────────────────────────────────────────────

node InvestigationNode {
    has goal: str = "";
    has hypothesis: str = "";
    has question: str = "";
    has notes: str = "";
    has is_open: bool = True;
    has conclusions: list = [];
    has artifacts: list = [];
    has depth: int = 0;
    has child_count: int = 0;
    has error_count: int = 0;
    has is_root: bool = False;
    has node_id: str = "";
    has tool_used: str = "";
    has children: list = [];
    has used_tools: set = set();
    has tool_history: list = [];
    has failed_tools: list = [];
    has ancestor_tools: list = [];
}

edge InvestigationEdge {
    has tool_name: str = "";
}


# ─────────────────────────────────────────────────────────────────────────────
# Walker: DFS Tree of Thought engine
# ─────────────────────────────────────────────────────────────────────────────

walker Investigator {
    has goal: str = "";
    has market_id: str = "";
    has event_timestamp: str = "";
    has max_depth: int = 6;
    has max_children: int = 4;
    has max_errors: int = 3;
    has llm: LLMEngine = LLMEngine();
    has tools: ToolRegistry = ToolRegistry();
    has final_report: str = "";
    has node_stack: list = [];
    has verbose: bool = True;

    # Counters
    has total_tool_calls: int = 0;
    has total_llm_calls: int = 0;
    has base_max_tool_calls: int = 20;
    has max_total_tool_calls: int = 20;
    has start_time: float = 0.0;

    # Evidence system
    has evidence_ledger: list = [];
    has _tool_categories_used: set = set();
    has _successful_tool_names: list = [];
    has _integrity_violations: list = [];
    has _unavailable_tools: set = set();
    has _source_limitations: list = [];
    has _corroboration_status: dict = {
        "public_news_timeline": "not_investigated",
        "wallet_profiling": "not_investigated",
        "trade_timing_scores": "not_investigated"
    };
    has _evidence_families: set = set();
    has _bootstrap_trade_data: list = [];

    # Logger
    has logger: InvestigationLogger = InvestigationLogger();

    # ── on_entry: DFS loop — evaluate, plan, execute, recurse ────────────
    can on_entry with InvestigationNode entry {
        self.node_stack.append(here);
        pad = "  " * here.depth;
        self._log(f"\n{pad}[NODE depth={here.depth}] {here.node_id}");
        if here.hypothesis {
            self._log(f"{pad}  H: {here.hypothesis[:80]}");
        }
        if here.question {
            self._log(f"{pad}  Q: {here.question[:80]}");
        }
        if self.logger {
            self.logger.log_node_enter(
                node_id=here.node_id, depth=here.depth,
                hypothesis=here.hypothesis, question=here.question,
                is_root=here.is_root, artifact_count=len(here.artifacts));
        }

        if not here.is_open {
            return;
        }
        if here.depth >= self.max_depth {
            self._close_node(here, "Max depth reached.");
            return;
        }

        _fruitless = 0;
        _max_fruitless = self.max_children + self.max_errors + 2;

        while here.is_open {
            if _fruitless >= _max_fruitless {
                reason = f"Exploration exhausted: {_fruitless} consecutive iterations without a successful new tool call";
                self._log(f"{pad}  [EXHAUSTED] {reason}");
                self._close_node(here, reason);
                break;
            }

            # Dynamic budget expansion
            self._maybe_expand_budget();

            if self.total_tool_calls >= self.max_total_tool_calls {
                self._close_node(here, "Global tool call limit reached.");
                break;
            }

            if here.child_count >= self.max_children {
                if here.is_root and not self._root_may_close() {
                    total_root_children = len(here.children);
                    max_root_total = self.max_children * 3;
                    if total_root_children >= max_root_total {
                        self._log(f"{pad}  [ROOT EXHAUSTED] {total_root_children} total children spawned, closing");
                        self._close_node(here, "Exploration exhausted (insufficient tools available)");
                        break;
                    }
                    self._log(f"{pad}  [ROOT CONSTRAINED] max_children reached but evidence insufficient — resetting");
                    here.child_count = 0;
                } else {
                    reason = "Max children reached" + (" (sufficient evidence)" if here.is_root else "");
                    self._close_node(here, reason);
                    break;
                }
            }

            if here.error_count >= self.max_errors {
                if here.is_root and not self._root_may_close() {
                    total_root_children = len(here.children);
                    max_root_total = self.max_children * 3;
                    if total_root_children >= max_root_total {
                        self._close_node(here, "Exploration exhausted (too many errors)");
                        break;
                    }
                    self._log(f"{pad}  [ROOT CONSTRAINED] max_errors reached but evidence insufficient — resetting errors");
                    here.error_count = 0;
                } else {
                    self._close_node(here, "Too many errors at this node.");
                    break;
                }
            }

            # ── EVALUATE ──
            self._log(f"{pad}  [EVAL] ...");
            self.total_llm_calls += 1;
            eval_r = self.llm.evaluate_node(
                goal=here.goal, hypothesis=here.hypothesis,
                question=here.question, notes=here.notes,
                artifacts=self._fmt(here.artifacts), conclusions=here.conclusions,
                available_tools=self.tools.list_tools(), is_root=here.is_root);
            if self.logger {
                self.logger.log_llm_call("evaluate_node",
                    f"node={here.node_id} depth={here.depth} is_root={here.is_root}",
                    eval_r, error=eval_r.get("error"));
            }

            if eval_r.get("error") {
                here.error_count += 1;
                _fruitless += 1;
                self._log(f"{pad}  [EVAL ERROR] {eval_r['error']}");
                continue;
            }

            if eval_r.get("should_close", False) {
                if here.is_root and not self._root_may_close() {
                    cats = len(self._tool_categories_used);
                    self._log(f"{pad}  [ROOT CLOSE BLOCKED] {self.total_tool_calls} calls, {cats} categories");
                    # Fall through to PLAN
                } else {
                    if here.is_root {
                        reason = f"Sufficient evidence: {self.total_tool_calls} tool calls, {len(self._tool_categories_used)} categories";
                        self._log(f"{pad}  [ROOT CLOSE — SUFFICIENT EVIDENCE] {reason}");
                        self._close_node(here, f"Sufficient evidence gathered ({reason})");
                    } else {
                        reason = eval_r.get("close_reason", "LLM decided to close.");
                        self._log(f"{pad}  [CLOSE] {reason}");
                        self._close_node(here, reason);
                    }
                    break;
                }
            }

            # ── PLAN ──
            self._log(f"{pad}  [PLAN] ...");
            available = self._get_available_tools();
            priority_ctx = self._build_priority_context();
            enriched_notes = here.notes;
            if priority_ctx {
                enriched_notes = (here.notes or "") + "\n" + priority_ctx;
                self._log(f"{pad}  [PRIORITY] Injecting priority targets");
            }
            # Inject ancestor tool history so LLM avoids repeating tools
            if here.ancestor_tools {
                ancestor_names = [f"{t[0]}({t[1]})" for t in here.ancestor_tools[-10:]];
                enriched_notes += "\nALREADY CALLED BY PARENT NODES (avoid repeating with same args):\n  " + "\n  ".join(ancestor_names);
            }
            self.total_llm_calls += 1;
            plan = self.llm.plan_next_step(
                goal=here.goal, hypothesis=here.hypothesis,
                question=here.question, notes=enriched_notes,
                artifacts=self._fmt(here.artifacts), conclusions=here.conclusions,
                available_tools=available, failed_tools=here.failed_tools);
            if self.logger {
                self.logger.log_llm_call("plan_next_step",
                    f"node={here.node_id} failed_tools={len(here.failed_tools)}",
                    plan, error=plan.get("error"));
            }

            if plan.get("error") {
                here.error_count += 1;
                self._log(f"{pad}  [PLAN ERROR] {plan['error']} — correcting...");
                self.total_llm_calls += 1;
                plan = self.llm.correct_plan(bad_plan=plan,
                    available_tools=self.tools.list_tools(), error=plan.get("error", ""));
                if plan.get("error") {
                    self._log(f"{pad}  [PLAN CORRECTION FAILED] {plan['error']}");
                    _fruitless += 1;
                    continue;
                }
            }

            tool_name = plan.get("tool_name", "");
            tool_args = plan.get("tool_args", {});

            # Source-aware: reject structurally unavailable tools
            if tool_name in self._unavailable_tools {
                self._log(f"{pad}  [SOURCE-AWARE] {tool_name} is unavailable — skipping");
                here.error_count += 1;
                _fruitless += 1;
                here.failed_tools.append(f"{tool_name} (structurally unavailable)");
                continue;
            }

            # Context integrity enforcement
            tool_args = self._enforce_context_integrity(tool_name, tool_args);

            # Loop detection
            call_key = make_call_key(tool_name, tool_args);
            if call_key in here.used_tools {
                self._log(f"{pad}  [LOOP DETECTED] {tool_name}");
                here.error_count += 1;
                _fruitless += 1;
                here.failed_tools.append(f"{tool_name} (duplicate call)");
                if self.logger {
                    self.logger.log_loop_detected(tool_name, here.node_id, here.depth);
                }
                continue;
            }

            self._log(f"{pad}  [TOOL] {tool_name}({tool_args})");
            self.total_tool_calls += 1;
            here.used_tools.add(call_key);
            here.tool_history.append((tool_name, tool_args));

            # ── EXECUTE ──
            tool_result = self.tools.call(tool_name, tool_args);

            if tool_result.get("error") {
                here.error_count += 1;
                _fruitless += 1;
                error_msg = tool_result["error"];
                here.notes += f"\n[TOOL ERROR]: {tool_name} failed: {error_msg}";
                here.failed_tools.append(f"{tool_name}: {error_msg}");
                self._log(f"{pad}  [TOOL ERROR] {error_msg}");
                if self.logger {
                    self.logger.log_tool_call(tool_name, tool_args, False, error=error_msg);
                }
                continue;
            }

            # SUCCESS
            _fruitless = 0;
            summary = tool_result.get("summary", "");
            self._log(f"{pad}  [RESULT] {summary[:100]}");
            if self.logger {
                self.logger.log_tool_call(tool_name, tool_args, True, summary=summary);
            }

            self._extract_evidence(tool_name, tool_result, here.node_id, here.depth + 1);
            self._tool_categories_used.add(tool_category(tool_name));
            self._successful_tool_names.append(tool_name);

            # Enhanced logging for news+timing tools
            data = tool_result.get("data", {});
            if isinstance(data, dict) {
                if "queries_generated" in data {
                    self._log(f"{pad}  [NEWS QUERY GENERATED] {data.get('queries_generated', [])}");
                }
                if "relevant_article_count" in data and "total_raw_results" in data {
                    self._log(f"{pad}  [ARTICLES FILTERED] {data['total_raw_results']} -> {data['relevant_article_count']}");
                }
                if "pre_news_wallet_count" in data and data.get("pre_news_wallet_count") is not None {
                    total = data.get("wallets_scored", 0);
                    self._log(f"{pad}  [PRE-NEWS WALLETS] {data['pre_news_wallet_count']} / {total}");
                }
                if "pct_volume_before_news" in data and data.get("pct_volume_before_news") is not None {
                    self._log(f"{pad}  [PRE-NEWS VOLUME] {data['pct_volume_before_news']}%");
                }
            }

            # Build artifact and child node
            artifact = Artifact(
                data=tool_result.get("data"), summary=summary,
                data_visible_to_ai=plan.get("data_visible_to_ai", False),
                source_tool=tool_name, created_at_depth=here.depth + 1);

            child_id = f"{tool_name}_{random.randint(10000, 99999)}";
            child_ancestor_tools = here.ancestor_tools + list(here.tool_history);
            child = InvestigationNode(
                goal=here.goal, hypothesis=plan.get("child_hypothesis", ""),
                question=plan.get("child_question", ""), notes=plan.get("child_notes", ""),
                is_open=True, depth=here.depth + 1,
                node_id=child_id, tool_used=tool_name,
                artifacts=here.artifacts + [artifact],
                ancestor_tools=child_ancestor_tools);

            here.children.append(child);
            here.child_count += 1;
            here ++> child;
            visit child;
            # After child DFS completes, the while loop continues on this node
        }
        # End of while loop — node is closed
    }

    # ── on_exit: bubble conclusions up to parent (backtracking) ─────────────
    can on_exit with InvestigationNode exit {
        close_reason = "";
        if not here.is_open {
            for c in here.conclusions {
                if c.startswith("[Closed]:") {
                    close_reason = c[len("[Closed]: "):];
                    break;
                }
            }
        }
        if self.logger {
            self.logger.log_node_exit(node_id=here.node_id, depth=here.depth,
                is_open=here.is_open, close_reason=close_reason, conclusions=here.conclusions);
        }

        if here.conclusions and len(self.node_stack) >= 2 {
            parent = self.node_stack[-2];
            if not here.is_open {
                self.total_llm_calls += 1;
                branch_summary = self.llm.summarize_branch(
                    hypothesis=here.hypothesis, question=here.question,
                    artifacts=self._fmt(here.artifacts), conclusions=here.conclusions);
                parent.conclusions.append(branch_summary);
                self._log(f"{'  '*here.depth}  [BACKTRACK] conclusion -> parent");
                if self.logger {
                    self.logger.log_backtrack(child_id=here.node_id, parent_id=parent.node_id,
                        child_depth=here.depth, summary=branch_summary);
                }
            } else {
                for c in here.conclusions {
                    parent.conclusions.append(c);
                }
            }
        }

        if self.node_stack and self.node_stack[-1] is here {
            self.node_stack.pop();
        }
    }

    # ── Helper methods ──────────────────────────────────────────────────────

    def _log(msg: str) {
        if self.verbose {
            print(msg);
        }
    }

    def _close_node(`node: InvestigationNode, reason: str) {
        `node.is_open = False;
        `node.conclusions.append(f"[Closed]: {reason}");
    }

    def _fmt(artifacts: list) -> list {
        result = [];
        for a in artifacts {
            entry = {"tool": a.source_tool, "summary": a.summary, "depth": a.created_at_depth};
            if a.data_visible_to_ai {
                data_str = str(a.data);
                entry["data"] = data_str[:2000] + "... [TRUNCATED]" if len(data_str) > 2000 else data_str;
            }
            result.append(entry);
        }
        return result;
    }

    def _root_may_close() -> bool {
        basic = (self.total_tool_calls >= MIN_TOOL_CALLS_FOR_ROOT_CLOSE
                 and len(self._tool_categories_used) >= MIN_TOOL_CATEGORIES_FOR_ROOT_CLOSE);
        if not basic {
            return False;
        }
        has_strong_clusters = any(
            e.promoted and "cluster" in e.metric_name
            and isinstance(e.value, (int, float)) and e.value >= 70
            for e in self.evidence_ledger
        );
        if has_strong_clusters {
            missing_count = sum(
                1 for v in self._corroboration_status.values()
                if v == "not_investigated"
            );
            if missing_count >= 2 and self.total_tool_calls < self.max_total_tool_calls {
                self._log(f"  [ESCALATION] Strong cluster evidence found but {missing_count} corroboration targets not yet attempted");
                return False;
            }
        }
        return True;
    }

    def _get_available_tools() -> list {
        all_tools = self.tools.list_tools();
        if not self._unavailable_tools {
            return all_tools;
        }
        return [t for t in all_tools if t["name"] not in self._unavailable_tools];
    }

    def _build_priority_context() -> str {
        lines = [];
        missing_targets = {k: v for (k, v) in self._corroboration_status.items()
                          if v in ("not_investigated", "unavailable")};
        if not missing_targets {
            return "";
        }
        both_news_and_timing_missing = (
            self._corroboration_status.get("public_news_timeline") in ("not_investigated", "unavailable")
            and self._corroboration_status.get("trade_timing_scores") in ("not_investigated", "unavailable")
        );
        has_clusters = any(
            e.promoted and "cluster" in e.metric_name
            and isinstance(e.value, (int, float)) and e.value >= 50
            for e in self.evidence_ledger
        );

        lines.append("\nPRIORITY TARGETS (MUST address before concluding):");
        if has_clusters and both_news_and_timing_missing {
            if "analyze_pre_news_trading" not in self._unavailable_tools {
                lines.append("  *** CRITICAL: Clusters detected — IMMEDIATELY use analyze_pre_news_trading "
                             "to assess pre-news positioning. This is the PRIMARY insider-trading signal. ***");
            }
        }

        priority_tools = {
            "public_news_timeline": ["analyze_pre_news_trading", "search_news", "get_event_news_timeline",
                                     "correlate_market_trades_with_news"],
            "wallet_profiling": ["compare_trader_to_peers", "score_trade_timing",
                                 "score_top_suspicious_wallets"],
            "trade_timing_scores": ["analyze_pre_news_trading", "score_trade_timing",
                                    "score_top_suspicious_wallets", "compare_trader_to_peers"]
        };
        for (target, status) in missing_targets.items() {
            label = target.replace("_", " ").title();
            tls = priority_tools.get(target, []);
            available_priority = [t for t in tls if t not in self._unavailable_tools];
            if available_priority {
                lines.append(f"  - {label}: {status.upper()} — USE: {', '.join(available_priority)}");
            } else {
                lines.append(f"  - {label}: {status.upper()} — no available tools (all unavailable)");
            }
        }
        lines.append("DO NOT skip these targets. Prioritize them over all other actions.");
        lines.append("DO NOT use find_synchronized_traders again if clusters already found.");
        lines.append("Without BOTH news timeline AND trade timing, you CANNOT conclude insider trading.");
        return "\n".join(lines);
    }

    def _maybe_expand_budget() {
        missing_count = sum(
            1 for v in self._corroboration_status.values()
            if v in ("not_investigated", "unavailable")
        );
        remaining = self.max_total_tool_calls - self.total_tool_calls;
        has_high_clusters = any(
            e.promoted and "cluster" in e.metric_name
            and isinstance(e.value, (int, float)) and e.value >= 70
            for e in self.evidence_ledger
        );
        trigger = (remaining <= 3 and missing_count > 0) or (has_high_clusters and missing_count >= 2);

        if trigger and missing_count > 0 {
            expansion = min(missing_count * 3, self.base_max_tool_calls // 2);
            new_max = self.max_total_tool_calls + expansion;
            max_ceiling = int(self.base_max_tool_calls * 2);
            if new_max > max_ceiling {
                new_max = max_ceiling;
            }
            if new_max > self.max_total_tool_calls {
                self._log(f"  [BUDGET] Expanding tool budget: {self.max_total_tool_calls} -> {new_max} ({missing_count} targets unresolved)");
                self.max_total_tool_calls = new_max;
            }
        }
    }

    # ── Context Integrity ────────────────────────────────────────────────────

    def _enforce_context_integrity(tool_name: str, tool_args: dict) -> dict {
        if tool_name not in TOOL_REGISTRY {
            return tool_args;
        }
        param_names = {p["name"] for p in TOOL_REGISTRY[tool_name]["params"]};
        corrected = dict(tool_args);

        if "market_id" in param_names {
            llm_market_id = corrected.get("market_id", "");
            if llm_market_id and llm_market_id != self.market_id {
                violation = {"type": "MARKET_ID_MISMATCH", "tool": tool_name,
                             "expected": self.market_id, "received": llm_market_id};
                self._integrity_violations.append(violation);
                self._log(f"  [INTEGRITY] MARKET_ID_MISMATCH in {tool_name}: expected={self.market_id} received={llm_market_id} — CORRECTED");
            }
            corrected["market_id"] = self.market_id;
        }

        if "event_timestamp" in param_names {
            llm_ts = corrected.get("event_timestamp", "");
            if llm_ts and llm_ts != self.event_timestamp {
                violation = {"type": "TIMESTAMP_MISMATCH", "tool": tool_name,
                             "expected": self.event_timestamp, "received": llm_ts};
                self._integrity_violations.append(violation);
                self._log(f"  [INTEGRITY] TIMESTAMP_MISMATCH in {tool_name}: expected={self.event_timestamp} received={llm_ts} — CORRECTED");
            }
            corrected["event_timestamp"] = self.event_timestamp;
        }

        return corrected;
    }

    def _check_integrity() -> dict {
        ts_violations = [v for v in self._integrity_violations if v["type"] == "TIMESTAMP_MISMATCH"];
        mid_violations = [v for v in self._integrity_violations if v["type"] == "MARKET_ID_MISMATCH"];
        return {
            "timestamp_ok": len(ts_violations) == 0,
            "market_id_ok": len(mid_violations) == 0,
            "timestamp_violations": ts_violations,
            "market_id_violations": mid_violations,
            "violation_count": len(self._integrity_violations),
            "all_corrected": True
        };
    }

    # ── Evidence System ──────────────────────────────────────────────────────

    def _extract_evidence(tool_name: str, tool_result: dict,
                          node_id: str, depth: int) {
        data = tool_result.get("data");
        summary = tool_result.get("summary", "");
        if data is None {
            return;
        }
        items = [];
        eid_base = f"E{len(self.evidence_ledger)+1:04d}";

        summary_lower = summary.lower();
        is_unavailable = any(marker in summary_lower for marker in UNAVAILABILITY_MARKERS);
        if is_unavailable {
            self._unavailable_tools.add(tool_name);
            limitation = f"{tool_name}: {summary[:150]}";
            if limitation not in self._source_limitations {
                self._source_limitations.append(limitation);
            }
            self._log(f"  [SOURCE-AWARE] {tool_name} marked as unavailable for this run");
        }

        if isinstance(data, dict) {
            metric_fields = {
                "abnormal_volume_ratio": "volume_ratio", "z_score": "z_score",
                "p_value": "p_value", "suspicion_level": "suspicion_level",
                "total_pre_event_drift": "price_drift", "timing_score": "timing_score",
                "behavioral_discontinuity": "behavioral_discontinuity",
                "peer_outperformance": "peer_outperformance",
                "total_volume_usdc": "total_volume", "unique_traders": "unique_traders",
                "overall_win_rate": "win_rate", "account_age_days": "account_age_days",
                "total_pnl_usdc": "total_pnl", "finding": "finding",
                "suspicious_flow_count": "suspicious_flows", "size_ratio": "size_ratio",
                "net_position_change_usdc": "net_position_change",
                "first_trade_vs_event_delta": "first_trade_vs_event_delta",
                "first_trade_vs_news_delta": "first_trade_vs_news_delta",
                "cluster_execution_span": "cluster_execution_span",
                "timing_percentile": "timing_percentile",
                "avg_timing_score": "avg_timing_score",
                "pre_news_trade_count": "pre_news_trade_count",
                "first_trade_minus_first_news_seconds": "first_trade_minus_first_news_seconds",
                "earliest_relevant_news_timestamp": "earliest_relevant_news_timestamp",
                "relevant_article_count": "relevant_article_count",
                "news_coverage_density": "news_coverage_density",
                "news_available": "news_available",
                "pre_news_volume_usdc": "pre_news_volume_usdc",
                "wallets_scored": "wallets_scored",
                "pct_wallets_before_news": "pct_wallets_before_news",
                "pct_volume_before_news": "pct_volume_before_news",
                "high_confidence_pre_news_wallets": "high_confidence_pre_news_wallets",
                "pre_news_wallet_count": "pre_news_wallet_count",
                "pct_trades_before_news": "pct_trades_before_news",
                "pre_news_signal": "pre_news_signal",
                "trading_classification": "trading_classification",
                "proxy_news_used": "proxy_news_used",
                "proxy_price_drift": "proxy_price_drift",
                "proxy_suspicion": "proxy_suspicion",
                "articles_kept": "articles_kept",
                "articles_filtered_out": "articles_filtered_out"
            };
            for (field_name, metric_name) in metric_fields.items() {
                if field_name in data {
                    val = data[field_name];
                    tier = classify_evidence_tier(val, summary, metric_name);
                    if tier == "null_metric" {
                        status = "weak";
                    } elif tier == "unavailable" {
                        status = "weak";
                    } else {
                        status = "valid";
                    }
                    eid = f"{eid_base}_{metric_name}";
                    items.append(EvidenceItem(evidence_id=eid, source_tool=tool_name,
                        metric_name=metric_name, value=val,
                        context=summary[:200], status=status, node_id=node_id,
                        depth=depth, tier=tier));
                }
            }
            if "drift_by_window" in data {
                for (window, vals) in data["drift_by_window"].items() {
                    val = vals.get("window_drift");
                    tier = classify_evidence_tier(val, summary, f"price_drift_{window}");
                    status = "valid" if tier in ("confirmed_numeric", "confirmed_structural") else "weak";
                    eid = f"{eid_base}_drift_{window}";
                    items.append(EvidenceItem(evidence_id=eid, source_tool=tool_name,
                        metric_name=f"price_drift_{window}", value=val,
                        context=f"Window: {window}", status=status, node_id=node_id,
                        depth=depth, tier=tier));
                }
            }
            if "flags" in data and isinstance(data["flags"], list) {
                for flag in data["flags"] {
                    eid = f"{eid_base}_flag_{flag}";
                    items.append(EvidenceItem(evidence_id=eid, source_tool=tool_name,
                        metric_name=f"flag_{flag}", value=True, context=summary[:200],
                        status="valid", node_id=node_id, depth=depth,
                        tier="confirmed_numeric"));
                }
            }
        } elif isinstance(data, list) {
            eid = f"{eid_base}_count";
            items.append(EvidenceItem(evidence_id=eid, source_tool=tool_name,
                metric_name="record_count", value=len(data), context=summary[:200],
                status="valid", node_id=node_id, depth=depth, tier="confirmed_numeric"));
            if data and isinstance(data[0], dict) and "suspicion_score" in data[0] {
                for (i, cluster) in enumerate(data) {
                    val = cluster.get("suspicion_score");
                    tier = classify_evidence_tier(val, summary);
                    status = "valid" if val is not None else "weak";
                    eid = f"{eid_base}_cluster{i}_suspicion";
                    items.append(EvidenceItem(evidence_id=eid, source_tool=tool_name,
                        metric_name=f"cluster_{i}_suspicion_score", value=val,
                        context=f"Cluster {i+1}: {len(cluster.get('wallets',[]))} wallets",
                        status=status, node_id=node_id, depth=depth, tier=tier));
                }
            }
        }

        if not items {
            tier = "unavailable" if is_unavailable else "weak_summary";
            items.append(EvidenceItem(evidence_id=f"{eid_base}_summary",
                source_tool=tool_name, metric_name="tool_summary",
                value=summary[:300], context="(no structured metrics)", status="weak",
                node_id=node_id, depth=depth, tier=tier));
        }

        self.evidence_ledger.extend(items);
        if self.logger {
            for item in items {
                self.logger.log_evidence(item);
            }
        }
        self._update_corroboration_status(tool_name, items, is_unavailable);
        cat = tool_category(tool_name);
        if any(i.tier in ("confirmed_numeric", "confirmed_structural") for i in items) {
            self._evidence_families.add(cat);
        }
    }

    def _update_corroboration_status(tool_name: str, items: list,
                                      is_unavailable: bool) {
        news_tools = {"search_news", "get_event_news_timeline", "check_pre_news_trades",
                      "correlate_market_trades_with_news", "get_news_sentiment_around_event",
                      "analyze_pre_news_trading"};
        if tool_name in news_tools {
            # Check if news actually returned real articles (not just zero-value metrics)
            has_real_news = any(
                i.tier in ("confirmed_numeric", "confirmed_structural")
                and i.value and i.value != 0
                and i.metric_name not in ("proxy_news_used", "proxy_suspicion", "proxy_price_drift")
                for i in items
            );
            if is_unavailable {
                self._corroboration_status["public_news_timeline"] = "unavailable";
            } elif has_real_news {
                self._corroboration_status["public_news_timeline"] = "confirmed";
            } elif self._corroboration_status["public_news_timeline"] == "not_investigated" {
                self._corroboration_status["public_news_timeline"] = "unavailable";
            }
        }
        wallet_tools = {"get_wallet_profile", "get_wallet_pnl",
                        "get_wallet_win_rate_by_market_type", "get_wallet_first_activity"};
        if tool_name in wallet_tools {
            if is_unavailable {
                self._corroboration_status["wallet_profiling"] = "unavailable";
            } elif any(i.tier in ("confirmed_numeric", "confirmed_structural")
                     and i.value is not None for i in items) {
                self._corroboration_status["wallet_profiling"] = "confirmed";
            } elif self._corroboration_status["wallet_profiling"] == "not_investigated" {
                self._corroboration_status["wallet_profiling"] = "unavailable";
            }
        }
        timing_tools = {"score_trade_timing", "compare_trader_to_peers",
                        "score_top_suspicious_wallets", "analyze_pre_news_trading"};
        if tool_name in timing_tools {
            if is_unavailable {
                self._corroboration_status["trade_timing_scores"] = "unavailable";
            } elif any(i.tier in ("confirmed_numeric", "confirmed_structural")
                     and i.value is not None for i in items) {
                self._corroboration_status["trade_timing_scores"] = "confirmed";
            } elif self._corroboration_status["trade_timing_scores"] == "not_investigated" {
                self._corroboration_status["trade_timing_scores"] = "unavailable";
            }
        }
    }

    def _promote_evidence() {
        for item in self.evidence_ledger {
            if item.status != "valid" { continue; }
            if item.metric_name == "tool_summary" { continue; }
            if isinstance(item.value, str) and len(item.value) > 200 { continue; }
            if item.tier in ("null_metric", "unavailable", "weak_summary") { continue; }
            if item.value is None { continue; }
            item.promoted = True;
        }
    }

    def _identify_missing_evidence() -> list {
        missing = [];
        cats = self._tool_categories_used;
        if "news" not in cats {
            missing.append("No public news timeline — cannot confirm pre-news trading");
        }
        if "network" not in cats {
            missing.append("No fund flow analysis — cannot confirm shared funding paths");
        }
        if "wallet" not in cats {
            missing.append("No wallet profiling — cannot confirm per-wallet win rates");
        }
        promoted = [e for e in self.evidence_ledger if e.promoted];
        metric_names = {e.metric_name for e in promoted};
        if "timing_score" not in metric_names {
            missing.append("No trade timing scores — cannot confirm pre-event positioning");
        }
        if not any("cluster" in m for m in metric_names) {
            if "find_synchronized_traders" not in self._successful_tool_names {
                missing.append("No synchronized trading analysis");
            }
        }
        return missing;
    }

    def _has_corroboration_beyond_clustering() -> bool {
        promoted = [e for e in self.evidence_ledger if e.promoted];
        non_cluster_signals = [
            e for e in promoted
            if "cluster" not in e.metric_name
            and e.source_tool != "find_synchronized_traders"
            and e.metric_name not in ("record_count", "tool_summary")
            and e.tier in ("confirmed_numeric", "confirmed_structural")
        ];
        return len(non_cluster_signals) > 0;
    }

    def _compute_confidence() -> str {
        n_promoted = len([e for e in self.evidence_ledger if e.promoted]);
        n_evidence_families = len(self._evidence_families);
        has_integrity_errors = len(self._integrity_violations) > 0;
        has_attribution = bool(self._tool_categories_used & {"wallet", "network"});
        missing = self._identify_missing_evidence();
        has_major_missing = len(missing) > 0;

        if self.total_tool_calls < MIN_TOOL_CALLS_FOR_ROOT_CLOSE {
            return "LOW";
        }
        if n_promoted < MIN_EVIDENCE_ITEMS_FOR_SUFFICIENT {
            return "LOW";
        }
        has_null_promoted = any(e.promoted and e.value is None for e in self.evidence_ledger);
        has_corroboration_beyond_clustering = self._has_corroboration_beyond_clustering();
        confirmed_targets = sum(1 for v in self._corroboration_status.values() if v == "confirmed");

        # HIGH gate
        if (not has_integrity_errors
                and n_evidence_families >= MIN_INDEPENDENT_CATEGORIES_FOR_HIGH
                and n_promoted >= MIN_PROMOTED_FOR_HIGH
                and has_attribution
                and not has_major_missing
                and not has_null_promoted
                and confirmed_targets >= 2
                and has_corroboration_beyond_clustering) {
            return "HIGH";
        }

        # MEDIUM gate — must have real substantive evidence
        non_zero_promoted = len([
            e for e in self.evidence_ledger
            if e.promoted and e.value != 0 and e.value is not None
            and e.metric_name not in ("proxy_news_used", "proxy_price_drift")
        ]);
        if (n_evidence_families >= 2
                and n_promoted >= 4
                and non_zero_promoted >= 3
                and has_corroboration_beyond_clustering
                and not has_null_promoted
                and not has_major_missing) {
            return "MEDIUM";
        }

        return "LOW";
    }

    # ── Report Generation ────────────────────────────────────────────────────

    def _generate_gated_report(root_node: InvestigationNode) -> str {
        meaningful = [c for c in root_node.conclusions if not c.startswith("[Closed]:")];
        confidence = self._compute_confidence();
        is_sufficient = confidence in ("MEDIUM", "HIGH");

        if not is_sufficient {
            self._log("[REPORT] WARNING: Insufficient evidence gathered.");
            `report = self._build_insufficient_report(root_node, meaningful, confidence);
        } else {
            self.total_llm_calls += 1;
            evidence_text = self._format_evidence_for_report();
            `report = self.llm.generate_final_report(
                goal=self.goal, market_id=self.market_id,
                all_conclusions=meaningful, artifacts=self._fmt(root_node.artifacts),
                evidence_summary=evidence_text, confidence=confidence);
        }

        recommendations = self._compute_recommendations(confidence);
        `report = self._sanitize_legal_language(`report, recommendations);

        `report += "\n\n" + self._build_findings_summary(meaningful, confidence);
        `report += "\n\n" + self._build_evidence_synthesis();
        `report += "\n\n" + self._build_suspect_wallets_summary();
        `report += "\n\n" + self._build_narrative_synthesis();
        `report += "\n\n" + self._build_pre_news_metrics_summary();
        `report += "\n\n" + self._build_evidence_coverage_summary();
        `report += "\n\n" + self._build_source_limitations_summary();
        `report += "\n\n" + self._build_corroboration_status_section();
        `report += "\n\n" + self._build_upgrade_recommendations();
        `report += "\n\n" + self._build_integrity_audit();

        if self.logger {
            self.logger.log_final_report(
                conclusions_count=len(root_node.conclusions), meaningful_count=len(meaningful),
                sufficient_evidence=is_sufficient, total_tool_calls=self.total_tool_calls,
                confidence=confidence,
                evidence_count=len([e for e in self.evidence_ledger if e.promoted]),
                categories_used=list(self._tool_categories_used), report_preview=`report);
        }
        return `report;
    }

    def _build_insufficient_report(root_node: InvestigationNode, meaningful: list, confidence: str) -> str {
        lines = [
            "WARNING: INSUFFICIENT EVIDENCE — LOW CONFIDENCE REPORT", "",
            f"Market: {self.market_id}", f"Goal: {self.goal}",
            f"Confidence: {confidence}", "",
            f"Tool calls made: {self.total_tool_calls}",
            f"Tool categories used: {', '.join(sorted(self._tool_categories_used)) or 'none'}",
            f"Evidence items collected: {len(self.evidence_ledger)}",
            f"Valid evidence items: {len([e for e in self.evidence_ledger if e.status == 'valid'])}",
            f"Meaningful conclusions: {len(meaningful)}", ""
        ];
        if self.evidence_ledger {
            lines.append("Evidence collected (insufficient for strong conclusions):");
            for e in self.evidence_ledger {
                lines.append(f"  [{e.evidence_id}] {e.source_tool} -> {e.metric_name} = {e.value} ({e.status})");
            }
            lines.append("");
        }
        if meaningful {
            lines.append("Partial conclusions:");
            for (i, c) in enumerate(meaningful) {
                lines.append(f"  [{i+1}] {c[:200]}");
            }
            lines.append("");
        }
        lines.append("FINDING: Investigation incomplete. More diverse tool calls required.");
        lines.append(f"\nWARNING: Only {len(meaningful)} conclusion(s) from {self.total_tool_calls} tool call(s). Confidence: {confidence}.");
        return "\n".join(lines);
    }

    def _format_evidence_for_report() -> str {
        promoted = [e for e in self.evidence_ledger if e.promoted];
        unconfirmed = [e for e in self.evidence_ledger if e.status == "valid" and not e.promoted];
        missing = self._identify_missing_evidence();

        lines = ["EVIDENCE LEDGER — CONFIRMED (promoted, may be cited as findings):"];
        for e in promoted {
            lines.append(f"  [{e.evidence_id}] {e.source_tool} | {e.metric_name} = {e.value} | {e.context[:100]}");
        }
        if unconfirmed {
            lines.append("\nPROVISIONAL (not promoted — may be noted but NOT cited as confirmed):");
            for e in unconfirmed {
                lines.append(f"  [{e.evidence_id}] {e.source_tool} | {e.metric_name} = {e.value} (PROVISIONAL)");
            }
        }
        if missing {
            lines.append("\nMISSING EVIDENCE (gaps that reduce confidence):");
            for m in missing {
                lines.append(f"  - {m}");
            }
        }
        lines.append(f"\nCONFIDENCE: {self._compute_confidence()}");
        lines.append(f"CATEGORIES: {', '.join(sorted(self._tool_categories_used))}");
        lines.append("\nMANDATORY CORROBORATION STATUS:");
        for (target, status) in self._corroboration_status.items() {
            label = target.replace("_", " ").title();
            lines.append(f"  - {label}: {status.upper()}");
        }
        all_missing = all(v in ("not_investigated", "unavailable") for v in self._corroboration_status.values());
        if all_missing {
            lines.append("  WARNING: All 3 mandatory corroboration targets are MISSING.");
            lines.append("  You MUST NOT conclude insider trading.");
        }
        lines.append("\nRULES:");
        lines.append("- CONFIRMED findings must cite evidence IDs from the CONFIRMED section only");
        lines.append("- PROVISIONAL data must be labeled PROVISIONAL and must NOT increase confidence");
        lines.append("- MISSING evidence must REDUCE confidence, not just be a caveat");
        lines.append("- Do NOT use legal language: SAR, enforcement action, mandatory referral, criminal referral");
        lines.append("- State uncertainty explicitly: 'evidence suggests' not 'this proves'");
        lines.append("- Cluster evidence requires corroboration from trade timing or peer outperformance");
        return "\n".join(lines);
    }

    def _build_findings_summary(meaningful: list, confidence: str) -> str {
        promoted = [e for e in self.evidence_ledger if e.promoted];
        provisional = [e for e in self.evidence_ledger if e.status == "valid" and not e.promoted];
        missing = self._identify_missing_evidence();
        cats = sorted(self._tool_categories_used);
        sections = [];

        sections.append("## SUMMARY OF FINDINGS");
        sections.append("");
        sections.append(
            f"This investigation examined market '{self.market_id}' for signs of "
            f"insider trading, using {self.total_tool_calls} analytical tools across "
            f"{len(cats)} category/categories ({', '.join(cats)}).");
        sections.append("");

        confirmed_targets = sum(1 for v in self._corroboration_status.values() if v == "confirmed");
        all_missing = all(v in ("not_investigated", "unavailable") for v in self._corroboration_status.values());
        news_missing = self._corroboration_status.get("public_news_timeline") in ("not_investigated", "unavailable");
        timing_missing = self._corroboration_status.get("trade_timing_scores") in ("not_investigated", "unavailable");

        if all_missing {
            sections.append("### CONCLUSION LIMIT");
            sections.append("All 3 mandatory corroboration targets are missing or unavailable. "
                           "This investigation CANNOT conclude insider trading.");
            sections.append("");
        } elif news_missing or timing_missing {
            missing_names = [];
            if news_missing { missing_names.append("public news timeline"); }
            if timing_missing { missing_names.append("trade timing scores"); }
            sections.append("### CONCLUSION LIMIT");
            sections.append(f"{confirmed_targets} of 3 mandatory corroboration targets confirmed. "
                           f"Missing: {', '.join(missing_names)}. Cannot conclude insider trading.");
            sections.append("");
        }

        # Trading classification gate
        trading_class = None;
        for e in promoted {
            if e.metric_name == "trading_classification" {
                trading_class = e.value;
                break;
            }
        }
        if trading_class and "POST-NEWS CLUSTERING" in str(trading_class) {
            sections.append("### SIGNAL INTERPRETATION");
            sections.append("High timing scores detected, but ALL wallet trades occurred AFTER public news. "
                           "This is post-news clustering (crowd reaction), NOT insider trading.");
            sections.append("");
        } elif trading_class and "POSSIBLE INSIDER" in str(trading_class) {
            sections.append("### SIGNAL INTERPRETATION");
            sections.append("Pre-news trading detected with strong timing. Consistent with possible insider trading.");
            sections.append("");
        }

        if promoted {
            sections.append("### CONFIRMED (backed by promoted evidence)");
            for e in promoted {
                if isinstance(e.value, (int, float)) {
                    sections.append(f"- {e.metric_name} = {e.value} (source: {e.source_tool}) [{e.evidence_id}]");
                } elif isinstance(e.value, str) and len(e.value) < 50 {
                    sections.append(f"- {e.metric_name} = {e.value} (source: {e.source_tool}) [{e.evidence_id}]");
                }
            }
            sections.append("");
        }
        if provisional {
            sections.append("### PROVISIONAL (not promoted — informational only)");
            for e in provisional[:5] {
                sections.append(f"- {e.metric_name} from {e.source_tool} [{e.evidence_id}] (PROVISIONAL)");
            }
            if len(provisional) > 5 {
                sections.append(f"- ... and {len(provisional) - 5} more provisional items");
            }
            sections.append("");
        }
        if missing {
            sections.append("### MISSING EVIDENCE (reduces confidence)");
            for m in missing { sections.append(f"- {m}"); }
            sections.append("");
        }

        recommendations = self._compute_recommendations(confidence);
        sections.append("### RECOMMENDED ACTIONS");
        for rec in recommendations {
            met = "MET" if rec["threshold_met"] else "NOT MET";
            sections.append(f"- [{rec['level']}] {rec['text']} (threshold: {met})");
        }
        sections.append("");

        n_promoted = len(promoted);
        sections.append(
            f"Overall confidence is {confidence}, based on {n_promoted} promoted evidence "
            f"item(s) from {len(cats)} tool category/categories, "
            f"{len(meaningful)} branch conclusion(s), and "
            f"{len(missing)} identified evidence gap(s).");

        return "\n".join(sections);
    }

    def _build_pre_news_metrics_summary() -> str {
        promoted = [e for e in self.evidence_ledger if e.promoted];
        sections = ["## PRE-NEWS TRADING METRICS", ""];
        metrics = {};
        for e in promoted {
            if e.metric_name in ("earliest_relevant_news_timestamp", "pct_wallets_before_news",
                                  "pct_volume_before_news", "avg_timing_score",
                                  "high_confidence_pre_news_wallets", "pre_news_wallet_count",
                                  "relevant_article_count", "wallets_scored",
                                  "pre_news_trade_count", "pre_news_volume_usdc",
                                  "news_available", "news_coverage_density",
                                  "trading_classification", "pre_news_signal",
                                  "articles_kept", "articles_filtered_out",
                                  "proxy_news_used", "proxy_price_drift", "proxy_suspicion") {
                metrics[e.metric_name] = e.value;
            }
        }
        if not metrics {
            sections.append("No pre-news trading metrics available.");
            sections.append("");
            return "\n".join(sections);
        }
        if "news_available" in metrics { sections.append(f"- News API available: {metrics['news_available']}"); }
        if "relevant_article_count" in metrics { sections.append(f"- Relevant news articles found: {metrics['relevant_article_count']}"); }
        if "earliest_relevant_news_timestamp" in metrics { sections.append(f"- Earliest relevant news: {metrics['earliest_relevant_news_timestamp']}"); }
        if "wallets_scored" in metrics { sections.append(f"- Wallets scored for timing: {metrics['wallets_scored']}"); }
        if "avg_timing_score" in metrics { sections.append(f"- Average timing score: {metrics['avg_timing_score']}/100"); }
        if "pct_wallets_before_news" in metrics { sections.append(f"- % wallets trading before news: {metrics['pct_wallets_before_news']}%"); }
        if "pct_volume_before_news" in metrics { sections.append(f"- % volume before news: {metrics['pct_volume_before_news']}%"); }
        if "pre_news_wallet_count" in metrics { sections.append(f"- Pre-news wallet count: {metrics['pre_news_wallet_count']}"); }
        if "high_confidence_pre_news_wallets" in metrics { sections.append(f"- High-confidence pre-news wallets: {metrics['high_confidence_pre_news_wallets']}"); }
        if "pre_news_signal" in metrics { sections.append(f"- Pre-news signal: {metrics['pre_news_signal']}"); }
        if "trading_classification" in metrics { sections.append(f"- Trading classification: {metrics['trading_classification']}"); }
        if "articles_kept" in metrics { sections.append(f"- Articles kept (in event window): {metrics['articles_kept']}"); }
        if "articles_filtered_out" in metrics { sections.append(f"- Articles filtered out (post-event): {metrics['articles_filtered_out']}"); }
        if metrics.get("proxy_news_used") {
            sections.append("- Proxy news inference used: YES");
            if "proxy_price_drift" in metrics { sections.append(f"- Proxy price drift: {metrics['proxy_price_drift']}"); }
            if "proxy_suspicion" in metrics { sections.append(f"- Proxy suspicion level: {metrics['proxy_suspicion']}"); }
        }
        sections.append("");
        return "\n".join(sections);
    }

    def _build_evidence_coverage_summary() -> str {
        sections = ["## EVIDENCE COVERAGE SUMMARY", ""];
        question_map = {
            "market": ("Market structure and trading patterns", {"get_market_info", "get_market_trades", "get_market_price_history", "get_large_trades", "get_pre_event_trades", "get_market_movers"}),
            "statistical": ("Statistical anomaly detection", {"compute_abnormal_volume", "compute_price_run_up", "score_trade_timing", "compare_trader_to_peers", "find_synchronized_traders"}),
            "news": ("Public news timeline correlation", {"search_news", "get_event_news_timeline", "check_pre_news_trades", "correlate_market_trades_with_news", "get_news_sentiment_around_event", "analyze_pre_news_trading"}),
            "wallet": ("Wallet profiling and history", {"get_wallet_profile", "get_wallet_trade_history", "get_wallet_pnl", "get_wallet_win_rate_by_market_type", "get_wallet_first_activity"}),
            "network": ("Network analysis and fund flows", {"find_linked_wallets", "build_trader_network", "trace_fund_flows"})
        };
        answered = [];
        unanswered = [];
        for (cat, (desc, tools)) in question_map.items() {
            used = tools & set(self._successful_tool_names);
            unavailable = tools & self._unavailable_tools;
            if used - unavailable {
                answered.append(f"- {desc}: investigated ({', '.join(sorted(used - unavailable))})");
            } elif unavailable {
                unanswered.append(f"- {desc}: unavailable due to API limitations ({', '.join(sorted(unavailable))})");
            } else {
                unanswered.append(f"- {desc}: not investigated");
            }
        }
        sections.append("### Answered");
        sections.extend(answered if answered else ["- (none)"]);
        sections.append("");
        sections.append("### Unanswered");
        sections.extend(unanswered if unanswered else ["- (none)"]);
        sections.append("");
        return "\n".join(sections);
    }

    def _build_source_limitations_summary() -> str {
        sections = ["## SOURCE LIMITATIONS", ""];
        if self._source_limitations {
            for lim in self._source_limitations { sections.append(f"- {lim}"); }
        } else {
            sections.append("- No source limitations encountered.");
        }
        if self._unavailable_tools {
            sections.append("");
            sections.append(f"Tools marked as unavailable during this run: {', '.join(sorted(self._unavailable_tools))}");
        }
        sections.append("");
        return "\n".join(sections);
    }

    def _build_corroboration_status_section() -> str {
        sections = ["## MANDATORY CORROBORATION STATUS", ""];
        for (target, status) in self._corroboration_status.items() {
            label = target.replace("_", " ").title();
            sections.append(f"- {label}: {status.upper()}");
        }
        sections.append("");
        all_missing = all(v in ("not_investigated", "unavailable") for v in self._corroboration_status.values());
        news_missing = self._corroboration_status.get("public_news_timeline") in ("not_investigated", "unavailable");
        timing_missing = self._corroboration_status.get("trade_timing_scores") in ("not_investigated", "unavailable");
        if all_missing {
            sections.append("WARNING: All 3 mandatory corroboration targets are missing or unavailable. "
                           "The system CANNOT conclude insider trading.");
        } elif news_missing or timing_missing {
            missing_names = [];
            if news_missing { missing_names.append("public news timeline"); }
            if timing_missing { missing_names.append("trade timing scores"); }
            sections.append(f"WARNING: Critical corroboration target(s) missing: {', '.join(missing_names)}.");
        }
        sections.append("");
        return "\n".join(sections);
    }

    def _build_upgrade_recommendations() -> str {
        sections = ["## UPGRADE RECOMMENDATIONS", ""];
        recs = [];
        if self._corroboration_status["public_news_timeline"] != "confirmed" {
            recs.append("1. [HIGH IMPACT] Connect a news API to enable public news timeline reconstruction.");
        }
        if self._corroboration_status["wallet_profiling"] != "confirmed" {
            recs.append("2. [HIGH IMPACT] Integrate on-chain wallet profiling (Etherscan, Dune).");
        }
        if self._corroboration_status["trade_timing_scores"] != "confirmed" {
            recs.append("3. [MEDIUM IMPACT] Expand trade timing analysis with more granular per-wallet scoring.");
        }
        if "network" not in self._evidence_families {
            recs.append("4. [MEDIUM IMPACT] Enable on-chain fund flow tracing.");
        }
        if recs {
            sections.extend(recs);
        } else {
            sections.append("- All major data sources are available. Focus on investigation depth.");
        }
        sections.append("");
        return "\n".join(sections);
    }

    def _build_evidence_synthesis() -> str {
        promoted = [e for e in self.evidence_ledger if e.promoted];
        sections = ["## EVIDENCE SYNTHESIS", ""];
        if not promoted {
            sections.append("No promoted evidence to synthesize.");
            sections.append("");
            return "\n".join(sections);
        }
        family_map = {
            "market": {"label": "Market Behavior", "weight": 0.15,
                       "tools": {"get_market_info", "get_market_trades", "get_market_price_history",
                                 "get_large_trades", "get_pre_event_trades", "get_market_movers"}},
            "statistical": {"label": "Statistical Anomaly", "weight": 0.20,
                            "tools": {"compute_abnormal_volume", "compute_price_run_up",
                                      "find_synchronized_traders", "score_top_suspicious_wallets"}},
            "timing": {"label": "Trade Timing", "weight": 0.25,
                       "tools": {"score_trade_timing", "compare_trader_to_peers",
                                 "score_top_suspicious_wallets", "analyze_pre_news_trading"}},
            "news": {"label": "News Timeline", "weight": 0.25,
                     "tools": {"search_news", "get_event_news_timeline", "check_pre_news_trades",
                               "correlate_market_trades_with_news", "analyze_pre_news_trading"}},
            "wallet": {"label": "Wallet Behavior", "weight": 0.10,
                       "tools": {"get_wallet_profile", "get_wallet_pnl",
                                 "get_wallet_win_rate_by_market_type", "get_wallet_first_activity"}},
            "network": {"label": "Network / Fund Flow", "weight": 0.05,
                        "tools": {"find_linked_wallets", "build_trader_network", "trace_fund_flows"}}
        };
        family_evidence = {k: [] for k in family_map};
        for e in promoted {
            for (fam, info) in family_map.items() {
                if e.source_tool in info["tools"] {
                    family_evidence[fam].append(e);
                    # No break — tools like analyze_pre_news_trading belong to multiple families
                }
            }
        }
        supporting = [];
        missing_families = [];
        for (fam, info) in family_map.items() {
            items = family_evidence[fam];
            if items {
                raw = len(items) * 10;
                capped = min(100, raw);
                weighted = round(capped * info["weight"], 1);
                supporting.append({
                    "family": info["label"], "weight": info["weight"],
                    "item_count": len(items), "contribution": weighted,
                    "key_metrics": [f"{e.metric_name}={e.value}" for e in items[:3]]
                });
            } else {
                missing_families.append(info["label"]);
            }
        }
        sections.append("### Supporting Evidence Families");
        if supporting {
            for s in supporting {
                metrics_str = ", ".join(s["key_metrics"]);
                sections.append(f"- **{s['family']}** (weight: {s['weight']:.0%}, {s['item_count']} items, "
                               f"contribution: {s['contribution']}): {metrics_str}");
            }
        } else {
            sections.append("- (none)");
        }
        sections.append("");
        sections.append("### Missing Evidence Families");
        if missing_families {
            for m in missing_families { sections.append(f"- {m}: not investigated or unavailable"); }
        } else {
            sections.append("- All evidence families represented");
        }
        sections.append("");
        if supporting {
            max_contrib = max(s["contribution"] for s in supporting);
            total_contrib = sum(s["contribution"] for s in supporting);
            if total_contrib > 0 {
                dominance = max_contrib / total_contrib;
                dominant_family = max(supporting, key=lambda s: s["contribution"])["family"];
                if dominance > 0.6 {
                    sections.append("### DOMINANCE WARNING");
                    sections.append(f"**{dominant_family}** contributes {dominance:.0%} of total evidence weight. "
                                   f"Conclusions based predominantly on a single evidence family are less reliable.");
                    sections.append("");
                }
            }
        }
        return "\n".join(sections);
    }

    def _build_suspect_wallets_summary() -> str {
        sections = ["## SUSPECT WALLETS", ""];
        scored = self._compute_wallet_risk_scores();
        if not scored {
            sections.append("No wallet-level risk scoring available (insufficient trade data).");
            sections.append("");
            return "\n".join(sections);
        }
        suspects = [w for w in scored if w["risk_score"] > 0];
        if not suspects {
            sections.append("No wallets flagged as suspicious based on available evidence.");
            sections.append("");
            return "\n".join(sections);
        }
        sections.append("| Rank | Wallet | Risk Score | Volume (USDC) | Vol % | Trades | Reasons |");
        sections.append("|------|--------|-----------|---------------|-------|--------|---------|");
        for (i, w) in enumerate(suspects[:10], 1) {
            addr = w["wallet"][:12] + "...";
            reasons = "; ".join(w["reasons"][:2]) if w["reasons"] else "—";
            sections.append(f"| {i} | `{addr}` | {w['risk_score']}/100 | "
                           f"${w['volume_usdc']:,.0f} | {w['volume_pct']}% | "
                           f"{w['trade_count']} | {reasons} |");
        }
        sections.append("");
        sections.append("**Note:** Risk scores are based on trading pattern analysis only. "
                        "A high risk score indicates unusual patterns, not confirmed misconduct.");
        sections.append("");
        return "\n".join(sections);
    }

    def _build_narrative_synthesis() -> str {
        promoted = [e for e in self.evidence_ledger if e.promoted];
        confidence = self._compute_confidence();
        sections = ["## INVESTIGATION NARRATIVE", ""];
        if not promoted {
            sections.append("Insufficient evidence to produce a narrative synthesis.");
            return "\n".join(sections);
        }
        metrics = {e.metric_name: e for e in promoted};

        # 1. Strongest evidence
        sections.append("### Strongest Evidence");
        strongest = [];
        if "pre_news_signal" in metrics {
            sig = metrics["pre_news_signal"].value;
            if sig == "NONE" {
                strongest.append("No pre-news trading detected.");
            } elif sig in ("MODERATE", "STRONG") {
                strongest.append(f"Pre-news trading signal: {sig} — wallets traded before public news.");
            }
        }
        if "avg_timing_score" in metrics {
            ts = metrics["avg_timing_score"].value;
            if isinstance(ts, (int, float)) {
                if ts >= 70 {
                    strongest.append(f"High average timing score ({ts}/100) — well-timed trades.");
                } elif ts < 30 {
                    strongest.append(f"Low average timing score ({ts}/100) — no evidence of well-timed positioning.");
                }
            }
        }
        if "suspicion_level" in metrics {
            sl = metrics["suspicion_level"].value;
            if sl == "HIGH" {
                strongest.append(f"Suspicion level: HIGH (from {metrics['suspicion_level'].source_tool})");
            } elif sl == "LOW" {
                strongest.append("Suspicion level: LOW — no anomalous patterns detected.");
            }
        }
        for s in strongest or ["No standout evidence found."] {
            sections.append(f"- {s}");
        }
        sections.append("");

        # 2. What weakens the case
        sections.append("### What Weakens the Case");
        weaknesses = [];
        missing = self._identify_missing_evidence();
        for m in missing { weaknesses.append(m); }
        news_missing = self._corroboration_status.get("public_news_timeline") in ("not_investigated", "unavailable");
        timing_missing = self._corroboration_status.get("trade_timing_scores") in ("not_investigated", "unavailable");
        if news_missing { weaknesses.append("No public news timeline available."); }
        if timing_missing { weaknesses.append("No trade timing scores."); }
        if "pct_wallets_before_news" in metrics {
            pct = metrics["pct_wallets_before_news"].value;
            if isinstance(pct, (int, float)) and pct == 0 {
                weaknesses.append("0% of scored wallets traded before news.");
            }
        }
        for w in weaknesses or ["No significant weaknesses identified."] {
            sections.append(f"- {w}");
        }
        sections.append("");

        # 3. Most plausible explanation
        sections.append("### Most Plausible Explanation");
        has_pre_news = ("pre_news_signal" in metrics and metrics["pre_news_signal"].value in ("MODERATE", "STRONG"));
        has_high_timing = ("avg_timing_score" in metrics and isinstance(metrics["avg_timing_score"].value, (int, float))
                          and metrics["avg_timing_score"].value >= 70);
        has_clusters = any("cluster" in e.metric_name and isinstance(e.value, (int, float)) and e.value >= 70
                          for e in promoted);
        classification = metrics.get("trading_classification");
        classification_val = classification.value if classification else None;

        if classification_val and "POST-NEWS CLUSTERING" in str(classification_val) {
            sections.append("High timing scores were detected, but ALL trades occurred AFTER public news. "
                           "This is post-news clustering (crowd reaction), NOT insider trading.");
        } elif has_pre_news and has_high_timing {
            sections.append("Evidence suggests informed trading: wallets positioned before public news with "
                           "high timing scores. Further investigation warranted.");
        } elif classification_val and ("UNCLASSIFIABLE" in str(classification_val) or "INSUFFICIENT PUBLIC NEWS" in str(classification_val)) {
            sections.append("No valid news timeline found. Cannot distinguish informed trading from normal behavior. "
                           "Proxy signals (price drift, timing scores) used for analysis.");
        } elif has_clusters and not has_pre_news {
            sections.append("Coordinated trading clusters detected, but no pre-news positioning found. "
                           "Most likely: coordinated but publicly-informed trading.");
        } elif not has_pre_news and not has_high_timing and not has_clusters {
            sections.append("No anomalous patterns detected. Trading activity appears normal.");
        } else {
            sections.append("Mixed signals detected. Evidence insufficient to distinguish informed trading from coincidence.");
        }
        sections.append("");

        # 4. Confidence justification
        sections.append("### Confidence Justification");
        sections.append(f"Final confidence: **{confidence}**");
        justification = self._justify_confidence(confidence);
        sections.append(f"Rationale: {justification}");
        sections.append("");

        # 5. What remains unproven
        sections.append("### Unproven");
        unproven = [];
        if self._corroboration_status.get("wallet_profiling") != "confirmed" {
            unproven.append("Wallet identities and trading history across other markets");
        }
        if "network" not in self._evidence_families {
            unproven.append("Fund flow connections between suspect wallets");
        }
        if not has_pre_news {
            unproven.append("Whether any wallet had access to non-public information");
        }
        for u in unproven or ["All key investigative questions have been addressed."] {
            sections.append(f"- {u}");
        }
        sections.append("");
        return "\n".join(sections);
    }

    def _build_integrity_audit() -> str {
        integrity = self._check_integrity();
        promoted = [e for e in self.evidence_ledger if e.promoted];
        missing = self._identify_missing_evidence();
        confidence = self._compute_confidence();
        lines = ["## INTEGRITY AUDIT", ""];
        lines.append(f"- Timestamp integrity: {'PASS' if integrity['timestamp_ok'] else 'FAIL — violations corrected'}");
        lines.append(f"- Market ID integrity: {'PASS' if integrity['market_id_ok'] else 'FAIL — violations corrected'}");
        lines.append(f"- Integrity violations detected: {integrity['violation_count']} (all auto-corrected)");
        lines.append(f"- Promoted evidence items: {len(promoted)}");
        lines.append(f"- Evidence categories: {', '.join(sorted(self._tool_categories_used))}");
        lines.append(f"- Missing evidence gaps: {len(missing)}");
        lines.append(f"- Confidence: {confidence}");
        lines.append(f"- Confidence justified: {self._justify_confidence(confidence)}");
        lines.append("");
        if integrity["violation_count"] > 0 {
            lines.append("### Violations (auto-corrected)");
            for v in self._integrity_violations {
                lines.append(f"  - {v['type']}: tool={v['tool']} expected={v['expected']} received={v['received']}");
            }
            lines.append("");
        }
        if missing {
            lines.append("### Missing Evidence");
            for m in missing { lines.append(f"  - {m}"); }
        }
        return "\n".join(lines);
    }

    def _justify_confidence(confidence: str) -> str {
        n_promoted = len([e for e in self.evidence_ledger if e.promoted]);
        n_families = len(self._evidence_families);
        has_integrity = len(self._integrity_violations) == 0;
        has_attribution = bool(self._tool_categories_used & {"wallet", "network"});
        missing = self._identify_missing_evidence();
        confirmed_targets = sum(1 for v in self._corroboration_status.values() if v == "confirmed");
        has_corroboration = self._has_corroboration_beyond_clustering();

        if confidence == "HIGH" {
            return (f"YES — {n_promoted} promoted items, {n_families} evidence families, "
                    f"no integrity violations, attribution present, "
                    f"{confirmed_targets}/3 corroboration targets confirmed");
        } elif confidence == "MEDIUM" {
            reasons = [];
            if not has_integrity { reasons.append("integrity violations detected"); }
            if n_families < MIN_INDEPENDENT_CATEGORIES_FOR_HIGH { reasons.append(f"only {n_families} evidence families"); }
            if not has_attribution { reasons.append("no wallet/network attribution"); }
            if missing { reasons.append(f"{len(missing)} evidence gaps"); }
            if confirmed_targets < 2 { reasons.append(f"only {confirmed_targets}/3 corroboration targets"); }
            if not has_corroboration { reasons.append("no corroboration beyond clustering"); }
            return f"MEDIUM not HIGH because: {'; '.join(reasons)}";
        } else {
            reasons = [];
            if n_promoted < MIN_EVIDENCE_ITEMS_FOR_SUFFICIENT { reasons.append(f"only {n_promoted} promoted items"); }
            if n_families < 2 { reasons.append(f"only {n_families} evidence families"); }
            if not has_corroboration { reasons.append("no corroboration beyond clustering"); }
            return f"LOW — {'; '.join(reasons) if reasons else 'insufficient evidence'}";
        }
    }

    # ── Legal Gating ─────────────────────────────────────────────────────────

    def _compute_recommendations(confidence: str) -> list {
        promoted = [e for e in self.evidence_ledger if e.promoted];
        cats = self._tool_categories_used;
        metric_names = {e.metric_name for e in promoted};
        recommendations = [];

        sar_thresh = LEGAL_THRESHOLDS["sar_filing"];
        sar_met = (confidence == sar_thresh["min_confidence"]
                   and len(cats) >= sar_thresh["min_independent_signals"]
                   and ("wallet" in cats or "network" in cats));
        if sar_met {
            recommendations.append({
                "level": "STRONG",
                "text": "Evidence meets threshold for SAR filing consideration",
                "threshold_met": True,
                "supporting_evidence": [e.evidence_id for e in promoted[:5]]
            });
        } else {
            recommendations.append({
                "level": "INFORMATIONAL",
                "text": "Further investigation recommended before any regulatory filing",
                "threshold_met": False,
                "supporting_evidence": []
            });
        }

        ref_thresh = LEGAL_THRESHOLDS["regulatory_referral"];
        has_pre_news = "finding" in metric_names or any("pre_news" in n for n in metric_names);
        has_wallet_id = "wallet" in cats;
        ref_met = (confidence == ref_thresh["min_confidence"] and has_pre_news and has_wallet_id);
        if ref_met {
            recommendations.append({
                "level": "MODERATE",
                "text": "Evidence supports referral for further regulatory review",
                "threshold_met": True,
                "supporting_evidence": [e.evidence_id for e in promoted
                                        if "finding" in e.metric_name or "timing" in e.metric_name]
            });
        }

        recommendations.append({
            "level": "INFORMATIONAL",
            "text": "Automated systems cannot make enforcement recommendations; human review required",
            "threshold_met": False,
            "supporting_evidence": []
        });
        return recommendations;
    }

    def _sanitize_legal_language(`report: str, recommendations: list) -> str {
        any_strong_met = any(r["threshold_met"] and r["level"] == "STRONG" for r in recommendations);
        if any_strong_met {
            return `report;
        }
        lines = `report.split("\n");
        sanitized = [];
        for line in lines {
            line_lower = line.lower();
            matched = any(phrase in line_lower for phrase in STRONG_LEGAL_PHRASES);
            if matched {
                sanitized.append("[REDACTED — legal recommendation threshold not met. Further investigation recommended.]");
            } else {
                sanitized.append(line);
            }
        }
        return "\n".join(sanitized);
    }

    # ── Wallet Risk Scoring ──────────────────────────────────────────────────

    def _compute_wallet_risk_scores() -> list {
        if not self._bootstrap_trade_data or not isinstance(self._bootstrap_trade_data, list) {
            return [];
        }
        wallets = {};
        for t in self._bootstrap_trade_data {
            w = t.get("wallet", "");
            if not w { continue; }
            if w not in wallets {
                wallets[w] = {"volume": 0, "trades": 0, "yes_trades": 0, "no_trades": 0};
            }
            wallets[w]["volume"] += t.get("size_usdc", 0);
            wallets[w]["trades"] += 1;
            direction = t.get("direction", "");
            if "YES" in direction { wallets[w]["yes_trades"] += 1; }
            elif "NO" in direction { wallets[w]["no_trades"] += 1; }
        }
        if not wallets { return []; }

        total_market_vol = sum(w["volume"] for w in wallets.values());
        scored = [];
        for (addr, stats) in wallets.items() {
            score = 0;
            reasons = [];
            vol_pct = (stats["volume"] / max(total_market_vol, 1)) * 100;
            if vol_pct >= 10 {
                score += 30;
                reasons.append(f"high volume concentration ({vol_pct:.1f}%)");
            } elif vol_pct >= 5 {
                score += 15;
                reasons.append(f"moderate volume ({vol_pct:.1f}%)");
            }
            total_dir = stats["yes_trades"] + stats["no_trades"];
            if total_dir > 0 {
                yes_pct = stats["yes_trades"] / total_dir;
                if yes_pct >= 0.9 or yes_pct <= 0.1 {
                    score += 20;
                    direction = "YES" if yes_pct >= 0.9 else "NO";
                    reasons.append(f"strong {direction} bias ({yes_pct:.0%})");
                } elif yes_pct >= 0.8 or yes_pct <= 0.2 {
                    score += 10;
                    direction = "YES" if yes_pct >= 0.8 else "NO";
                    reasons.append(f"directional bias ({direction} {yes_pct:.0%})");
                }
            }
            if stats["trades"] <= 3 and stats["volume"] >= 1000 {
                score += 20;
                reasons.append(f"concentrated positioning ({stats['trades']} trades, ${stats['volume']:.0f})");
            }
            score = min(100, score);
            scored.append({
                "wallet": addr, "risk_score": score, "reasons": reasons,
                "volume_usdc": round(stats["volume"], 2),
                "volume_pct": round(vol_pct, 1),
                "trade_count": stats["trades"],
                "yes_trades": stats["yes_trades"],
                "no_trades": stats["no_trades"]
            });
        }
        scored.sort(key=lambda x: -x["risk_score"]);
        return scored[:20];
    }
}


# ─────────────────────────────────────────────────────────────────────────────
# Service function — called from frontend via __doFuncFetch
# ─────────────────────────────────────────────────────────────────────────────

def:priv start_investigation(market_id: str, event_timestamp: str, goal: str = "", max_depth: int = 4, max_children: int = 4) -> dict {
    if not goal {
        goal = "Detect insider trading in Polymarket market " + market_id;
    }
    max_tool_calls = int(os.environ.get("MAX_TOOL_CALLS", "20"));

    llm = LLMEngine();
    tools = ToolRegistry();
    log_path = os.environ.get("LOG_PATH", "investigation.log");
    logger = InvestigationLogger(log_path=log_path, enabled=True);

    # Bootstrap artifacts
    bootstrap_trade_data: list = [];

    market_result = get_market_info(market_id);
    market_art = Artifact(
        data=market_result.get("data"), summary=market_result.get("summary", ""),
        data_visible_to_ai=True, source_tool="get_market_info", created_at_depth=0);
    logger.log_bootstrap("get_market_info", market_result.get("summary", ""));

    trades_result = get_market_trades(market_id, None, None);
    trades_art = Artifact(
        data=trades_result.get("data"), summary=trades_result.get("summary", ""),
        data_visible_to_ai=False, source_tool="get_market_trades", created_at_depth=0);
    logger.log_bootstrap("get_market_trades", trades_result.get("summary", ""));
    if isinstance(trades_result.get("data"), list) {
        bootstrap_trade_data = trades_result["data"];
    }

    price_result = get_market_price_history(market_id, None, None);
    price_art = Artifact(
        data=price_result.get("data"), summary=price_result.get("summary", ""),
        data_visible_to_ai=False, source_tool="get_market_price_history", created_at_depth=0);
    logger.log_bootstrap("get_market_price_history", price_result.get("summary", ""));

    root_node = InvestigationNode(
        goal=goal, is_root=True, is_open=True, depth=0,
        node_id="root",
        artifacts=[market_art, trades_art, price_art]);

    investigator = Investigator(
        goal=goal, market_id=market_id, event_timestamp=event_timestamp,
        max_depth=max_depth, max_children=max_children, max_errors=3,
        llm=llm, tools=tools, verbose=True,
        base_max_tool_calls=max_tool_calls,
        max_total_tool_calls=max_tool_calls,
        logger=logger,
        _bootstrap_trade_data=bootstrap_trade_data);

    logger.log_run_start(
        market_id=market_id, event_timestamp=event_timestamp,
        goal=goal, config={
            "max_depth": max_depth, "max_children": max_children, "max_errors": 3,
            "max_total_tool_calls": max_tool_calls});

    investigator.start_time = _time.monotonic();

    # Spawn walker on root node — DFS traversal begins
    root_node spawn investigator;

    # Post-run: integrity check, evidence promotion, report generation
    integrity = investigator._check_integrity();
    investigator._promote_evidence();
    promoted_count = len([e for e in investigator.evidence_ledger if e.promoted]);
    final_report = investigator._generate_gated_report(root_node);

    elapsed = _time.monotonic() - investigator.start_time;
    logger.log_run_end(investigator.total_tool_calls, investigator.total_llm_calls, elapsed);
    logger.close();

    confidence = investigator._compute_confidence();

    return {
        "summary": final_report,
        "market_id": market_id,
        "event_timestamp": event_timestamp,
        "total_tool_calls": investigator.total_tool_calls,
        "total_llm_calls": investigator.total_llm_calls,
        "evidence_count": len(investigator.evidence_ledger),
        "promoted_count": promoted_count,
        "confidence": confidence,
        "categories": sorted(list(investigator._tool_categories_used)),
        "elapsed": round(elapsed, 1),
        "integrity": integrity
    };
}
