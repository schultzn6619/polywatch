"""PolyWatch — Evidence types, tiers, and classification."""

# Evidence quality tiers — determines what can back which claims
glob EVIDENCE_TIERS: dict = {
    "confirmed_numeric": 4,
    "confirmed_structural": 3,
    "weak_summary": 2,
    "unavailable": 1,
    "null_metric": 0
};

# Phrases in tool output that indicate structural unavailability
glob UNAVAILABILITY_MARKERS: list = [
    "not available from public api",
    "not available without",
    "no news api connected",
    "requires on-chain",
    "not available from the public",
    "public api does not expose",
    "use build_trader_network instead",
    "requires a condition_id filter",
    "requires resolved market data",
    "requires on-chain transaction",
    "cannot verify",
    "inconclusive"
];

def classify_evidence_tier(value: object, summary: str = "", metric_name: str = "") -> str {
    """Classify an evidence item into a quality tier.""";
    if value is None {
        return "null_metric";
    }
    summary_lower = (summary or "").lower();
    if any(marker in summary_lower for marker in UNAVAILABILITY_MARKERS) {
        return "unavailable";
    }
    if metric_name == "tool_summary" {
        return "weak_summary";
    }
    # Booleans must be checked before int (bool is subclass of int in Python)
    if isinstance(value, bool) {
        return "confirmed_numeric";
    }
    if isinstance(value, (int, float)) {
        # Zero-value counts for absence metrics are NOT real evidence
        _ABSENCE_METRICS = {
            "relevant_article_count", "articles_kept", "pre_news_volume_usdc",
            "pre_news_wallet_count", "high_confidence_pre_news_wallets",
            "pct_wallets_before_news", "pct_volume_before_news", "record_count"
        };
        if value == 0 and metric_name in _ABSENCE_METRICS {
            return "unavailable";
        }
        return "confirmed_numeric";
    }
    if isinstance(value, list) {
        return "confirmed_structural";
    }
    if isinstance(value, str) and len(value) <= 200 {
        return "confirmed_structural";
    }
    return "weak_summary";
}

obj Artifact {
    has data: object | None = None;
    has summary: str = "";
    has data_visible_to_ai: bool = False;
    has source_tool: str = "";
    has created_at_depth: int = 0;
}

obj EvidenceItem {
    has evidence_id: str = "";
    has source_tool: str = "";
    has metric_name: str = "";
    has value: object | None = None;
    has context: str = "";
    has status: str = "valid";
    has node_id: str = "";
    has depth: int = 0;
    has promoted: bool = False;
    has tier: str = "weak_summary";
}
