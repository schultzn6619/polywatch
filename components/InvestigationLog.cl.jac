"""Investigation log component — scrollable, color-coded trace log."""

def:pub InvestigationLog(trace: list) -> JsxElement {

    def get_events() -> list {
        events: list = [];
        for log_entry in trace {
            if "event_type" in log_entry {
                events.append(log_entry);
            }
        }
        return events;
    }

    def format_message(log_entry: dict) -> str {
        etype = log_entry.get("event_type", "");
        data = log_entry.get("data", {});

        if etype == "root_init" {
            return "Investigation started — " + str(data.get("artifact_count", 0)) + " initial artifacts";
        }
        if etype == "llm_call" {
            return "Calling " + str(data.get("function", ""));
        }
        if etype == "llm_decision" {
            fn = data.get("function", "");
            if fn == "generate_root_step" or fn == "decide_next_step" {
                return "Chose tool: " + str(data.get("tool_name", "")) + " | Hypothesis: " + str(data.get("child_hypothesis", ""))[:80];
            }
            if fn == "evaluate_node" {
                if data.get("should_close", False) {
                    return "Node should CLOSE — " + str(data.get("conclusion", ""))[:80];
                }
                return "Node stays OPEN";
            }
        }
        if etype == "tool_exec" {
            return "Executing " + str(data.get("tool_name", ""));
        }
        if etype == "tool_success" {
            return str(data.get("artifact_summary", ""))[:100];
        }
        if etype == "tool_error" {
            return "ERROR: " + str(data.get("error", ""))[:100];
        }
        if etype == "node_closed" {
            return "Closed — " + str(data.get("reason", ""));
        }
        if etype == "backtrack" {
            return "Backtrack from N" + str(data.get("child_id", "")) + " — " + str(data.get("conclusion", ""))[:80];
        }
        if etype == "generating_summary" {
            return "Generating final summary...";
        }
        if etype == "summary_complete" {
            return "Summary complete (" + str(data.get("summary_length", 0)) + " chars)";
        }
        return str(data);
    }

    events = get_events();

    return (
        <div className="log-container">
            {[
                <div className={"log-entry log-entry-" + log_entry.get("event_type", "")}>
                    <span className="log-badge">{log_entry.get("event_type", "")}</span>
                    <span className="log-depth">{"D" + str(log_entry.get("depth", 0))}</span>
                    <span className="log-message">{format_message(log_entry)}</span>
                </div>
                for log_entry in events
            ]}
            {not events and (
                <p className="text-muted-foreground text-sm">{"No log entries."}</p>
            )}
        </div>
    );
}
