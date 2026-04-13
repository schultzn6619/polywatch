import { useState, useEffect } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import {
  ArrowLeft,
  Play,
  Loader2,
  ChevronRight,
  FileText,
  AlertTriangle,
  CheckCircle2,
  Clock,
  Brain,
  Wrench,
} from "lucide-react";

interface TreeNode {
  id: string;
  title: string;
  status: "running" | "complete" | "pending";
  depth: number;
  toolCalls: number;
  category: string;
}

interface Artifact {
  id: string;
  title: string;
  category: string;
  summary: string;
}

const demoTree: TreeNode[] = [
  { id: "1", title: "Baseline Market Analysis", status: "complete", depth: 0, toolCalls: 4, category: "Market Analysis" },
  { id: "2", title: "Volume Anomaly Detection", status: "complete", depth: 1, toolCalls: 3, category: "Statistical Anomaly" },
  { id: "3", title: "Large Trade Clustering", status: "complete", depth: 2, toolCalls: 2, category: "Market Analysis" },
  { id: "4", title: "Pre-News Trading Scan", status: "complete", depth: 1, toolCalls: 3, category: "News Correlation" },
  { id: "5", title: "Wallet Profiling - Top Traders", status: "complete", depth: 2, toolCalls: 4, category: "Wallet Profiling" },
  { id: "6", title: "Network Link Analysis", status: "running", depth: 2, toolCalls: 2, category: "Network Analysis" },
  { id: "7", title: "Synchronized Trade Detection", status: "pending", depth: 3, toolCalls: 0, category: "Statistical Anomaly" },
];

const demoArtifacts: Artifact[] = [
  { id: "A1", title: "Market Overview", category: "Market Analysis", summary: "Total volume $3.2B across 12 markets. Primary market shows 89% concentration." },
  { id: "A2", title: "Volume Spike Report", category: "Statistical Anomaly", summary: "Detected 340% volume increase 2 hours before major news event on 2024-11-03." },
  { id: "A3", title: "Large Trade Log", category: "Market Analysis", summary: "17 trades exceeding $50K in 24hr window. 12 from 3 connected wallets." },
  { id: "A4", title: "News Timeline", category: "News Correlation", summary: "Pre-news trading detected: 4 large buy orders placed 47 minutes before AP report." },
  { id: "A5", title: "Wallet Profile - 0x7a3f", category: "Wallet Profiling", summary: "94% win rate across 23 trades. First activity 6 hours before event creation." },
];

const statusIcon = {
  running: <Loader2 className="h-4 w-4 animate-spin text-primary" />,
  complete: <CheckCircle2 className="h-4 w-4 text-success" />,
  pending: <Clock className="h-4 w-4 text-muted-foreground" />,
};

export default function InvestigationPage() {
  const [searchParams] = useSearchParams();
  const slug = searchParams.get("slug") || "presidential-election-2024";
  const navigate = useNavigate();

  const [phase, setPhase] = useState<"input" | "running" | "complete">("input");
  const [goal, setGoal] = useState("");
  const [elapsed, setElapsed] = useState(0);
  const [tree, setTree] = useState<TreeNode[]>([]);
  const [artifacts, setArtifacts] = useState<Artifact[]>([]);
  const [activeTab, setActiveTab] = useState<"overview" | "artifacts" | "report">("overview");
  const [selectedArtifact, setSelectedArtifact] = useState<Artifact | null>(null);

  useEffect(() => {
    if (phase !== "running") return;
    const timer = setInterval(() => setElapsed((e) => e + 1), 1000);

    let nodeIndex = 0;
    const addNodes = setInterval(() => {
      if (nodeIndex < demoTree.length) {
        setTree((prev) => [...prev, demoTree[nodeIndex]]);
        nodeIndex++;
      }
    }, 1500);

    const completeTimer = setTimeout(() => {
      setPhase("complete");
      setTree(demoTree.map((n) => ({ ...n, status: "complete" as const })));
      setArtifacts(demoArtifacts);
      clearInterval(addNodes);
    }, demoTree.length * 1500 + 2000);

    return () => {
      clearInterval(timer);
      clearInterval(addNodes);
      clearTimeout(completeTimer);
    };
  }, [phase]);

  function startInvestigation() {
    setPhase("running");
    setTree([]);
    setArtifacts([]);
    setElapsed(0);
  }

  const formatTime = (s: number) =>
    `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;

  const title = slug.replace(/-/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());

  return (
    <div className="min-h-screen pt-16">
      <div className="mx-auto max-w-6xl px-6 py-8">
        <button
          onClick={() => navigate("/dashboard")}
          className="mb-4 inline-flex items-center gap-1 text-sm text-muted-foreground transition-colors hover:text-primary"
        >
          <ArrowLeft className="h-4 w-4" /> Back to Dashboard
        </button>
        <h1 className="text-2xl font-bold">{title}</h1>

        {phase === "input" && (
          <div className="mt-8 mx-auto max-w-lg">
            <div className="rounded-xl border border-border bg-card p-6">
              <h2 className="text-lg font-semibold">Start Investigation</h2>
              <p className="mt-1 text-sm text-muted-foreground">
                Optionally describe what you are looking for.
              </p>
              <textarea
                value={goal}
                onChange={(e) => setGoal(e.target.value)}
                placeholder="e.g. Look for insider trading, coordinated wallets, pre-news activity..."
                rows={3}
                className="mt-4 w-full rounded-xl border border-border bg-surface px-4 py-3 text-sm text-foreground placeholder:text-muted-foreground outline-none transition-colors focus:border-primary resize-none"
              />
              <button
                onClick={startInvestigation}
                className="mt-4 inline-flex w-full items-center justify-center gap-2 rounded-xl bg-primary py-3 text-sm font-semibold text-primary-foreground transition-all hover:-translate-y-px hover:bg-primary-dark hover:shadow-[0_0_20px_rgba(245,158,11,0.25)]"
              >
                <Play className="h-4 w-4" /> Launch Investigation
              </button>
            </div>
          </div>
        )}

        {phase !== "input" && (
          <div className="mt-6">
            <div className="flex flex-wrap items-center gap-4 rounded-xl border border-border bg-card px-5 py-3">
              <div className="flex items-center gap-2">
                {phase === "running" ? (
                  <Loader2 className="h-4 w-4 animate-spin text-primary" />
                ) : (
                  <CheckCircle2 className="h-4 w-4 text-success" />
                )}
                <span className="text-sm font-medium">
                  {phase === "running" ? "Investigating..." : "Complete"}
                </span>
              </div>
              <div className="flex items-center gap-1 text-xs text-muted-foreground">
                <Clock className="h-3 w-3" /> {formatTime(elapsed)}
              </div>
              <div className="flex items-center gap-1 text-xs text-muted-foreground">
                <Brain className="h-3 w-3" /> {tree.length} nodes
              </div>
              <div className="flex items-center gap-1 text-xs text-muted-foreground">
                <Wrench className="h-3 w-3" />{" "}
                {tree.reduce((s, n) => s + n.toolCalls, 0)} tool calls
              </div>
              <div className="flex items-center gap-1 text-xs text-muted-foreground">
                <FileText className="h-3 w-3" /> {artifacts.length} artifacts
              </div>
            </div>

            <div className="mt-6 flex gap-1 border-b border-border">
              {(["overview", "artifacts", "report"] as const).map((tab) => (
                <button
                  key={tab}
                  onClick={() => setActiveTab(tab)}
                  className={`px-4 py-2 text-sm font-medium capitalize transition-colors ${
                    activeTab === tab
                      ? "border-b-2 border-primary text-primary"
                      : "text-muted-foreground hover:text-foreground"
                  }`}
                >
                  {tab}
                </button>
              ))}
            </div>

            {activeTab === "overview" && (
              <div className="mt-4 space-y-2">
                {tree.map((node) => (
                  <div
                    key={node.id}
                    className="flex items-center gap-3 rounded-xl border border-border bg-card px-4 py-3 transition-all hover:border-primary/20"
                    style={{ marginLeft: node.depth * 24 }}
                  >
                    {statusIcon[node.status]}
                    <span className="flex-1 text-sm font-medium">{node.title}</span>
                    <span className="rounded-lg bg-muted px-2.5 py-0.5 text-xs text-muted-foreground">
                      {node.category}
                    </span>
                    <span className="text-xs text-muted-foreground">
                      {node.toolCalls} calls
                    </span>
                  </div>
                ))}
                {tree.length === 0 && (
                  <p className="py-8 text-center text-sm text-muted-foreground">
                    Starting investigation...
                  </p>
                )}
              </div>
            )}

            {activeTab === "artifacts" && (
              <div className="mt-4 space-y-3">
                {artifacts.map((a) => (
                  <button
                    key={a.id}
                    onClick={() =>
                      setSelectedArtifact(selectedArtifact?.id === a.id ? null : a)
                    }
                    className="w-full rounded-xl border border-border bg-card p-4 text-left transition-all hover:border-primary/20"
                  >
                    <div className="flex items-center gap-3">
                      <span className="rounded-md bg-primary/10 px-2 py-0.5 text-xs font-bold text-primary">
                        {a.id}
                      </span>
                      <span className="flex-1 text-sm font-medium">{a.title}</span>
                      <span className="rounded-lg bg-muted px-2.5 py-0.5 text-xs text-muted-foreground">
                        {a.category}
                      </span>
                      <ChevronRight
                        className={`h-4 w-4 text-muted-foreground transition-transform ${
                          selectedArtifact?.id === a.id ? "rotate-90" : ""
                        }`}
                      />
                    </div>
                    {selectedArtifact?.id === a.id && (
                      <p className="mt-3 text-sm leading-relaxed text-muted-foreground">
                        {a.summary}
                      </p>
                    )}
                  </button>
                ))}
                {artifacts.length === 0 && (
                  <p className="py-8 text-center text-sm text-muted-foreground">
                    Artifacts will appear as the investigation progresses...
                  </p>
                )}
              </div>
            )}

            {activeTab === "report" && (
              <div className="mt-4">
                {phase === "complete" ? (
                  <div className="rounded-xl border border-border bg-card p-6">
                    <h2 className="text-xl font-bold">Investigation Report</h2>
                    <p className="mt-1 text-sm text-muted-foreground">{title}</p>

                    <div className="mt-6 space-y-6">
                      <section>
                        <h3 className="flex items-center gap-2 text-sm font-semibold uppercase tracking-wider text-primary">
                          <AlertTriangle className="h-4 w-4" /> Executive Summary
                        </h3>
                        <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
                          Analysis of trading activity on this market reveals several
                          concerning patterns suggesting possible informed trading.
                          A cluster of large trades from connected wallets was
                          detected approximately 47 minutes before a major news
                          event, with volume spiking 340% above the 7-day average
                          [A2]. Three wallets showing unusually high win rates
                          (94%+) executed coordinated buy orders [A3][A5].
                        </p>
                      </section>

                      <section>
                        <h3 className="text-sm font-semibold uppercase tracking-wider text-primary">
                          Key Findings
                        </h3>
                        <ul className="mt-2 space-y-2 text-sm leading-relaxed text-muted-foreground">
                          <li className="flex gap-2">
                            <span className="mt-0.5 text-primary">1.</span>
                            Pre-news trading detected: 4 large buy orders placed
                            47 minutes before AP report [A4]
                          </li>
                          <li className="flex gap-2">
                            <span className="mt-0.5 text-primary">2.</span>
                            340% volume anomaly 2 hours before news event [A2]
                          </li>
                          <li className="flex gap-2">
                            <span className="mt-0.5 text-primary">3.</span>
                            17 trades exceeding $50K from 3 connected wallets
                            within 24hr [A3]
                          </li>
                          <li className="flex gap-2">
                            <span className="mt-0.5 text-primary">4.</span>
                            Wallet 0x7a3f shows 94% win rate with first activity
                            predating market creation [A5]
                          </li>
                        </ul>
                      </section>

                      <section>
                        <h3 className="text-sm font-semibold uppercase tracking-wider text-primary">
                          Limitations
                        </h3>
                        <p className="mt-2 text-sm leading-relaxed text-muted-foreground">
                          This analysis is based on publicly available on-chain
                          data and API responses. Wallet attribution relies on
                          behavioral patterns and cannot confirm real-world
                          identities. Correlation does not imply causation.
                        </p>
                      </section>

                      <section>
                        <h3 className="text-sm font-semibold uppercase tracking-wider text-primary">
                          Recommended Next Steps
                        </h3>
                        <ul className="mt-2 space-y-1 text-sm text-muted-foreground">
                          <li>- Deep-dive into wallet 0x7a3f transaction history</li>
                          <li>- Cross-reference with other prediction market platforms</li>
                          <li>- Monitor for continued coordinated activity</li>
                          <li>- Expand network analysis to second-degree connections</li>
                        </ul>
                      </section>
                    </div>
                  </div>
                ) : (
                  <p className="py-8 text-center text-sm text-muted-foreground">
                    Report will be generated when the investigation completes...
                  </p>
                )}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
