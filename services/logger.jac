"""PolyWatch — Investigation logger. Streaming file logger for observability."""

import os;
import json;
import datetime;

obj InvestigationLogger {
    has enabled: bool = True;
    has log_path: str = "investigation.log";
    has _fh: object | None = None;

    def init(log_path: str = "investigation.log", enabled: bool = True) {
        super.init();
        self.enabled = enabled;
        self.log_path = log_path;
        self._fh = None;
        if enabled {
            try {
                self._fh = open(log_path, "a", encoding="utf-8");
            } except OSError as e {
                print(f"[LOGGER WARNING] Could not open {log_path}: {e}");
                self.enabled = False;
            }
        }
    }

    def close() {
        if self._fh {
            try { self._fh.close(); }
            except OSError { }
        }
    }

    def _write(text: str) {
        if not self.enabled or not self._fh { return; }
        try {
            self._fh.write(text + "\n");
            self._fh.flush();
        } except Exception { }
    }

    def _sep(label: str) {
        self._write(f"\n{'='*20} {label} {'='*20}");
    }

    def _ts() -> str {
        return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ");
    }

    def log_run_start(market_id: str, event_timestamp: str,
                      goal: str, config: dict) {
        self._sep("RUN START");
        self._write(f"  timestamp:       {self._ts()}");
        self._write(f"  market_id:       {market_id}");
        self._write(f"  event_timestamp: {event_timestamp}");
        self._write(f"  goal:            {goal}");
        for (k, v) in config.items() {
            self._write(f"  {k}: {v}");
        }
    }

    def log_run_end(total_tool_calls: int, total_llm_calls: int,
                    elapsed_seconds: float) {
        self._sep("RUN END");
        self._write(f"  timestamp:        {self._ts()}");
        self._write(f"  total_tool_calls: {total_tool_calls}");
        self._write(f"  total_llm_calls:  {total_llm_calls}");
        self._write(f"  elapsed_seconds:  {elapsed_seconds:.2f}");
    }

    def log_node_enter(node_id: str, depth: int, hypothesis: str,
                       question: str, is_root: bool, artifact_count: int) {
        self._sep("NODE ENTER");
        self._write(f"  node_id:    {node_id}");
        self._write(f"  depth:      {depth}");
        self._write(f"  is_root:    {is_root}");
        self._write(f"  artifacts:  {artifact_count}");
        self._write(f"  hypothesis: {hypothesis[:120] if hypothesis else '(none)'}");
        self._write(f"  question:   {question[:120] if question else '(none)'}");
    }

    def log_node_exit(node_id: str, depth: int, is_open: bool,
                      close_reason: str, conclusions: list) {
        self._sep("NODE EXIT");
        self._write(f"  node_id:      {node_id}");
        self._write(f"  depth:        {depth}");
        self._write(f"  is_open:      {is_open}");
        self._write(f"  close_reason: {close_reason or '(still open)'}");
        self._write(f"  conclusions:  {len(conclusions)}");
        for (i, c) in enumerate(conclusions) {
            self._write(f"    [{i}] {c[:200]}");
        }
    }

    def log_llm_call(function_name: str, input_summary: str,
                     output: object, error: str | None = None) {
        self._sep("LLM RESPONSE");
        self._write(f"  function:  {function_name}");
        self._write(f"  input:     {input_summary[:200]}");
        if error {
            self._write(f"  status:    ERROR");
            self._write(f"  error:     {error}");
        } elif isinstance(output, dict) {
            self._write(f"  status:    OK");
            for k in ("should_close", "close_reason", "tool_name", "reasoning") {
                if k in output {
                    self._write(f"  {k}: {str(output[k])[:200]}");
                }
            }
        } else {
            self._write(f"  status:    OK");
            self._write(f"  output:    {str(output)[:300]}");
        }
    }

    def log_tool_call(tool_name: str, tool_args: dict,
                      success: bool, summary: str = "", error: str = "") {
        self._sep("TOOL CALL");
        self._write(f"  tool:    {tool_name}");
        self._write(f"  args:    {json.dumps(tool_args, default=str)[:300]}");
        self._write(f"  success: {success}");
        if success { self._write(f"  summary: {summary[:300]}"); }
        else { self._write(f"  error:   {error[:300]}"); }
    }

    def log_loop_detected(tool_name: str, node_id: str, depth: int) {
        self._sep("ERROR");
        self._write(f"  category: LOOP_PREVENTION");
        self._write(f"  detail:   Duplicate call blocked: {tool_name}");
        self._write(f"  node_id:  {node_id}");
        self._write(f"  depth:    {depth}");
    }

    def log_final_report(conclusions_count: int, meaningful_count: int,
                         sufficient_evidence: bool, total_tool_calls: int,
                         confidence: str = "LOW", evidence_count: int = 0,
                         categories_used: list | None = None,
                         report_preview: str = "") {
        self._sep("FINAL REPORT");
        self._write(f"  total_conclusions:      {conclusions_count}");
        self._write(f"  meaningful_conclusions: {meaningful_count}");
        self._write(f"  sufficient_evidence:    {sufficient_evidence}");
        self._write(f"  total_tool_calls:       {total_tool_calls}");
        self._write(f"  confidence:             {confidence}");
        self._write(f"  evidence_items:         {evidence_count}");
        cats = categories_used or [];
        self._write(f"  categories_used:        {', '.join(cats)}");
        self._write(f"  report_preview:");
        for line in report_preview[:800].split("\n") {
            self._write(f"    {line}");
        }
    }

    def log_backtrack(child_id: str, parent_id: str,
                      child_depth: int, summary: str) {
        self._sep("BACKTRACK");
        self._write(f"  child:   {child_id} (depth {child_depth})");
        self._write(f"  parent:  {parent_id}");
        self._write(f"  summary: {summary[:300]}");
    }

    def log_bootstrap(artifact_name: str, summary: str) {
        self._write(f"  [BOOTSTRAP] {artifact_name}: {summary[:200]}");
    }

    def log_evidence(item: object) {
        self._sep("EVIDENCE");
        self._write(f"  evidence_id:  {item.evidence_id}");
        self._write(f"  source_tool:  {item.source_tool}");
        self._write(f"  metric_name:  {item.metric_name}");
        self._write(f"  value:        {item.value}");
        self._write(f"  status:       {item.status}");
        self._write(f"  node_id:      {item.node_id}");
        self._write(f"  depth:        {item.depth}");
        self._write(f"  context:      {item.context[:200]}");
    }
}
