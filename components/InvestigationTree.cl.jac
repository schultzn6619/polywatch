"""Investigation tree visualization — shows the LLM's DFS thought process."""

def:pub InvestigationTree(tree: list) -> JsxElement {

    def get_cat_class(tool_name: str) -> str {
        if not tool_name { return "tree-cat-default"; }
        t = tool_name.toLowerCase() if tool_name else "";
        if "news" in t or "sentiment" in t or "pre_news" in t { return "tree-cat-news"; }
        if "wallet" in t or "pnl" in t or "profile" in t or "activity" in t { return "tree-cat-wallet"; }
        if "network" in t or "linked" in t or "fund" in t or "trader_network" in t { return "tree-cat-network"; }
        if "volume" in t or "price" in t or "timing" in t or "synchronized" in t or "suspicious" in t or "abnormal" in t { return "tree-cat-statistical"; }
        return "tree-cat-market";
    }

    nodes = Array.from(tree);
    if not nodes or nodes.length == 0 {
        return <p className="text-muted-foreground text-sm">{"No tree data available."}</p>;
    }

    def render_single(n: any) -> JsxElement {
        cat = get_cat_class(n["tool"] or "");
        d = n["depth"] or 0;
        return (
            <div className="tree-viz-node" key={n["id"] or "?"} style={{"marginLeft": str(d * 28) + "px"}}>
                <div className={"tree-viz-bar " + cat}>
                    <span className="tree-viz-id">{n["id"] or "?"}</span>
                    {n["tool"] and (
                        <span className="tree-viz-tool">{n["tool"]}</span>
                    )}
                    <span className="tree-viz-depth">{"D" + str(d)}</span>
                </div>
                {n["hypothesis"] and (
                    <div className="tree-viz-hyp">{n["hypothesis"]}</div>
                )}
                {n["result"] and (
                    <div className="tree-viz-result">{n["result"]}</div>
                )}
            </div>
        );
    }

    return (
        <div className="tree-viz-container">
            <div className="tree-legend">
                <span className="tree-legend-dot tree-cat-market" />
                <span className="tree-legend-label">Market</span>
                <span className="tree-legend-dot tree-cat-statistical" />
                <span className="tree-legend-label">Statistical</span>
                <span className="tree-legend-dot tree-cat-news" />
                <span className="tree-legend-label">News</span>
                <span className="tree-legend-dot tree-cat-wallet" />
                <span className="tree-legend-label">Wallet</span>
                <span className="tree-legend-dot tree-cat-network" />
                <span className="tree-legend-label">Network</span>
            </div>
            <div className="tree-viz-scroll">
                {nodes.map(render_single)}
            </div>
        </div>
    );
}
