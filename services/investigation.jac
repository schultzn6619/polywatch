"""Investigation engine — Tree of Thought with DFS and backtracking.

Uses Jac's native graph primitives (nodes, edges, walkers) to build
and traverse the investigation tree. Includes step-by-step tracing.
"""

import os;
import from pathlib { Path }
import from byllm.lib { Model }
import from services.tools { TOOL_REGISTRY, TOOL_DESCRIPTIONS }
import from services.polymarketApi { get_event_info }


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

glob DEEPSEEK_API_KEY: str = _load_secret("DEEPSEEK_API_KEY");
glob deepseek_llm = Model(
    model_name="deepseek/deepseek-chat",
    api_key=DEEPSEEK_API_KEY
);

glob MAX_DEPTH: int = 5;
glob MAX_CHILDREN: int = 4;
glob _node_counter: int = 0;
glob _trace: list = [];


# ============================================================
# DATA STRUCTURES
# ============================================================

node InvestigationNode {
    has artifacts: list = [];
    has hypothesis: str = "";
    has question: str = "";
    has notes: str = "";
    has is_open: bool = True;
    has conclusions: list = [];
    has goal: str = "";
    has depth: int = 0;
    has node_id: int = 0;
    has child_count: int = 0;
}

edge InvestigatedWith {
    has tool_name: str = "";
    has tool_args: dict = {};
}


# ============================================================
# LLM RETURN TYPES
# ============================================================

obj NextStepResult {
    has tool_name: str = "";
    has tool_args: dict[str, str] = {};
    has child_hypothesis: str = "";
    has child_question: str = "";
    has child_notes: str = "";
    has data_visible_to_ai: bool = True;
}

obj EvalResult {
    has should_close: bool = False;
    has conclusion: str = "";
    has reasoning: str = "";
}


# ============================================================
# LLM-POWERED DECISION FUNCTIONS (by llm)
# ============================================================

# Decide the next investigative step given current state
def decide_next_step(
    goal: str,
    artifacts_summary: str,
    hypothesis: str,
    question: str,
    notes: str,
    conclusions: str,
    tool_descriptions: str
) -> NextStepResult by deepseek_llm();

# Evaluate whether an investigation node should stay open or close
def evaluate_node(
    goal: str,
    artifacts_summary: str,
    hypothesis: str,
    question: str,
    notes: str,
    conclusions: str,
    tool_descriptions: str
) -> EvalResult by deepseek_llm();

# Generate the first investigative step from the root node
def generate_root_step(
    goal: str,
    artifacts_summary: str,
    tool_descriptions: str
) -> NextStepResult by deepseek_llm();

# Summarize the entire investigation after all branches close
def generate_summary(
    goal: str,
    all_conclusions: str
) -> str by deepseek_llm();


# ============================================================
# TRACE HELPERS
# ============================================================

def _trace_reset() -> None {
    _trace = [];
}

def _trace_add(event_type: str, node_id: int, depth: int, data: dict) -> None {
    entry = {
        "event_type": event_type,
        "node_id": node_id,
        "depth": depth,
        "data": data
    };
    _trace.append(entry);
}

def _trace_add_node(node_id: int, parent_id: int, depth: int, hypothesis: str, question: str, notes: str, tool_name: str, tool_args: dict, tool_result_summary: str) -> None {
    entry = {
        "node_id": node_id,
        "parent_id": parent_id,
        "depth": depth,
        "status": "open",
        "hypothesis": hypothesis,
        "question": question,
        "notes": notes,
        "conclusions": [],
        "tool_name": tool_name,
        "tool_args": tool_args,
        "tool_result_summary": tool_result_summary,
        "children": []
    };
    _trace.append(entry);
}

def _trace_update_node(node_id: int, status: str, conclusions: list) -> None {
    for entry in _trace {
        if entry.get("node_id", -1) == node_id and "status" in entry {
            entry["status"] = status;
            entry["conclusions"] = conclusions;
            return;
        }
    }
}

def _trace_add_child(parent_id: int, child_id: int) -> None {
    for entry in _trace {
        if entry.get("node_id", -1) == parent_id and "children" in entry {
            entry["children"].append(child_id);
            return;
        }
    }
}


# ============================================================
# HELPER FUNCTIONS
# ============================================================

# Build a summary string from artifacts list
def _get_artifacts_summary(artifacts: list) -> str {
    if not artifacts {
        return "No artifacts yet.";
    }
    summary = "";
    i = 0;
    for artifact in artifacts {
        i += 1;
        summary += "Artifact " + str(i) + ": " + str(artifact.get("summary", "No summary")) + "\n";
        if artifact.get("data_visible_to_ai", False) {
            data_str = str(artifact.get("data", ""));
            if len(data_str) > 2000 {
                summary += "Data (truncated): " + data_str[:2000] + "...\n";
            } else {
                summary += "Data: " + data_str + "\n";
            }
        }
        summary += "\n";
    }
    return summary;
}

# Format conclusions array as a readable string
def _get_conclusions_str(conclusions: list) -> str {
    if not conclusions {
        return "No conclusions yet.";
    }
    result = "";
    i = 0;
    for c in conclusions {
        i += 1;
        result += "Conclusion " + str(i) + ": " + str(c) + "\n";
    }
    return result;
}

# Execute a tool by name with given args. Returns artifact dict or error
def _execute_tool(tool_name: str, tool_args: dict) -> dict {
    if tool_name not in TOOL_REGISTRY {
        return {
            "error": True,
            "message": "Unknown tool '" + tool_name + "'. Available tools: " + str(list(TOOL_REGISTRY.keys()))
        };
    }

    tool_fn = TOOL_REGISTRY[tool_name];

    try {
        result = tool_fn(**tool_args);
        return {"error": False, "artifact": result};
    } except Exception as e {
        return {
            "error": True,
            "message": "Tool '" + tool_name + "' failed with args " + str(tool_args) + ": " + str(e)
        };
    }
}


# ============================================================
# INVESTIGATION RUNNER
# ============================================================

# Run a full Tree of Thought investigation with tracing
def run_investigation(goal: str, initial_artifacts: list, max_depth: int = 3, max_children: int = 2) -> dict {
    _node_counter = 0;
    _trace_reset();
    MAX_DEPTH = max_depth;
    MAX_CHILDREN = max_children;

    # Add root node to trace
    _trace_add_node(0, -1, 0, "", "", "", "", {}, "");
    _trace_add("root_init", 0, 0, {"goal": goal, "artifact_count": len(initial_artifacts)});

    root_node = InvestigationNode(
        artifacts=initial_artifacts,
        hypothesis="",
        question="",
        notes="",
        is_open=True,
        conclusions=[],
        goal=goal,
        depth=0,
        node_id=0
    );

    _investigate_node(root_node, goal);

    # Update root trace
    _trace_update_node(0, "closed" if not root_node.is_open else "open", root_node.conclusions);

    all_conclusions = _collect_all_conclusions(root_node);

    _trace_add("generating_summary", 0, 0, {"conclusion_count": len(root_node.conclusions)});
    summary = generate_summary(goal, all_conclusions);
    _trace_add("summary_complete", 0, 0, {"summary_length": len(summary)});

    return {
        "summary": summary,
        "root_conclusions": root_node.conclusions,
        "total_nodes": _node_counter + 1,
        "trace": list(_trace)
    };
}


# Recursive DFS investigation at a node
def _investigate_node(current: InvestigationNode, goal: str) -> None {
    artifacts_summary = _get_artifacts_summary(current.artifacts);
    conclusions_str = _get_conclusions_str(current.conclusions);

    # Root node with no children yet — get first step
    if current.depth == 0 and current.child_count == 0 {
        _trace_add("llm_call", current.node_id, current.depth, {"function": "generate_root_step"});
        step = generate_root_step(goal, artifacts_summary, TOOL_DESCRIPTIONS);
        _trace_add("llm_decision", current.node_id, current.depth, {
            "function": "generate_root_step",
            "tool_name": step.tool_name,
            "tool_args": step.tool_args,
            "child_hypothesis": step.child_hypothesis,
            "child_question": step.child_question
        });
    } else {
        # Evaluate whether this node should stay open
        _trace_add("llm_call", current.node_id, current.depth, {"function": "evaluate_node"});
        eval_result = evaluate_node(
            goal,
            artifacts_summary,
            current.hypothesis,
            current.question,
            current.notes,
            conclusions_str,
            TOOL_DESCRIPTIONS
        );

        should_close = eval_result.should_close;
        _trace_add("llm_decision", current.node_id, current.depth, {
            "function": "evaluate_node",
            "should_close": should_close,
            "conclusion": eval_result.conclusion,
            "reasoning": eval_result.reasoning
        });

        if should_close {
            current.is_open = False;
            _trace_update_node(current.node_id, "closed", current.conclusions);
            return;
        }

        # Decide next step
        _trace_add("llm_call", current.node_id, current.depth, {"function": "decide_next_step"});
        step = decide_next_step(
            goal,
            artifacts_summary,
            current.hypothesis,
            current.question,
            current.notes,
            conclusions_str,
            TOOL_DESCRIPTIONS
        );
        _trace_add("llm_decision", current.node_id, current.depth, {
            "function": "decide_next_step",
            "tool_name": step.tool_name,
            "tool_args": step.tool_args,
            "child_hypothesis": step.child_hypothesis,
            "child_question": step.child_question
        });
    }

    # Check max children
    if current.child_count >= MAX_CHILDREN {
        current.is_open = False;
        _trace_add("node_closed", current.node_id, current.depth, {"reason": "max_children_reached"});
        _trace_update_node(current.node_id, "closed", current.conclusions);
        return;
    }

    # Execute the tool
    tool_name = step.tool_name;
    tool_args = step.tool_args;
    _trace_add("tool_exec", current.node_id, current.depth, {"tool_name": tool_name, "tool_args": tool_args});
    exec_result = _execute_tool(tool_name, tool_args);

    # Handle tool errors
    if exec_result.get("error", False) {
        error_msg = exec_result.get("message", "Unknown error");
        _trace_add("tool_error", current.node_id, current.depth, {"tool_name": tool_name, "error": error_msg});
        print("Tool error: " + error_msg);
        current.is_open = False;
        _trace_update_node(current.node_id, "closed", current.conclusions);
        return;
    }

    artifact_summary = exec_result["artifact"].get("summary", "");
    _trace_add("tool_success", current.node_id, current.depth, {"tool_name": tool_name, "artifact_summary": artifact_summary});

    # Create child node
    _node_counter += 1;
    new_artifact = exec_result["artifact"];

    if not step.data_visible_to_ai {
        new_artifact["data_visible_to_ai"] = False;
    }

    child_artifacts = list(current.artifacts) + [new_artifact];

    child = InvestigationNode(
        artifacts=child_artifacts,
        hypothesis=step.child_hypothesis,
        question=step.child_question,
        notes=step.child_notes,
        is_open=True,
        conclusions=[],
        goal=goal,
        depth=current.depth + 1,
        node_id=_node_counter,
        child_count=0
    );

    current +>:InvestigatedWith(tool_name=tool_name, tool_args=tool_args):+> child;
    current.child_count += 1;

    # Add child to trace
    _trace_add_node(
        _node_counter, current.node_id, child.depth,
        child.hypothesis, child.question, child.notes,
        tool_name, tool_args, artifact_summary
    );
    _trace_add_child(current.node_id, _node_counter);

    # Force close if max depth reached
    if child.depth >= MAX_DEPTH {
        child.is_open = False;
        _trace_add("node_closed", child.node_id, child.depth, {"reason": "max_depth_reached"});

        eval_result = evaluate_node(
            goal,
            _get_artifacts_summary(child.artifacts),
            child.hypothesis,
            child.question,
            child.notes,
            "Max depth reached. Must close this node.",
            TOOL_DESCRIPTIONS
        );
        conclusion = eval_result.conclusion if eval_result.conclusion else "Max depth reached — investigation path closed.";
        current.conclusions.append(conclusion);
        _trace_update_node(child.node_id, "closed", [conclusion]);
        _trace_add("backtrack", current.node_id, current.depth, {"child_id": child.node_id, "conclusion": conclusion});
        return;
    }

    # Recurse into child
    _investigate_node(child, goal);

    # Child returned (closed) — collect conclusion
    if not child.is_open {
        eval_result = evaluate_node(
            goal,
            _get_artifacts_summary(child.artifacts),
            child.hypothesis,
            child.question,
            child.notes,
            _get_conclusions_str(child.conclusions),
            TOOL_DESCRIPTIONS
        );
        conclusion = eval_result.conclusion if eval_result.conclusion else "Investigation path closed without conclusion.";
        current.conclusions.append(conclusion);
        _trace_update_node(child.node_id, "closed", child.conclusions);
        _trace_add("backtrack", current.node_id, current.depth, {"child_id": child.node_id, "conclusion": conclusion});
    }

    # After backtrack, re-evaluate parent
    if current.is_open and current.child_count < MAX_CHILDREN {
        _investigate_node(current, goal);
    }
}


# Collect conclusions from the entire tree for the final summary
def _collect_all_conclusions(nd: InvestigationNode) -> str {
    result = "";
    if nd.conclusions {
        for c in nd.conclusions {
            result += "- " + str(c) + "\n";
        }
    }
    children = [nd-->];
    for child in children {
        result += _collect_all_conclusions(child);
    }
    return result;
}


# ============================================================
# HIGH-LEVEL ENTRY POINT (for frontend)
# ============================================================

# Start an investigation from a Polymarket event slug
def:priv start_investigation(slug: str, goal: str = "", max_depth: int = 3, max_children: int = 2) -> dict {
    # Fetch event data
    try {
        event_info = get_event_info(slug);
    } except Exception as e {
        return {"error": "Failed to fetch event '" + slug + "': " + str(e)};
    }

    if not goal {
        goal = "Investigate the Polymarket event '" + slug + "' for signs of insider trading, market manipulation, or informed trading ahead of news events.";
    }

    initial_artifacts = [
        {
            "data": event_info,
            "summary": "Polymarket event data for '" + slug + "'. Contains event description, market outcomes, prices, liquidity, and volume metrics.",
            "data_visible_to_ai": True
        }
    ];

    result = run_investigation(goal, initial_artifacts, max_depth, max_children);

    result["event_slug"] = slug;
    event_preview = event_info;
    if len(event_info) > 500 {
        event_preview = event_info[:500] + "...";
    }
    result["event_summary"] = event_preview;

    return result;
}
