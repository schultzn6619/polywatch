"""Test trace runner — runs a real investigation at reduced scale and prints the full reasoning trace.

Run with: WEBZ_TOKEN=... PYTHONPATH=. jac run services/test_trace_investigation.jac
"""

import from services.investigation { run_investigation }
import from services.tools { tool_get_event_data }
import json;


def print_trace_readable(trace: list) -> None {
    for entry in trace {
        # Skip node entries (they have "status" key), only print events
        if "event_type" not in entry {
            continue;
        }

        depth = entry.get("depth", 0);
        indent = "  " * depth;
        etype = entry.get("event_type", "");
        nid = entry.get("node_id", 0);
        data = entry.get("data", {});

        if etype == "root_init" {
            print(indent + "[Node " + str(nid) + "] ROOT INIT — goal: " + str(data.get("goal", ""))[:80]);
        } elif etype == "llm_call" {
            print(indent + "  >> Calling LLM: " + str(data.get("function", "")));
        } elif etype == "llm_decision" {
            fn = data.get("function", "");
            if fn == "generate_root_step" or fn == "decide_next_step" {
                print(indent + "  << LLM chose tool: " + str(data.get("tool_name", "")));
                print(indent + "     Hypothesis: " + str(data.get("child_hypothesis", ""))[:100]);
                print(indent + "     Question: " + str(data.get("child_question", ""))[:100]);
            } elif fn == "evaluate_node" {
                close = data.get("should_close", False);
                print(indent + "  << Evaluate: should_close=" + str(close));
                if close {
                    print(indent + "     Conclusion: " + str(data.get("conclusion", ""))[:120]);
                }
            }
        } elif etype == "tool_exec" {
            print(indent + "  ~~ Executing: " + str(data.get("tool_name", "")) + "(" + str(data.get("tool_args", {})) + ")");
        } elif etype == "tool_success" {
            print(indent + "  OK: " + str(data.get("artifact_summary", ""))[:100]);
        } elif etype == "tool_error" {
            print(indent + "  !! ERROR: " + str(data.get("error", "")));
        } elif etype == "node_closed" {
            print(indent + "[Node " + str(nid) + "] CLOSED — " + str(data.get("reason", "")));
        } elif etype == "backtrack" {
            print(indent + "  <- BACKTRACK from child " + str(data.get("child_id", "")));
            print(indent + "     Conclusion: " + str(data.get("conclusion", ""))[:120]);
        } elif etype == "generating_summary" {
            print(indent + "  >> Generating final summary...");
        } elif etype == "summary_complete" {
            print(indent + "  << Summary generated (" + str(data.get("summary_length", 0)) + " chars)");
        }
    }
}


def print_tree_from_trace(trace: list) -> None {
    # Extract node entries (they have "status" key)
    nodes: dict = {};
    for entry in trace {
        if "status" in entry and "node_id" in entry {
            nodes[entry["node_id"]] = entry;
        }
    }

    def print_node(nid: int, depth: int) -> None {
        nd = nodes.get(nid, {});
        indent = "  " * depth;
        status = nd.get("status", "?");
        hyp = nd.get("hypothesis", "") or "(root)";
        tool = nd.get("tool_name", "") or "-";

        marker = "O" if status == "open" else "X";
        print(indent + "[" + marker + "] Node " + str(nid) + " (depth=" + str(nd.get("depth", 0)) + ") via " + tool);
        if hyp != "(root)" {
            print(indent + "    Hypothesis: " + str(hyp)[:100]);
            print(indent + "    Question: " + str(nd.get("question", ""))[:100]);
        }
        if nd.get("conclusions") {
            for c in nd.get("conclusions", []) {
                print(indent + "    Conclusion: " + str(c)[:120]);
            }
        }

        for child_id in nd.get("children", []) {
            print_node(child_id, depth + 1);
        }
    }

    if 0 in nodes {
        print_node(0, 0);
    }
}


with entry {
    print("=" * 70);
    print("PolyWatch Investigation — Trace Test Runner");
    print("MAX_DEPTH=3, MAX_CHILDREN=2");
    print("=" * 70);

    # Fetch seed event data
    print("\nFetching seed event data...");
    seed = tool_get_event_data("us-x-iran-ceasefire-by");
    print("Seed: " + str(seed.get("summary", ""))[:100]);

    initial_artifacts = [seed];
    goal = "Investigate whether there are signs of insider trading or informed betting on this prediction market. Look for suspicious trading patterns relative to news events.";

    print("\nStarting investigation...\n");
    result = run_investigation(goal, initial_artifacts, 3, 2);

    # Print readable trace
    print("\n" + "=" * 70);
    print("STEP-BY-STEP TRACE");
    print("=" * 70);
    print_trace_readable(result.get("trace", []));

    # Print tree view
    print("\n" + "=" * 70);
    print("INVESTIGATION TREE");
    print("=" * 70);
    print_tree_from_trace(result.get("trace", []));

    # Print final results
    print("\n" + "=" * 70);
    print("FINAL RESULTS");
    print("=" * 70);
    print("Total nodes: " + str(result.get("total_nodes", 0)));
    print("\nRoot conclusions:");
    i = 0;
    for c in result.get("root_conclusions", []) {
        i += 1;
        print("  " + str(i) + ". " + str(c));
    }
    print("\nSummary:");
    print(str(result.get("summary", "")));
}
