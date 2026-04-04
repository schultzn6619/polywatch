"""PolyWatch — LLM Engine. Wraps Claude/DeepSeek API calls."""

import json;
import os;
import time;

glob MODEL_CLAUDE: str = "claude-sonnet-4-6";
glob MODEL_DEEPSEEK: str = "deepseek-chat";
glob MAX_TOKENS: int = 2048;
glob MAX_API_RETRIES: int = 2;
glob RETRY_DELAY_S: float = 1.0;

# Load .env at module init
::py::
from pathlib import Path as _Path
_env_path = _Path(__file__).resolve().parent.parent / ".env"
if _env_path.exists():
    for _line in _env_path.read_text().splitlines():
        _line = _line.strip()
        if _line and not _line.startswith("#") and "=" in _line:
            _key, _, _val = _line.partition("=")
            __import__("os").environ.setdefault(_key.strip(), _val.strip())
::py::

obj LLMEngine {
    has provider: str = "";
    has client: object | None = None;
    has model: str = "";
    has _auth_failed: bool = False;

    def init() {
        super.init();
        self.provider = os.environ.get("LLM_PROVIDER", "anthropic").lower();
        self._auth_failed = False;
        if self.provider == "deepseek" {
            import openai;
            self.client = openai.OpenAI(
                api_key=os.environ.get("DEEPSEEK_API_KEY", ""),
                base_url="https://api.deepseek.com"
            );
            self.model = os.environ.get("DEEPSEEK_MODEL", MODEL_DEEPSEEK);
        } else {
            api_key = os.environ.get("ANTHROPIC_API_KEY", "");
            if not api_key {
                raise RuntimeError("ANTHROPIC_API_KEY not set.");
            }
            import anthropic;
            self.client = anthropic.Anthropic(api_key=api_key);
            self.model = os.environ.get("ANTHROPIC_MODEL", MODEL_CLAUDE);
        }
    }

    def evaluate_node(goal: str, hypothesis: str, question: str, notes: str,
                      artifacts: list, conclusions: list, available_tools: list,
                      is_root: bool = False) -> dict {
        system = (
            "You are an expert insider trading investigator analyzing Polymarket "
            "prediction markets. Respond ONLY with valid JSON."
        );
        artifacts_text = self._fmt_artifacts(artifacts);
        conclusions_text = "\n".join(f"- {c}" for c in conclusions) if conclusions else "None yet.";
        user = f"""Decide whether to KEEP OPEN or CLOSE this investigation node.

GOAL: {goal}
HYPOTHESIS: {hypothesis or "(Root — no hypothesis)"}
QUESTION: {question or "(Root — explore broadly)"}
NOTES: {notes or "(None)"}

ARTIFACTS:
{artifacts_text}

CONCLUSIONS FROM CHILDREN:
{conclusions_text}

IS ROOT: {is_root}

Close if: question answered, dead end, or strong conclusion reached.
Stay open if: root with unexplored angles, new evidence from children, question unanswered.

JSON only:
{{"should_close": <bool>, "close_reason": "<if closing>", "reasoning": "<brief>"}}""";
        return self._call(system, user);
    }

    def plan_next_step(goal: str, hypothesis: str, question: str, notes: str,
                       artifacts: list, conclusions: list, available_tools: list,
                       failed_tools: list | None = None) -> dict {
        system = (
            "You are an expert insider trading investigator. "
            "Select the best tool and generate hypothesis/question for the next step. "
            "Respond ONLY with valid JSON."
        );
        artifacts_text = self._fmt_artifacts(artifacts);
        conclusions_text = "\n".join(f"- {c}" for c in conclusions) if conclusions else "None yet.";
        tools_text = self._fmt_tools(available_tools);
        failed_text = "";
        if failed_tools {
            failed_text = (
                "\nTOOLS THAT FAILED (do NOT use these again):\n"
                + "\n".join(f"  - {t}" for t in failed_tools)
            );
        }
        user = f"""Plan the next investigation step.

GOAL: {goal}
HYPOTHESIS: {hypothesis or "(Root — start fresh)"}
QUESTION: {question or "(Root — pick best starting point)"}
NOTES: {notes or "(None)"}

ARTIFACTS:
{artifacts_text}

CONCLUSIONS:
{conclusions_text}
{failed_text}

TOOLS:
{tools_text}

Guidelines:
- Root: prefer get_pre_event_trades, compute_price_run_up, or get_market_movers
- Follow evidence: suspicious trades -> drill into wallets
- data_visible_to_ai=true only for small results; false for large datasets
- IMPORTANT: Do NOT include market_id or event_timestamp in tool_args — these are auto-injected by the system

JSON only:
{{"tool_name": "<exact name>", "tool_args": {{}}, "child_hypothesis": "<testable>", "child_question": "<concrete>", "child_notes": "<brief>", "data_visible_to_ai": <bool>}}""";
        return self._call(system, user);
    }

    def correct_plan(bad_plan: dict, available_tools: list, error: str) -> dict {
        system = (
            "A previous tool selection failed. Correct using only valid tools. "
            "Respond ONLY with valid JSON."
        );
        tools_text = self._fmt_tools(available_tools);
        user = f"""Previous plan failed:
ERROR: {error}
BAD PLAN: {json.dumps(bad_plan, indent=2)}

VALID TOOLS:
{tools_text}

JSON only:
{{"tool_name": "<exact name>", "tool_args": {{}}, "child_hypothesis": "<>", "child_question": "<>", "child_notes": "<>", "data_visible_to_ai": false}}""";
        return self._call(system, user);
    }

    def summarize_branch(hypothesis: str, question: str,
                         artifacts: list, conclusions: list) -> str {
        system = (
            "You are an expert insider trading investigator. "
            "Write a concise conclusion for a closed branch. "
            "Be specific: name wallets, amounts, timing, signals. "
            "State confirmed/refuted/inconclusive."
        );
        artifacts_text = self._fmt_artifacts(artifacts);
        sub_conclusions = "\n".join(f"- {c}" for c in conclusions) if conclusions else "None.";
        user = f"""Summarize this closed investigation branch.

HYPOTHESIS: {hypothesis}
QUESTION: {question}

ARTIFACTS:
{artifacts_text}

SUB-CONCLUSIONS:
{sub_conclusions}

Write 2-4 sentences. Include confirmed/refuted/inconclusive, key evidence, suspicion level.""";
        result = self._call(system, user);
        if isinstance(result, str) { return result; }
        if "error" in result { return f"[Summary failed: {result['error']}]"; }
        if "text" in result { return result["text"]; }
        return json.dumps(result);
    }

    def generate_final_report(goal: str, market_id: str, all_conclusions: list,
                              artifacts: list, evidence_summary: str = "",
                              confidence: str = "LOW") -> str {
        system = (
            "You are a senior financial crimes investigator writing a formal report. "
            "Synthesize all branches into a clear, actionable report. "
            "CRITICAL: You MUST only reference data values that appear in the CONFIRMED section of the EVIDENCE LEDGER below. "
            "Do NOT invent wallet counts, volumes, percentages, or any statistics not explicitly listed. "
            "If a data point is not in the evidence ledger, state 'data not available' instead. "
            "PROVISIONAL items may be mentioned but must be labeled PROVISIONAL and must NOT increase confidence. "
            "MISSING evidence must REDUCE your confidence assessment. "
            "Do NOT use legal language such as: SAR filing, enforcement action, mandatory referral, criminal referral, prosecution. "
            "Do NOT recommend regulatory escalation unless the evidence explicitly meets stated thresholds. "
            "Use uncertainty language: 'evidence suggests', 'indicators consistent with', not 'this proves' or 'conclusively demonstrates'."
        );
        conclusions_text = "\n\n".join(
            f"BRANCH {i+1}: {c}" for (i, c) in enumerate(all_conclusions)
        ) if all_conclusions else "No conclusions gathered.";
        artifacts_text = self._fmt_artifacts(artifacts);
        user = f"""Write the final investigation report.

GOAL: {goal}
MARKET: {market_id}
ASSIGNED CONFIDENCE LEVEL: {confidence}

BRANCH CONCLUSIONS:
{conclusions_text}

ROOT ARTIFACTS:
{artifacts_text}

{evidence_summary}

RULES:
- Use ONLY numeric values from the EVIDENCE LEDGER above
- The confidence level is {confidence} — do NOT override this
- Reference evidence IDs when making claims (e.g. "[E001_price_drift]")
- If data is missing for a claim, write "data not available"

Sections:
1. Executive Summary (2-3 sentences, reference confidence level, use uncertainty language)
2. CONFIRMED Findings (ONLY from CONFIRMED evidence, cite evidence IDs)
3. PROVISIONAL Observations (label clearly as PROVISIONAL, do not increase confidence)
4. MISSING Evidence (what would be needed for stronger conclusions)
5. Suspicious Actors (ONLY if wallet data is in CONFIRMED evidence)
6. Recommended Next Steps (do NOT use legal/regulatory language unless thresholds stated above are met)""";
        result = self._call(system, user, max_tokens=4096);
        if isinstance(result, str) { return result; }
        if "error" in result { return f"[Report generation failed: {result['error']}]"; }
        if "text" in result { return result["text"]; }
        return json.dumps(result);
    }

    def _call(system: str, user: str, max_tokens: int = 2048) -> dict {
        if self._auth_failed {
            return {"error": "API authentication previously failed. Check your API key."};
        }
        last_error = None;
        for attempt in range(MAX_API_RETRIES + 1) {
            try {
                if self.provider == "deepseek" {
                    return self._call_deepseek(system, user, max_tokens);
                } else {
                    return self._call_anthropic(system, user, max_tokens);
                }
            } except Exception as e {
                last_error = str(e);
                if "authentication" in last_error.lower() or "api_key" in last_error.lower() {
                    self._auth_failed = True;
                    return {"error": f"API authentication failed: {last_error}"};
                }
                if attempt < MAX_API_RETRIES {
                    time.sleep(RETRY_DELAY_S * (attempt + 1));
                    continue;
                }
            }
        }
        return {"error": f"API failed after {MAX_API_RETRIES + 1} attempts: {last_error}"};
    }

    def _call_anthropic(system: str, user: str, max_tokens: int) -> dict {
        import anthropic;
        response = self.client.messages.create(
            model=self.model, max_tokens=max_tokens,
            system=system,
            messages=[{"role": "user", "content": user}]
        );
        return self._parse(response.content[0].text.strip());
    }

    def _call_deepseek(system: str, user: str, max_tokens: int) -> dict {
        response = self.client.chat.completions.create(
            model=self.model, max_tokens=max_tokens,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user}
            ]
        );
        return self._parse(response.choices[0].message.content.strip());
    }

    def _parse(raw: str) -> dict {
        try {
            clean = raw;
            if clean.startswith("```") {
                lines = clean.split("\n");
                clean = "\n".join(lines[1:-1] if lines[-1].strip() == "```" else lines[1:]);
            }
            return json.loads(clean);
        } except Exception {
            return {"text": raw};
        }
    }

    def _fmt_artifacts(artifacts: list) -> str {
        if not artifacts { return "No artifacts yet."; }
        lines = [];
        for (i, a) in enumerate(artifacts) {
            lines.append(f"[{i+1}] Tool: {a.get('tool','?')} (depth {a.get('depth','?')})");
            lines.append(f"     Summary: {a.get('summary','N/A')}");
            if "data" in a {
                data_str = str(a["data"]);
                if len(data_str) > 500 { data_str = data_str[:500] + "...[TRUNCATED]"; }
                lines.append(f"     Data: {data_str}");
            }
        }
        return "\n".join(lines);
    }

    def _fmt_tools(tools: list) -> str {
        _AUTO_INJECTED = {"market_id", "event_timestamp"};
        lines = [];
        for t in tools {
            visible_params = [p for p in t.get("params", [])
                              if p["name"] not in _AUTO_INJECTED];
            parts = [];
            for p in visible_params {
                tag = " [REQUIRED]" if p.get("required") else "";
                parts.append(f"{p['name']}: {p['type']}{tag}");
            }
            params = ", ".join(parts);
            lines.append(f"  {t['name']}({params}) — {t['description']}");
        }
        return "\n".join(lines);
    }
}
