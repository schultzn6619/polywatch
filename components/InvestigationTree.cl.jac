"""Investigation tree component — flat-list rendering of the investigation trace nodes."""

def:pub InvestigationTree(trace: list) -> JsxElement {
    has expanded_nodes: dict = {"0": True};

    def toggle_node(nid: str) -> None {
        if nid in expanded_nodes {
            new_exp = {};
            for k in expanded_nodes {
                if k != nid {
                    new_exp[k] = True;
                }
            }
            expanded_nodes = new_exp;
        } else {
            new_exp = {};
            for k in expanded_nodes {
                new_exp[k] = True;
            }
            new_exp[nid] = True;
            expanded_nodes = new_exp;
        }
    }

    def get_nodes() -> dict {
        nodes: dict = {};
        for entry in trace {
            if "status" in entry and "node_id" in entry {
                nodes[str(entry["node_id"])] = entry;
            }
        }
        return nodes;
    }

    def render_node(nodes: dict, nid: str, depth: int) -> JsxElement {
        nd = nodes.get(nid, {});
        is_expanded = nid in expanded_nodes;
        status = nd.get("status", "?");
        hyp = nd.get("hypothesis", "") or "Root Node";
        tool = nd.get("tool_name", "");
        children = nd.get("children", []);
        has_children = len(children) > 0;
        nid_str = str(nid);

        return (
            <div className="tree-node" style={{"marginLeft": str(depth * 8) + "px"}}>
                <div className="tree-node-header" onClick={lambda: toggle_node(nid_str)}>
                    <span className="tree-chevron">
                        {(("v" if is_expanded else ">") if has_children else " ")}
                    </span>
                    <span className={"tree-node-badge " + ("tree-node-badge-open" if status == "open" else "tree-node-badge-closed")}>
                        {"N" + nid_str}
                    </span>
                    {tool and (
                        <span className="tree-edge-label">{tool}</span>
                    )}
                    <span className="tree-node-hypothesis">
                        {hyp[:80]}
                    </span>
                </div>

                {is_expanded and (
                    <div className="tree-node-body">
                        {nd.get("question", "") and (
                            <div className="tree-field">
                                <span className="tree-field-label">{"Question: "}</span>
                                {nd.get("question", "")}
                            </div>
                        )}
                        {nd.get("notes", "") and (
                            <div className="tree-field">
                                <span className="tree-field-label">{"Notes: "}</span>
                                {nd.get("notes", "")[:200]}
                            </div>
                        )}
                        {nd.get("tool_result_summary", "") and (
                            <div className="tree-field">
                                <span className="tree-field-label">{"Tool Result: "}</span>
                                {nd.get("tool_result_summary", "")[:150]}
                            </div>
                        )}
                        {nd.get("conclusions", []) and (
                            <div className="tree-field">
                                <span className="tree-field-label">{"Conclusions:"}</span>
                                <ul className="tree-conclusions">
                                    {[<li key={str(idx)}>{str(c)[:150]}</li> for idx, c in enumerate(nd.get("conclusions", []))]}
                                </ul>
                            </div>
                        )}
                        {has_children and (
                            <div className="tree-children">
                                {[render_node(nodes, str(cid), depth + 1) for cid in children]}
                            </div>
                        )}
                    </div>
                )}
            </div>
        );
    }

    nodes = get_nodes();

    return (
        <div>
            {nodes and "0" in nodes and (
                render_node(nodes, "0", 0)
            )}
            {(not nodes or "0" not in nodes) and (
                <p className="text-muted-foreground text-sm">{"No tree data available."}</p>
            )}
        </div>
    );
}
