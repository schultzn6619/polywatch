"""Investigation engine — Tree of Thought with DFS and backtracking.

Uses Jac's native graph primitives (nodes, edges, walkers) to build
and traverse the investigation tree.
"""

import from services.tools { TOOL_REGISTRY, TOOL_DESCRIPTIONS }

glob MAX_DEPTH: int = 5;
glob MAX_CHILDREN: int = 4;


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
) -> dict by llm();

# Evaluate whether an investigation node should stay open or close
def evaluate_node(
    goal: str,
    artifacts_summary: str,
    hypothesis: str,
    question: str,
    notes: str,
    conclusions: str,
    tool_descriptions: str
) -> dict by llm();

# Generate the first investigative step from the root node
def generate_root_step(
    goal: str,
    artifacts_summary: str,
    tool_descriptions: str
) -> dict by llm();

# Summarize the entire investigation after all branches close
def generate_summary(
    goal: str,
    all_conclusions: str
) -> str by llm();


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

glob _node_counter: int = 0;

# Run a full Tree of Thought investigation
def run_investigation(goal: str, initial_artifacts: list) -> dict {
    _node_counter = 0;

    root = InvestigationNode(
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

    _investigate_node(root, goal);

    all_conclusions = _collect_all_conclusions(root);
    summary = generate_summary(goal, all_conclusions);

    return {
        "summary": summary,
        "root_conclusions": root.conclusions,
        "total_nodes": _node_counter + 1
    };
}


# Recursive DFS investigation at a node
def _investigate_node(current: InvestigationNode, goal: str) -> None {
    artifacts_summary = _get_artifacts_summary(current.artifacts);
    conclusions_str = _get_conclusions_str(current.conclusions);

    # Root node with no children yet — get first step
    if current.depth == 0 and current.child_count == 0 {
        step = generate_root_step(goal, artifacts_summary, TOOL_DESCRIPTIONS);
    } else {
        # Evaluate whether this node should stay open
        eval_result = evaluate_node(
            goal,
            artifacts_summary,
            current.hypothesis,
            current.question,
            current.notes,
            conclusions_str,
            TOOL_DESCRIPTIONS
        );

        if eval_result.get("should_close", False) {
            current.is_open = False;
            return;
        }

        # Decide next step
        step = decide_next_step(
            goal,
            artifacts_summary,
            current.hypothesis,
            current.question,
            current.notes,
            conclusions_str,
            TOOL_DESCRIPTIONS
        );
    }

    # Check max children
    if current.child_count >= MAX_CHILDREN {
        current.is_open = False;
        return;
    }

    # Execute the tool
    tool_name = step.get("tool_name", "");
    tool_args = step.get("tool_args", {});
    exec_result = _execute_tool(tool_name, tool_args);

    # Handle tool errors — feed back, don't create a node
    if exec_result.get("error", False) {
        error_msg = exec_result.get("message", "Unknown error");
        print("Tool error: " + error_msg);
        current.is_open = False;
        return;
    }

    # Create child node
    _node_counter += 1;
    new_artifact = exec_result["artifact"];

    if not step.get("data_visible_to_ai", True) {
        new_artifact["data_visible_to_ai"] = False;
    }

    child_artifacts = list(current.artifacts) + [new_artifact];

    child = InvestigationNode(
        artifacts=child_artifacts,
        hypothesis=step.get("child_hypothesis", ""),
        question=step.get("child_question", ""),
        notes=step.get("child_notes", ""),
        is_open=True,
        conclusions=[],
        goal=goal,
        depth=current.depth + 1,
        node_id=_node_counter,
        child_count=0
    );

    current +>:InvestigatedWith(tool_name=tool_name, tool_args=tool_args):+> child;
    current.child_count += 1;

    # Force close if max depth reached
    if child.depth >= MAX_DEPTH {
        child.is_open = False;
        eval_result = evaluate_node(
            goal,
            _get_artifacts_summary(child.artifacts),
            child.hypothesis,
            child.question,
            child.notes,
            "Max depth reached. Must close this node.",
            TOOL_DESCRIPTIONS
        );
        conclusion = eval_result.get("conclusion", "Max depth reached — investigation path closed.");
        current.conclusions.append(conclusion);
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
        conclusion = eval_result.get("conclusion", "Investigation path closed without conclusion.");
        current.conclusions.append(conclusion);
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
