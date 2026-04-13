import { useState, useEffect, useRef, useCallback, useMemo } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import {
  ArrowLeft,
  Play,
  Square,
  Loader2,
  ChevronRight,
  FileText,
  AlertTriangle,
  CheckCircle2,
  Clock,
  Brain,
  Wrench,
  BarChart3,
  Newspaper,
  GitBranch,
  History,
  List,
  Network,
  ExternalLink,
  X,
  TrendingUp,
  Activity,
  Search,
  Shield,
} from "lucide-react";

/* ───────── Types ───────── */

interface TreeNode {
  id: string;
  hypothesis: string;
  tool: string;
  question: string;
  result: string;
  status: "active" | "closed";
  depth: number;
  category: "market" | "statistical" | "news" | "wallet" | "network";
  parentId: string | null;
}

interface Artifact {
  id: string;
  tool: string;
  summary: string;
  data: Record<string, unknown>;
}

interface NewsArticle {
  title: string;
  url: string;
  source: string;
  publishedDate: string;
  description: string;
}

interface PricePoint {
  date: string;
  price_yes: number;
  price_no: number;
}

interface VolumePoint {
  date: string;
  volume_usdc: number;
  abnormal: boolean;
}

interface PreviousInvestigation {
  id: string;
  marketTitle: string;
  confidence: "HIGH" | "MEDIUM" | "LOW";
  toolCount: number;
  elapsedSeconds: number;
  date: string;
}

interface InvestigationStep {
  label: string;
  description: string;
  complete: boolean;
}

/* ───────── Demo Data ───────── */

const DEMO_TREE: TreeNode[] = [
  {
    id: "N1", hypothesis: "Market shows abnormal trading patterns", tool: "get_market_data",
    question: "What are the baseline trading metrics for this market?",
    result: "Total volume $3.2M. 89% concentration in YES shares. Average daily volume $230K with recent 3x spike.",
    status: "closed", depth: 0, category: "market", parentId: null,
  },
  {
    id: "N2", hypothesis: "Volume spikes correlate with information events", tool: "detect_volume_anomalies",
    question: "Are there statistically significant volume anomalies?",
    result: "Detected 340% volume increase 2 hours before major news event on 2024-11-03. Z-score: 4.2.",
    status: "closed", depth: 1, category: "statistical", parentId: "N1",
  },
  {
    id: "N3", hypothesis: "Large trades cluster around key events", tool: "get_large_trades",
    question: "What large trades occurred around detected anomalies?",
    result: "17 trades exceeding $50K in 24hr window. 12 originated from 3 connected wallets.",
    status: "closed", depth: 2, category: "market", parentId: "N2",
  },
  {
    id: "N4", hypothesis: "News events preceded by informed trading", tool: "correlate_news_trades",
    question: "Were there trades placed before news broke publicly?",
    result: "4 large buy orders placed 47 minutes before AP report publication. Total value: $312K.",
    status: "closed", depth: 1, category: "news", parentId: "N1",
  },
  {
    id: "N5", hypothesis: "Top traders have suspicious win rates", tool: "profile_wallet",
    question: "What is the trading history of the top-performing wallets?",
    result: "Wallet 0x7a3f: 94% win rate across 23 trades. First activity 6 hours before market creation.",
    status: "closed", depth: 2, category: "wallet", parentId: "N4",
  },
  {
    id: "N6", hypothesis: "Connected wallets form coordinated network", tool: "analyze_network",
    question: "Are the flagged wallets linked through on-chain transfers?",
    result: "3-wallet cluster identified with shared funding source. Total inter-wallet transfers: $1.8M.",
    status: "closed", depth: 2, category: "network", parentId: "N3",
  },
  {
    id: "N7", hypothesis: "Synchronized trades indicate coordination", tool: "detect_sync_trades",
    question: "Did the identified wallets execute trades within the same time windows?",
    result: "5 synchronized trade events detected within 30-second windows. Probability of coincidence < 0.01%.",
    status: "closed", depth: 3, category: "statistical", parentId: "N6",
  },
];

const DEMO_ARTIFACTS: Artifact[] = [
  {
    id: "A1", tool: "get_market_data", summary: "Market overview data showing $3.2M total volume, 89% YES concentration.",
    data: { market_id: "0x8f3a", total_volume_usd: 3200000, yes_concentration: 0.89, avg_daily_volume: 230000, unique_traders: 847, created_at: "2024-10-15T08:00:00Z", last_trade: "2024-11-05T14:32:00Z" },
  },
  {
    id: "A2", tool: "detect_volume_anomalies", summary: "Volume spike report: 340% increase detected 2 hours before news event.",
    data: { anomaly_type: "volume_spike", magnitude_pct: 340, z_score: 4.2, baseline_volume_24h: 180000, spike_volume_24h: 792000, timestamp: "2024-11-03T10:15:00Z", confidence: 0.97, related_event: "AP_report_publication" },
  },
  {
    id: "A3", tool: "get_large_trades", summary: "17 trades exceeding $50K from 3 connected wallets in 24hr window.",
    data: { total_large_trades: 17, threshold_usd: 50000, time_window: "24h", connected_wallets: 3, total_value_usd: 1450000, trades: [{ wallet: "0x7a3f", amount: 125000, side: "YES", timestamp: "2024-11-03T09:28:00Z" }, { wallet: "0x2b8e", amount: 87000, side: "YES", timestamp: "2024-11-03T09:29:00Z" }, { wallet: "0xd41c", amount: 63000, side: "YES", timestamp: "2024-11-03T09:31:00Z" }] },
  },
  {
    id: "A4", tool: "correlate_news_trades", summary: "Pre-news trading: 4 buy orders placed 47 minutes before AP report.",
    data: { pre_news_trades: 4, lead_time_minutes: 47, news_source: "Associated Press", news_published: "2024-11-03T12:00:00Z", total_pre_news_value: 312000, trade_direction: "BUY_YES", avg_execution_price: 0.62 },
  },
  {
    id: "A5", tool: "profile_wallet", summary: "Wallet 0x7a3f profile: 94% win rate, 23 trades, suspicious early activity.",
    data: { wallet: "0x7a3f", win_rate: 0.94, total_trades: 23, total_pnl_usd: 487000, first_activity: "2024-10-15T02:00:00Z", market_creation: "2024-10-15T08:00:00Z", hours_before_creation: 6, funding_source: "0xabc1", connected_wallets: ["0x2b8e", "0xd41c"] },
  },
];

const DEMO_NEWS: NewsArticle[] = [
  {
    title: "Polymarket Sees Surge in Election Betting Volume",
    url: "https://example.com/article1",
    source: "CoinDesk",
    publishedDate: "2024-11-03",
    description: "Trading volume on Polymarket's presidential election markets has surged over 300% in the past 24 hours, raising questions about the source of the influx.",
  },
  {
    title: "On-Chain Analysts Flag Suspicious Wallet Clusters",
    url: "https://example.com/article2",
    source: "The Block",
    publishedDate: "2024-11-02",
    description: "Blockchain analytics firms have identified clusters of wallets executing coordinated trades on prediction markets ahead of major news events.",
  },
  {
    title: "AP Report Triggers Major Market Movement",
    url: "https://example.com/article3",
    source: "Associated Press",
    publishedDate: "2024-11-03",
    description: "An AP investigation revealed new information that caused prediction market prices to shift dramatically within minutes of publication.",
  },
  {
    title: "Prediction Market Integrity Under Scrutiny",
    url: "https://example.com/article4",
    source: "Bloomberg",
    publishedDate: "2024-11-04",
    description: "Regulators are increasingly focused on prediction market platforms after reports of potential insider trading and coordinated manipulation.",
  },
];

const DEMO_PRICE_HISTORY: PricePoint[] = Array.from({ length: 20 }, (_, i) => {
  const base = 0.55 + Math.sin(i * 0.4) * 0.12 + (i / 20) * 0.15;
  const yes = Math.min(0.95, Math.max(0.3, base + (Math.random() - 0.5) * 0.05));
  return { date: `Nov ${(i + 1).toString().padStart(2, "0")}`, price_yes: +yes.toFixed(3), price_no: +(1 - yes).toFixed(3) };
});

const DEMO_VOLUME: VolumePoint[] = Array.from({ length: 14 }, (_, i) => {
  const isAbnormal = i === 8 || i === 9 || i === 12;
  const vol = isAbnormal ? 500000 + Math.random() * 400000 : 100000 + Math.random() * 200000;
  return { date: `Nov ${(i + 1).toString().padStart(2, "0")}`, volume_usdc: Math.round(vol), abnormal: isAbnormal };
});

const DEMO_REPORT = `## Executive Summary

Analysis of trading activity on this market reveals several concerning patterns suggesting possible informed trading. A cluster of large trades from connected wallets was detected approximately 47 minutes before a major news event, with volume spiking 340% above the 7-day average [A2]. Three wallets showing unusually high win rates (94%+) executed coordinated buy orders [A3][A5].

## Key Findings

1. **Pre-news trading detected**: 4 large buy orders totaling $312K were placed exactly 47 minutes before the Associated Press report was published [A4]. The timing precision suggests advance knowledge of the publication schedule.

2. **Volume anomaly**: A 340% volume spike was detected 2 hours before the news event, with a z-score of 4.2 indicating extreme statistical significance [A2]. Normal daily volume averages $230K; the anomaly window saw $792K in trades.

3. **Connected wallet cluster**: 17 trades exceeding $50K originated from just 3 wallets within a 24-hour window [A3]. These wallets share a common funding source (0xabc1) and have executed $1.8M in inter-wallet transfers.

4. **Suspicious wallet profile**: Wallet 0x7a3f demonstrates a 94% win rate across 23 trades with $487K in realized profit [A5]. Notably, this wallet's first activity predates market creation by 6 hours, suggesting insider access.

5. **Synchronized execution**: The identified wallet cluster executed 5 synchronized trade events within 30-second windows. Statistical analysis indicates the probability of this occurring by coincidence is less than 0.01% [A1].

## Confidence Assessment

Overall confidence: **HIGH** (0.87)

The convergence of multiple independent signals (volume anomaly, pre-news timing, wallet clustering, and synchronized execution) provides strong evidence of coordinated informed trading. Each signal alone might be coincidental, but their combination is highly improbable under normal market conditions.

## Limitations

This analysis is based on publicly available on-chain data and API responses. Wallet attribution relies on behavioral patterns and cannot confirm real-world identities. Correlation does not imply causation. The investigation did not have access to off-chain communication channels or exchange KYC data.

## Recommended Next Steps

- Deep-dive into wallet 0x7a3f full transaction history across all markets
- Cross-reference flagged wallets with other prediction market platforms (Augur, Gnosis)
- Monitor for continued coordinated activity in real-time
- Expand network analysis to second-degree wallet connections
- Submit findings to platform integrity team for further review`;

const DEMO_PREVIOUS: PreviousInvestigation[] = [
  { id: "inv-1", marketTitle: "US Presidential Election 2024 Winner", confidence: "HIGH", toolCount: 18, elapsedSeconds: 142, date: "2024-11-05" },
  { id: "inv-2", marketTitle: "Bitcoin Price Above $100K by Dec 2024", confidence: "MEDIUM", toolCount: 12, elapsedSeconds: 98, date: "2024-11-04" },
  { id: "inv-3", marketTitle: "Fed Rate Cut January 2025", confidence: "LOW", toolCount: 8, elapsedSeconds: 67, date: "2024-11-03" },
];

const INVESTIGATION_STEPS: InvestigationStep[] = [
  { label: "Market Data Collection", description: "Fetch baseline market metrics and trading history", complete: false },
  { label: "Statistical Analysis", description: "Detect volume anomalies and outlier patterns", complete: false },
  { label: "Trade Clustering", description: "Identify large trade clusters and connected wallets", complete: false },
  { label: "News Correlation", description: "Cross-reference trades with news timeline", complete: false },
  { label: "Wallet Profiling", description: "Deep-dive into flagged wallet histories", complete: false },
  { label: "Network Analysis", description: "Map wallet connections and fund flows", complete: false },
  { label: "Report Generation", description: "Synthesize findings into final report", complete: false },
];

/* ───────── Category colors ───────── */

const CATEGORY_COLORS: Record<string, string> = {
  market: "#3b82f6",
  statistical: "#a855f7",
  news: "#22c55e",
  wallet: "#f59e0b",
  network: "#ef4444",
};

/* ───────── Confidence badge ───────── */

function ConfidenceBadge({ level }: { level: "HIGH" | "MEDIUM" | "LOW" }) {
  const cls =
    level === "HIGH"
      ? "bg-emerald-500/10 text-emerald-400 border-emerald-500/20"
      : level === "MEDIUM"
        ? "bg-amber-500/10 text-amber-400 border-amber-500/20"
        : "bg-red-500/10 text-red-400 border-red-500/20";
  return (
    <span className={`inline-flex items-center gap-1 rounded-full border px-2.5 py-0.5 text-xs font-semibold ${cls}`}>
      <Shield className="h-3 w-3" />
      {level}
    </span>
  );
}

/* ───────── Artifact Modal ───────── */

function ArtifactModal({ artifact, onClose }: { artifact: Artifact; onClose: () => void }) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-sm" onClick={onClose}>
      <div
        className="relative mx-4 max-h-[80vh] w-full max-w-2xl overflow-y-auto rounded-xl border border-border bg-card p-6"
        onClick={(e) => e.stopPropagation()}
      >
        <button onClick={onClose} className="absolute right-4 top-4 text-muted-foreground hover:text-foreground transition-colors">
          <X className="h-5 w-5" />
        </button>
        <div className="flex items-center gap-3 mb-4">
          <span className="rounded-md bg-primary/10 px-2.5 py-1 text-sm font-bold text-primary">{artifact.id}</span>
          <span className="text-sm text-muted-foreground font-mono">{artifact.tool}</span>
        </div>
        <p className="text-sm text-foreground mb-4">{artifact.summary}</p>
        <div className="rounded-lg bg-background border border-border p-4 overflow-x-auto">
          <pre className="text-xs text-muted-foreground font-mono whitespace-pre-wrap">
            {JSON.stringify(artifact.data, null, 2)}
          </pre>
        </div>
      </div>
    </div>
  );
}

/* ───────── SVG Charts ───────── */

function PriceChart({ data }: { data: PricePoint[] }) {
  if (data.length === 0) return null;
  const w = 700, h = 200, pad = 40;
  const xStep = (w - pad * 2) / (data.length - 1);

  const toY = (v: number) => pad + (1 - v) * (h - pad * 2);

  const yesPath = data.map((p, i) => `${i === 0 ? "M" : "L"}${pad + i * xStep},${toY(p.price_yes)}`).join(" ");
  const noPath = data.map((p, i) => `${i === 0 ? "M" : "L"}${pad + i * xStep},${toY(p.price_no)}`).join(" ");

  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="w-full" preserveAspectRatio="xMidYMid meet">
      {/* grid lines */}
      {[0, 0.25, 0.5, 0.75, 1].map((v) => (
        <g key={v}>
          <line x1={pad} y1={toY(v)} x2={w - pad} y2={toY(v)} stroke="#252525" strokeWidth={1} />
          <text x={pad - 6} y={toY(v) + 4} textAnchor="end" fill="#6b6b6b" fontSize={10}>${v.toFixed(2)}</text>
        </g>
      ))}
      {/* x labels */}
      {data.filter((_, i) => i % 4 === 0).map((p, i) => (
        <text key={i} x={pad + (data.indexOf(p)) * xStep} y={h - 8} textAnchor="middle" fill="#6b6b6b" fontSize={9}>{p.date}</text>
      ))}
      <path d={yesPath} fill="none" stroke="#34d399" strokeWidth={2} />
      <path d={noPath} fill="none" stroke="#ef4444" strokeWidth={2} />
      {/* legend */}
      <circle cx={w - 140} cy={14} r={4} fill="#34d399" />
      <text x={w - 132} y={18} fill="#34d399" fontSize={10}>YES Price</text>
      <circle cx={w - 60} cy={14} r={4} fill="#ef4444" />
      <text x={w - 52} y={18} fill="#ef4444" fontSize={10}>NO Price</text>
    </svg>
  );
}

function VolumeChart({ data }: { data: VolumePoint[] }) {
  if (data.length === 0) return null;
  const w = 700, h = 180, pad = 50;
  const maxVol = Math.max(...data.map((d) => d.volume_usdc));
  const barW = Math.max(8, (w - pad * 2) / data.length - 4);

  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="w-full" preserveAspectRatio="xMidYMid meet">
      {[0, 0.5, 1].map((f) => {
        const y = pad + (1 - f) * (h - pad * 2);
        return (
          <g key={f}>
            <line x1={pad} y1={y} x2={w - pad} y2={y} stroke="#252525" strokeWidth={1} />
            <text x={pad - 6} y={y + 4} textAnchor="end" fill="#6b6b6b" fontSize={9}>
              ${Math.round(maxVol * f / 1000)}K
            </text>
          </g>
        );
      })}
      {data.map((d, i) => {
        const barH = (d.volume_usdc / maxVol) * (h - pad * 2);
        const x = pad + i * ((w - pad * 2) / data.length) + 2;
        const y = h - pad - barH;
        return (
          <g key={i}>
            <rect x={x} y={y} width={barW} height={barH} rx={3} fill={d.abnormal ? "#ef4444" : "#3b82f6"} opacity={0.8} />
            {i % 2 === 0 && (
              <text x={x + barW / 2} y={h - 8} textAnchor="middle" fill="#6b6b6b" fontSize={8}>{d.date.replace("Nov ", "")}</text>
            )}
          </g>
        );
      })}
      {/* legend */}
      <rect x={w - 160} y={8} width={10} height={10} rx={2} fill="#3b82f6" />
      <text x={w - 146} y={17} fill="#6b6b6b" fontSize={10}>Normal</text>
      <rect x={w - 80} y={8} width={10} height={10} rx={2} fill="#ef4444" />
      <text x={w - 66} y={17} fill="#6b6b6b" fontSize={10}>Abnormal</text>
    </svg>
  );
}

/* ───────── Tree Graph SVG ───────── */

function TreeGraph({ nodes }: { nodes: TreeNode[] }) {
  const nodeW = 180, nodeH = 60, gapX = 40, gapY = 90;
  const positions = useMemo(() => {
    const pos: Record<string, { x: number; y: number }> = {};
    const depthCounts: Record<number, number> = {};
    nodes.forEach((n) => {
      const d = n.depth;
      depthCounts[d] = (depthCounts[d] || 0) + 1;
    });
    const depthIndex: Record<number, number> = {};
    nodes.forEach((n) => {
      const d = n.depth;
      depthIndex[d] = (depthIndex[d] || 0);
      const count = depthCounts[d];
      const totalW = count * (nodeW + gapX) - gapX;
      const startX = (900 - totalW) / 2;
      pos[n.id] = { x: startX + depthIndex[d] * (nodeW + gapX), y: 20 + d * gapY };
      depthIndex[d]++;
    });
    return pos;
  }, [nodes]);

  const maxY = Math.max(...Object.values(positions).map((p) => p.y), 0);
  const svgH = maxY + nodeH + 40;

  return (
    <svg viewBox={`0 0 900 ${svgH}`} className="w-full" preserveAspectRatio="xMidYMid meet">
      {/* connecting lines */}
      {nodes.filter((n) => n.parentId && positions[n.parentId]).map((n) => {
        const parent = positions[n.parentId!];
        const child = positions[n.id];
        if (!parent || !child) return null;
        return (
          <line
            key={`line-${n.id}`}
            x1={parent.x + nodeW / 2} y1={parent.y + nodeH}
            x2={child.x + nodeW / 2} y2={child.y}
            stroke="#252525" strokeWidth={2}
          />
        );
      })}
      {/* nodes */}
      {nodes.map((n) => {
        const p = positions[n.id];
        if (!p) return null;
        const col = CATEGORY_COLORS[n.category] || "#6b6b6b";
        return (
          <g key={n.id}>
            <rect x={p.x} y={p.y} width={nodeW} height={nodeH} rx={8} fill="#141414" stroke={col} strokeWidth={1.5} />
            <text x={p.x + 10} y={p.y + 20} fill="#f5f0e8" fontSize={11} fontWeight={600}>
              {n.hypothesis.length > 22 ? n.hypothesis.slice(0, 22) + "..." : n.hypothesis}
            </text>
            <text x={p.x + 10} y={p.y + 36} fill="#6b6b6b" fontSize={9} fontFamily="monospace">{n.tool}</text>
            <text x={p.x + 10} y={p.y + 50} fill={col} fontSize={9}>{n.category}</text>
            <circle cx={p.x + nodeW - 14} cy={p.y + 14} r={5} fill={n.status === "active" ? "#f59e0b" : "#34d399"} />
          </g>
        );
      })}
    </svg>
  );
}

/* ───────── Tabs type ───────── */

type TabKey = "overview" | "report" | "evidence" | "news" | "tree" | "previous";

/* ═══════════════ MAIN COMPONENT ═══════════════ */

export default function InvestigationPage() {
  const [searchParams] = useSearchParams();
  const slug = searchParams.get("slug") || "presidential-election-2024";
  const navigate = useNavigate();

  const [phase, setPhase] = useState<"input" | "running" | "complete">("input");
  const [slugInput, setSlugInput] = useState(slug);
  const [goal, setGoal] = useState("");
  const [elapsed, setElapsed] = useState(0);
  const [tree, setTree] = useState<TreeNode[]>([]);
  const [artifacts, setArtifacts] = useState<Artifact[]>([]);
  const [news, setNews] = useState<NewsArticle[]>([]);
  const [steps, setSteps] = useState<InvestigationStep[]>(INVESTIGATION_STEPS.map((s) => ({ ...s })));
  const [report, setReport] = useState("");
  const [activeTab, setActiveTab] = useState<TabKey>("overview");
  const [modalArtifact, setModalArtifact] = useState<Artifact | null>(null);
  const [treeView, setTreeView] = useState<"list" | "graph">("list");
  const [autoScroll, setAutoScroll] = useState(true);
  const [statusDesc, setStatusDesc] = useState("");
  const [confidence, setConfidence] = useState<{ level: "HIGH" | "MEDIUM" | "LOW"; score: number } | null>(null);

  const treeEndRef = useRef<HTMLDivElement>(null);
  const timerRef = useRef<number | null>(null);
  const simRef = useRef<number[]>([]);

  // Auto-scroll
  useEffect(() => {
    if (autoScroll && treeEndRef.current) {
      treeEndRef.current.scrollIntoView({ behavior: "smooth" });
    }
  }, [tree, autoScroll]);

  // Timer
  useEffect(() => {
    if (phase === "running") {
      timerRef.current = window.setInterval(() => setElapsed((e) => e + 1), 1000);
    }
    return () => { if (timerRef.current) clearInterval(timerRef.current); };
  }, [phase]);

  const stopInvestigation = useCallback(() => {
    simRef.current.forEach((id) => clearTimeout(id));
    simRef.current = [];
    if (timerRef.current) clearInterval(timerRef.current);
    setPhase("complete");
    setTree(DEMO_TREE.map((n) => ({ ...n, status: "closed" as const })));
    setArtifacts(DEMO_ARTIFACTS);
    setNews(DEMO_NEWS);
    setReport(DEMO_REPORT);
    setSteps(INVESTIGATION_STEPS.map((s) => ({ ...s, complete: true })));
    setConfidence({ level: "HIGH", score: 0.87 });
    setStatusDesc("Investigation complete");
  }, []);

  function startInvestigation() {
    setPhase("running");
    setTree([]);
    setArtifacts([]);
    setNews([]);
    setReport("");
    setElapsed(0);
    setSteps(INVESTIGATION_STEPS.map((s) => ({ ...s, complete: false })));
    setConfidence(null);
    setStatusDesc("Initializing investigation...");
    setActiveTab("overview");

    const toolDescs = [
      "Fetching market data...",
      "Running volume anomaly detection...",
      "Analyzing large trade clusters...",
      "Correlating news timeline with trades...",
      "Profiling flagged wallets...",
      "Mapping wallet network connections...",
      "Detecting synchronized trade patterns...",
    ];

    const ids: number[] = [];

    // Progressively add tree nodes
    DEMO_TREE.forEach((node, i) => {
      const id = window.setTimeout(() => {
        setTree((prev) => [...prev, { ...node, status: i < DEMO_TREE.length - 1 ? "closed" : "active" }]);
        setStatusDesc(toolDescs[i] || "Processing...");
        setSteps((prev) => prev.map((s, si) => si <= i ? { ...s, complete: true } : s));
      }, (i + 1) * 1500);
      ids.push(id);
    });

    // Add artifacts progressively
    DEMO_ARTIFACTS.forEach((art, i) => {
      const id = window.setTimeout(() => {
        setArtifacts((prev) => [...prev, art]);
      }, (i + 1) * 2000 + 500);
      ids.push(id);
    });

    // Add news midway
    const newsId = window.setTimeout(() => {
      setNews(DEMO_NEWS);
    }, 5000);
    ids.push(newsId);

    // Complete
    const completeId = window.setTimeout(() => {
      if (timerRef.current) clearInterval(timerRef.current);
      setPhase("complete");
      setTree(DEMO_TREE.map((n) => ({ ...n, status: "closed" as const })));
      setArtifacts(DEMO_ARTIFACTS);
      setNews(DEMO_NEWS);
      setReport(DEMO_REPORT);
      setSteps(INVESTIGATION_STEPS.map((s) => ({ ...s, complete: true })));
      setConfidence({ level: "HIGH", score: 0.87 });
      setStatusDesc("Investigation complete");
    }, DEMO_TREE.length * 1500 + 3000);
    ids.push(completeId);

    simRef.current = ids;
  }

  const formatTime = (s: number) => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
  const title = slug.replace(/-/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());

  const totalToolCalls = tree.reduce((s, n) => s + (n.tool ? 1 : 0), 0);
  const totalLLMCalls = tree.length * 2;

  // Handle citation clicks in report
  function openCitation(artifactId: string) {
    const art = DEMO_ARTIFACTS.find((a) => a.id === artifactId);
    if (art) setModalArtifact(art);
  }

  function renderReport(text: string) {
    // Split by citation references and make them clickable
    const parts = text.split(/(\[A\d+\])/g);
    return parts.map((part, i) => {
      const match = part.match(/^\[(A\d+)\]$/);
      if (match) {
        return (
          <button
            key={i}
            onClick={() => openCitation(match[1])}
            className="text-primary hover:text-primary-dark hover:underline font-semibold text-xs mx-0.5"
          >
            {part}
          </button>
        );
      }
      // Handle markdown bold
      const boldParts = part.split(/(\*\*[^*]+\*\*)/g);
      return boldParts.map((bp, j) => {
        if (bp.startsWith("**") && bp.endsWith("**")) {
          return <strong key={`${i}-${j}`} className="text-foreground">{bp.slice(2, -2)}</strong>;
        }
        return <span key={`${i}-${j}`}>{bp}</span>;
      });
    });
  }

  /* ───────── Tab definitions ───────── */
  const tabs: { key: TabKey; label: string; icon: React.ReactNode; count?: number }[] = [
    { key: "overview", label: "Overview", icon: <BarChart3 className="h-4 w-4" /> },
    { key: "report", label: "Report", icon: <FileText className="h-4 w-4" /> },
    { key: "evidence", label: "Evidence", icon: <Search className="h-4 w-4" />, count: artifacts.length },
    { key: "news", label: "News", icon: <Newspaper className="h-4 w-4" />, count: news.length },
    { key: "tree", label: "Tree", icon: <GitBranch className="h-4 w-4" />, count: tree.length },
    { key: "previous", label: "Previous", icon: <History className="h-4 w-4" /> },
  ];

  /* ═══════════════ RENDER ═══════════════ */

  return (
    <div className="min-h-screen pt-16">
      {/* Artifact Modal */}
      {modalArtifact && <ArtifactModal artifact={modalArtifact} onClose={() => setModalArtifact(null)} />}

      <div className="mx-auto max-w-6xl px-6 py-8">
        {/* Back button */}
        <button
          onClick={() => navigate("/dashboard")}
          className="mb-4 inline-flex items-center gap-1 text-sm text-muted-foreground transition-colors hover:text-primary"
        >
          <ArrowLeft className="h-4 w-4" /> Back to Dashboard
        </button>

        <h1 className="text-2xl font-bold flex items-center gap-3">
          <Activity className="h-6 w-6 text-primary" />
          {title}
        </h1>

        {/* ───── INPUT PHASE ───── */}
        {phase === "input" && (
          <div className="mt-8 grid gap-8 lg:grid-cols-[1fr,380px]">
            {/* Start form */}
            <div className="rounded-xl border border-border bg-card p-6 hover:border-primary/20 hover:shadow-[0_0_20px_rgba(245,158,11,0.1)] transition-all">
              <h2 className="text-lg font-semibold flex items-center gap-2">
                <Play className="h-5 w-5 text-primary" />
                New Investigation
              </h2>
              <p className="mt-1 text-sm text-muted-foreground">
                Enter a market slug and optionally describe your investigation goal.
              </p>

              <label className="mt-4 block text-xs font-medium text-muted-foreground uppercase tracking-wider">Market Slug</label>
              <input
                type="text"
                value={slugInput}
                onChange={(e) => setSlugInput(e.target.value)}
                placeholder="e.g. presidential-election-2024"
                className="mt-1 w-full rounded-xl border border-border bg-surface px-4 py-3 text-sm text-foreground placeholder:text-muted-foreground outline-none transition-colors focus:border-primary"
              />

              <label className="mt-4 block text-xs font-medium text-muted-foreground uppercase tracking-wider">Investigation Goal (optional)</label>
              <textarea
                value={goal}
                onChange={(e) => setGoal(e.target.value)}
                placeholder="e.g. Look for insider trading, coordinated wallets, pre-news activity..."
                rows={3}
                className="mt-1 w-full rounded-xl border border-border bg-surface px-4 py-3 text-sm text-foreground placeholder:text-muted-foreground outline-none transition-colors focus:border-primary resize-none"
              />

              <button
                onClick={startInvestigation}
                className="mt-4 inline-flex w-full items-center justify-center gap-2 rounded-xl bg-primary py-3 text-sm font-semibold text-primary-foreground transition-all hover:-translate-y-px hover:bg-primary-dark hover:shadow-[0_0_20px_rgba(245,158,11,0.25)]"
              >
                <Play className="h-4 w-4" /> Launch Investigation
              </button>
            </div>

            {/* Previous investigations */}
            <div>
              <h3 className="text-sm font-semibold text-muted-foreground uppercase tracking-wider mb-3">Previous Investigations</h3>
              <div className="space-y-3">
                {DEMO_PREVIOUS.map((inv) => (
                  <div
                    key={inv.id}
                    className="rounded-xl border border-border bg-card p-4 hover:border-primary/20 hover:shadow-[0_0_20px_rgba(245,158,11,0.1)] transition-all cursor-pointer"
                  >
                    <div className="flex items-start justify-between gap-2">
                      <span className="text-sm font-medium leading-tight">{inv.marketTitle}</span>
                      <ConfidenceBadge level={inv.confidence} />
                    </div>
                    <div className="mt-2 flex items-center gap-4 text-xs text-muted-foreground">
                      <span className="flex items-center gap-1"><Wrench className="h-3 w-3" />{inv.toolCount} tools</span>
                      <span className="flex items-center gap-1"><Clock className="h-3 w-3" />{formatTime(inv.elapsedSeconds)}</span>
                      <span>{inv.date}</span>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}

        {/* ───── ACTIVE PHASE (running / complete) ───── */}
        {phase !== "input" && (
          <div className="mt-6">
            {/* Status bar */}
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
              {statusDesc && (
                <span className="text-xs text-muted-foreground italic">{statusDesc}</span>
              )}
              <div className="ml-auto flex items-center gap-4">
                <div className="flex items-center gap-1 text-xs text-muted-foreground">
                  <Clock className="h-3 w-3" /> {formatTime(elapsed)}
                </div>
                {phase === "running" && (
                  <button
                    onClick={stopInvestigation}
                    className="inline-flex items-center gap-1.5 rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-1.5 text-xs font-medium text-destructive hover:bg-destructive/20 transition-colors"
                  >
                    <Square className="h-3 w-3" /> Stop
                  </button>
                )}
                <button
                  onClick={() => { stopInvestigation(); setPhase("input"); setTree([]); setArtifacts([]); setNews([]); setReport(""); setElapsed(0); }}
                  className="inline-flex items-center gap-1.5 rounded-lg border border-border px-3 py-1.5 text-xs font-medium text-muted-foreground hover:text-foreground hover:border-primary/20 transition-colors"
                >
                  <ArrowLeft className="h-3 w-3" /> Back
                </button>
              </div>
            </div>

            {/* Tabs */}
            <div className="mt-6 flex gap-1 border-b border-border overflow-x-auto">
              {tabs.map((tab) => (
                <button
                  key={tab.key}
                  onClick={() => setActiveTab(tab.key)}
                  className={`inline-flex items-center gap-1.5 whitespace-nowrap px-4 py-2.5 text-sm font-medium transition-colors ${
                    activeTab === tab.key
                      ? "border-b-2 border-primary text-primary"
                      : "text-muted-foreground hover:text-foreground"
                  }`}
                >
                  {tab.icon}
                  {tab.label}
                  {tab.count !== undefined && tab.count > 0 && (
                    <span className="rounded-full bg-primary/10 px-1.5 py-0.5 text-[10px] font-bold text-primary">
                      {tab.count}
                    </span>
                  )}
                </button>
              ))}
            </div>

            {/* ─── OVERVIEW TAB ─── */}
            {activeTab === "overview" && (
              <div className="mt-6 space-y-6">
                {/* Stats row */}
                <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
                  {[
                    { label: "Tool Calls", value: totalToolCalls, icon: <Wrench className="h-4 w-4 text-primary" /> },
                    { label: "LLM Calls", value: totalLLMCalls, icon: <Brain className="h-4 w-4 text-purple-400" /> },
                    { label: "Evidence", value: artifacts.length, icon: <Search className="h-4 w-4 text-blue-400" /> },
                    { label: "Articles", value: news.length, icon: <Newspaper className="h-4 w-4 text-green-400" /> },
                    { label: "Nodes", value: tree.length, icon: <GitBranch className="h-4 w-4 text-amber-400" /> },
                    { label: "Duration", value: formatTime(elapsed), icon: <Clock className="h-4 w-4 text-muted-foreground" /> },
                  ].map((stat) => (
                    <div key={stat.label} className="rounded-xl border border-border bg-card p-3 text-center">
                      <div className="flex justify-center mb-1">{stat.icon}</div>
                      <div className="text-lg font-bold">{stat.value}</div>
                      <div className="text-[10px] uppercase tracking-wider text-muted-foreground">{stat.label}</div>
                    </div>
                  ))}
                </div>

                {/* Confidence */}
                {confidence && (
                  <div className="rounded-xl border border-border bg-card p-4">
                    <h3 className="text-sm font-semibold uppercase tracking-wider text-muted-foreground mb-3">Confidence Assessment</h3>
                    <div className="flex items-center gap-4">
                      <ConfidenceBadge level={confidence.level} />
                      <div className="flex-1">
                        <div className="h-2 rounded-full bg-muted overflow-hidden">
                          <div
                            className="h-full rounded-full transition-all duration-1000"
                            style={{
                              width: `${confidence.score * 100}%`,
                              backgroundColor: confidence.level === "HIGH" ? "#34d399" : confidence.level === "MEDIUM" ? "#f59e0b" : "#ef4444",
                            }}
                          />
                        </div>
                      </div>
                      <span className="text-sm font-mono font-bold">{(confidence.score * 100).toFixed(0)}%</span>
                    </div>
                  </div>
                )}

                {/* Investigation Steps */}
                <div className="rounded-xl border border-border bg-card p-4">
                  <h3 className="text-sm font-semibold uppercase tracking-wider text-muted-foreground mb-3">Investigation Steps</h3>
                  <div className="space-y-2">
                    {steps.map((step, i) => (
                      <div key={i} className="flex items-center gap-3 text-sm">
                        {step.complete ? (
                          <CheckCircle2 className="h-4 w-4 text-success flex-shrink-0" />
                        ) : phase === "running" && i === steps.findIndex((s) => !s.complete) ? (
                          <Loader2 className="h-4 w-4 animate-spin text-primary flex-shrink-0" />
                        ) : (
                          <div className="h-4 w-4 rounded-full border border-border flex-shrink-0" />
                        )}
                        <span className={step.complete ? "text-foreground" : "text-muted-foreground"}>{step.label}</span>
                        <span className="text-xs text-muted-foreground hidden sm:inline">- {step.description}</span>
                      </div>
                    ))}
                  </div>
                </div>

                {/* Price History Chart */}
                <div className="rounded-xl border border-border bg-card p-4">
                  <h3 className="text-sm font-semibold uppercase tracking-wider text-muted-foreground mb-3 flex items-center gap-2">
                    <TrendingUp className="h-4 w-4" /> Price History
                  </h3>
                  <PriceChart data={DEMO_PRICE_HISTORY} />
                </div>

                {/* Daily Volume Chart */}
                <div className="rounded-xl border border-border bg-card p-4">
                  <h3 className="text-sm font-semibold uppercase tracking-wider text-muted-foreground mb-3 flex items-center gap-2">
                    <BarChart3 className="h-4 w-4" /> Daily Volume
                  </h3>
                  <VolumeChart data={DEMO_VOLUME} />
                </div>
              </div>
            )}

            {/* ─── REPORT TAB ─── */}
            {activeTab === "report" && (
              <div className="mt-6">
                {phase === "complete" && report ? (
                  <div className="rounded-xl border border-border bg-card p-6">
                    <h2 className="text-xl font-bold flex items-center gap-2">
                      <FileText className="h-5 w-5 text-primary" />
                      Investigation Report
                    </h2>
                    <p className="mt-1 text-sm text-muted-foreground">{title}</p>
                    <div className="mt-6 space-y-4">
                      {report.split("\n\n").map((para, i) => {
                        if (para.startsWith("## ")) {
                          return (
                            <h3 key={i} className="flex items-center gap-2 text-sm font-semibold uppercase tracking-wider text-primary pt-2">
                              <AlertTriangle className="h-4 w-4" />
                              {para.replace("## ", "")}
                            </h3>
                          );
                        }
                        if (para.match(/^\d+\./m)) {
                          const items = para.split("\n").filter(Boolean);
                          return (
                            <ul key={i} className="space-y-2">
                              {items.map((item, j) => (
                                <li key={j} className="flex gap-2 text-sm leading-relaxed text-muted-foreground">
                                  <span className="mt-0.5 text-primary font-semibold">{j + 1}.</span>
                                  <span>{renderReport(item.replace(/^\d+\.\s*/, ""))}</span>
                                </li>
                              ))}
                            </ul>
                          );
                        }
                        if (para.startsWith("- ")) {
                          const items = para.split("\n").filter(Boolean);
                          return (
                            <ul key={i} className="space-y-1">
                              {items.map((item, j) => (
                                <li key={j} className="text-sm text-muted-foreground">
                                  {renderReport(item)}
                                </li>
                              ))}
                            </ul>
                          );
                        }
                        return (
                          <p key={i} className="text-sm leading-relaxed text-muted-foreground">
                            {renderReport(para)}
                          </p>
                        );
                      })}
                    </div>
                  </div>
                ) : (
                  <div className="flex flex-col items-center justify-center py-16 text-muted-foreground">
                    {phase === "running" ? (
                      <>
                        <Loader2 className="h-8 w-8 animate-spin text-primary mb-3" />
                        <p className="text-sm">Report will be generated when the investigation completes...</p>
                      </>
                    ) : (
                      <p className="text-sm">No report available.</p>
                    )}
                  </div>
                )}
              </div>
            )}

            {/* ─── EVIDENCE TAB ─── */}
            {activeTab === "evidence" && (
              <div className="mt-6 space-y-3">
                {artifacts.length > 0 ? (
                  artifacts.map((a) => (
                    <button
                      key={a.id}
                      onClick={() => setModalArtifact(a)}
                      className="w-full rounded-xl border border-border bg-card p-4 text-left transition-all hover:border-primary/20 hover:shadow-[0_0_20px_rgba(245,158,11,0.1)]"
                    >
                      <div className="flex items-center gap-3">
                        <span className="rounded-md bg-primary/10 px-2.5 py-1 text-xs font-bold text-primary">{a.id}</span>
                        <span className="flex-1">
                          <span className="text-sm font-medium">{a.summary}</span>
                        </span>
                        <span className="rounded-lg bg-muted px-2.5 py-0.5 text-xs text-muted-foreground font-mono">{a.tool}</span>
                        <ChevronRight className="h-4 w-4 text-muted-foreground" />
                      </div>
                    </button>
                  ))
                ) : (
                  <div className="flex flex-col items-center justify-center py-16 text-muted-foreground">
                    {phase === "running" ? (
                      <>
                        <Loader2 className="h-8 w-8 animate-spin text-primary mb-3" />
                        <p className="text-sm">Evidence will appear as the investigation progresses...</p>
                      </>
                    ) : (
                      <p className="text-sm">No evidence collected.</p>
                    )}
                  </div>
                )}
              </div>
            )}

            {/* ─── NEWS TAB ─── */}
            {activeTab === "news" && (
              <div className="mt-6 space-y-3">
                {news.length > 0 ? (
                  news.map((article, i) => (
                    <div
                      key={i}
                      className="rounded-xl border border-border bg-card p-4 transition-all hover:border-primary/20 hover:shadow-[0_0_20px_rgba(245,158,11,0.1)]"
                    >
                      <div className="flex items-start justify-between gap-3">
                        <div className="flex-1">
                          <a
                            href={article.url}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="text-sm font-medium text-foreground hover:text-primary transition-colors inline-flex items-center gap-1"
                          >
                            {article.title}
                            <ExternalLink className="h-3 w-3 text-muted-foreground" />
                          </a>
                          <div className="mt-1 flex items-center gap-3 text-xs text-muted-foreground">
                            <span className="font-semibold text-primary/70">{article.source}</span>
                            <span>{article.publishedDate}</span>
                          </div>
                          <p className="mt-2 text-xs text-muted-foreground leading-relaxed line-clamp-2">{article.description}</p>
                        </div>
                      </div>
                    </div>
                  ))
                ) : (
                  <div className="flex flex-col items-center justify-center py-16 text-muted-foreground">
                    {phase === "running" ? (
                      <>
                        <Loader2 className="h-8 w-8 animate-spin text-primary mb-3" />
                        <p className="text-sm">Scanning for relevant news articles...</p>
                      </>
                    ) : (
                      <p className="text-sm">No news articles found.</p>
                    )}
                  </div>
                )}
              </div>
            )}

            {/* ─── TREE TAB ─── */}
            {activeTab === "tree" && (
              <div className="mt-6">
                {/* Controls */}
                <div className="flex items-center gap-3 mb-4">
                  <div className="inline-flex rounded-lg border border-border overflow-hidden">
                    <button
                      onClick={() => setTreeView("list")}
                      className={`inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium transition-colors ${
                        treeView === "list" ? "bg-primary text-primary-foreground" : "text-muted-foreground hover:text-foreground"
                      }`}
                    >
                      <List className="h-3 w-3" /> List
                    </button>
                    <button
                      onClick={() => setTreeView("graph")}
                      className={`inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium transition-colors ${
                        treeView === "graph" ? "bg-primary text-primary-foreground" : "text-muted-foreground hover:text-foreground"
                      }`}
                    >
                      <Network className="h-3 w-3" /> Graph
                    </button>
                  </div>
                  <label className="ml-auto inline-flex items-center gap-1.5 text-xs text-muted-foreground cursor-pointer">
                    <input
                      type="checkbox"
                      checked={autoScroll}
                      onChange={(e) => setAutoScroll(e.target.checked)}
                      className="rounded border-border accent-primary"
                    />
                    Auto-scroll
                  </label>
                </div>

                {tree.length > 0 ? (
                  treeView === "list" ? (
                    <div className="space-y-2">
                      {tree.map((node) => (
                        <div
                          key={node.id}
                          className="rounded-xl border bg-card p-4 transition-all hover:border-primary/20 hover:shadow-[0_0_20px_rgba(245,158,11,0.1)]"
                          style={{
                            marginLeft: node.depth * 28,
                            borderColor: CATEGORY_COLORS[node.category] + "33",
                            borderLeftWidth: 3,
                            borderLeftColor: CATEGORY_COLORS[node.category],
                          }}
                        >
                          <div className="flex items-start gap-3">
                            <div className="flex-1 min-w-0">
                              <div className="flex items-center gap-2 flex-wrap">
                                <span className="text-sm font-semibold">{node.hypothesis}</span>
                                <span
                                  className="rounded-full px-2 py-0.5 text-[10px] font-bold"
                                  style={{ backgroundColor: CATEGORY_COLORS[node.category] + "20", color: CATEGORY_COLORS[node.category] }}
                                >
                                  {node.category}
                                </span>
                                <span className="rounded-full bg-muted px-2 py-0.5 text-[10px] text-muted-foreground font-mono">
                                  depth {node.depth}
                                </span>
                                <span className={`rounded-full px-2 py-0.5 text-[10px] font-semibold ${
                                  node.status === "active"
                                    ? "bg-amber-500/10 text-amber-400"
                                    : "bg-emerald-500/10 text-emerald-400"
                                }`}>
                                  {node.status}
                                </span>
                              </div>
                              <div className="mt-1.5 text-xs text-muted-foreground font-mono">{node.tool}</div>
                              <div className="mt-1 text-xs text-muted-foreground">
                                <span className="text-foreground/60 font-medium">Q:</span> {node.question}
                              </div>
                              <div className="mt-1 text-xs text-muted-foreground">
                                <span className="text-success/80 font-medium">R:</span> {node.result}
                              </div>
                            </div>
                          </div>
                        </div>
                      ))}
                      <div ref={treeEndRef} />
                    </div>
                  ) : (
                    <div className="rounded-xl border border-border bg-card p-4 overflow-x-auto">
                      <TreeGraph nodes={tree} />
                    </div>
                  )
                ) : (
                  <div className="flex flex-col items-center justify-center py-16 text-muted-foreground">
                    {phase === "running" ? (
                      <>
                        <Loader2 className="h-8 w-8 animate-spin text-primary mb-3" />
                        <p className="text-sm">Building investigation tree...</p>
                      </>
                    ) : (
                      <p className="text-sm">No tree nodes.</p>
                    )}
                  </div>
                )}
              </div>
            )}

            {/* ─── PREVIOUS TAB ─── */}
            {activeTab === "previous" && (
              <div className="mt-6 space-y-3">
                {DEMO_PREVIOUS.map((inv) => (
                  <div
                    key={inv.id}
                    className="rounded-xl border border-border bg-card p-4 transition-all hover:border-primary/20 hover:shadow-[0_0_20px_rgba(245,158,11,0.1)] cursor-pointer"
                  >
                    <div className="flex items-center justify-between gap-3">
                      <div className="flex-1">
                        <span className="text-sm font-medium">{inv.marketTitle}</span>
                        <div className="mt-1.5 flex items-center gap-4 text-xs text-muted-foreground">
                          <span className="flex items-center gap-1"><Wrench className="h-3 w-3" />{inv.toolCount} tools</span>
                          <span className="flex items-center gap-1"><Clock className="h-3 w-3" />{formatTime(inv.elapsedSeconds)}</span>
                          <span>{inv.date}</span>
                        </div>
                      </div>
                      <ConfidenceBadge level={inv.confidence} />
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
