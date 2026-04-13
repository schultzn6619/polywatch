import { useState, useEffect, type FormEvent } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import {
  Search,
  LogOut,
  ArrowRight,
  Terminal,
  Anchor,
  Radar,
  FileText,
  Lock,
  HelpCircle,
} from "lucide-react";
import {
  searchEvents,
  type PolymarketEvent,
} from "../services/polymarket";

function formatVolume(vol: number): string {
  if (vol >= 1_000_000_000) return `$${(vol / 1_000_000_000).toFixed(1)}B`;
  if (vol >= 1_000_000) return `$${(vol / 1_000_000).toFixed(0)}M`;
  if (vol >= 1_000) return `$${(vol / 1_000).toFixed(0)}K`;
  return `$${vol.toFixed(0)}`;
}

type SidebarTab = "scan" | "terminal" | "whales" | "reports" | "vault";

const sidebarNav: { icon: typeof Radar; label: string; tab: SidebarTab }[] = [
  { icon: Terminal, label: "Terminal", tab: "terminal" },
  { icon: Anchor, label: "Whales", tab: "whales" },
  { icon: Radar, label: "Scan", tab: "scan" },
  { icon: FileText, label: "Reports", tab: "reports" },
  { icon: Lock, label: "Vault", tab: "vault" },
];

export default function DashboardPage() {
  const [query, setQuery] = useState("");
  const [events, setEvents] = useState<PolymarketEvent[]>([]);
  const [loading, setLoading] = useState(false);
  const [searched, setSearched] = useState(false);
  const [error, setError] = useState("");
  const [activeTab, setActiveTab] = useState<SidebarTab>("scan");
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();

  // Auto-search if ?q= param is present
  useEffect(() => {
    const q = searchParams.get("q");
    if (q) {
      setQuery(q);
      doSearch(q);
    }
  }, []);

  function handleLogout() {
    localStorage.removeItem("polywatch_user");
    navigate("/login");
  }

  async function doSearch(q: string) {
    setLoading(true);
    setSearched(true);
    setError("");
    try {
      const results = await searchEvents(q);
      setEvents(results);
    } catch {
      setError("Failed to search Polymarket. Please try again.");
      setEvents([]);
    }
    setLoading(false);
  }

  function handleSearch(e: FormEvent) {
    e.preventDefault();
    const q = query.trim();
    if (!q) return;
    doSearch(q);
  }

  return (
    <div className="flex min-h-screen pt-16">
      {/* Sidebar */}
      <aside className="hidden lg:flex w-56 flex-col border-r border-border bg-surface px-3 py-6 fixed top-16 bottom-0">
        <div className="flex items-center gap-2 px-3 mb-6">
          <Radar className="h-5 w-5 text-primary" />
          <span className="text-xs font-semibold tracking-widest uppercase text-muted-foreground">
            AI Investigation Unit
          </span>
        </div>
        <nav className="flex-1 space-y-1">
          {sidebarNav.map((item) => (
            <button
              key={item.label}
              onClick={() => setActiveTab(item.tab)}
              className={`flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-sm transition-colors ${
                activeTab === item.tab
                  ? "bg-primary/10 text-primary font-medium"
                  : "text-muted-foreground hover:text-foreground hover:bg-muted"
              }`}
            >
              <item.icon className="h-4 w-4" />
              {item.label}
            </button>
          ))}
        </nav>
        <div className="border-t border-border pt-4 space-y-1">
          <button className="flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-sm text-muted-foreground hover:text-foreground hover:bg-muted transition-colors">
            <HelpCircle className="h-4 w-4" /> Support
          </button>
          <button
            onClick={handleLogout}
            className="flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-sm text-muted-foreground hover:text-foreground hover:bg-muted transition-colors"
          >
            <LogOut className="h-4 w-4" /> Logout
          </button>
        </div>
      </aside>

      {/* Main */}
      <div className="flex-1 lg:ml-56">
        <div className="px-6 py-8 max-w-6xl">
          {/* ═══ SCAN TAB ═══ */}
          {activeTab === "scan" && (
            <>
              <div className="flex items-center justify-between">
                <div>
                  <h1 className="text-2xl font-bold">Search and explore Polymarket events</h1>
                  <p className="mt-1 text-sm text-muted-foreground">
                    Search any market on Polymarket to begin an AI-powered investigation.
                  </p>
                </div>
                <button
                  onClick={handleLogout}
                  className="hidden lg:hidden inline-flex items-center gap-2 rounded-xl border border-border px-4 py-2 text-sm text-muted-foreground hover:text-foreground hover:border-primary/30 transition-colors"
                >
                  <LogOut className="h-4 w-4" /> Sign out
                </button>
              </div>

              {/* Search */}
              <form onSubmit={handleSearch} className="mt-6 flex gap-3">
                <div className="relative flex-1">
                  <Search className="absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
                  <input
                    type="text"
                    value={query}
                    onChange={(e) => setQuery(e.target.value)}
                    placeholder="Search events... (e.g. iran, bitcoin, election, fed)"
                    className="w-full rounded-xl border border-border bg-background py-2.5 pl-10 pr-4 text-sm text-foreground placeholder:text-muted-foreground outline-none transition-colors focus:border-primary"
                  />
                </div>
                <button
                  type="submit"
                  disabled={loading}
                  className="rounded-xl bg-primary px-6 py-2.5 text-sm font-semibold text-primary-foreground transition-all hover:-translate-y-px hover:bg-primary-dark hover:shadow-[0_0_20px_rgba(245,158,11,0.25)] disabled:opacity-40"
                >
                  {loading ? "Searching..." : "Search"}
                </button>
              </form>

              {/* Error */}
              {error && (
                <div className="mt-6 rounded-xl border border-destructive/30 bg-destructive/5 p-4 text-sm text-destructive">
                  {error}
                </div>
              )}

              {/* Loading */}
              {loading && (
                <div className="mt-8 text-center text-sm text-muted-foreground">
                  Searching Polymarket...
                </div>
              )}

              {/* No results */}
              {!loading && searched && events.length === 0 && !error && (
                <div className="mt-8 text-center">
                  <p className="text-sm text-muted-foreground">
                    No events found for "<span className="text-foreground font-medium">{query}</span>". Try a different search term.
                  </p>
                </div>
              )}

              {/* Not searched yet */}
              {!searched && !loading && (
                <div className="mt-12 text-center text-sm text-muted-foreground">
                  Search for Polymarket events to get started.
                </div>
              )}

              {/* Event grid */}
              {!loading && events.length > 0 && (
                <div className="mt-8 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
                  {events.map((ev) => (
                    <div
                      key={ev.slug}
                      className="rounded-xl border border-border bg-card p-5 transition-all hover:border-primary/20 hover:shadow-[0_0_20px_rgba(245,158,11,0.1)]"
                    >
                      <div className="flex items-start justify-between gap-3">
                        <h3 className="font-semibold leading-snug">{ev.title}</h3>
                        <span
                          className={`shrink-0 rounded-full px-2.5 py-0.5 text-xs font-semibold uppercase tracking-wider ${
                            ev.active
                              ? "bg-success/15 text-success"
                              : "bg-destructive/10 text-destructive"
                          }`}
                        >
                          {ev.active ? "Active" : "Closed"}
                        </span>
                      </div>
                      <div className="mt-4 grid grid-cols-3 gap-3">
                        <div>
                          <div className="text-[10px] uppercase tracking-wider text-muted-foreground">Volume</div>
                          <div className="mt-0.5 text-sm font-bold">{formatVolume(ev.volume)}</div>
                        </div>
                        <div>
                          <div className="text-[10px] uppercase tracking-wider text-muted-foreground">Liquidity</div>
                          <div className="mt-0.5 text-sm font-bold">{formatVolume(ev.liquidity)}</div>
                        </div>
                        <div>
                          <div className="text-[10px] uppercase tracking-wider text-muted-foreground">Markets</div>
                          <div className="mt-0.5 text-sm font-bold">{ev.markets_count}</div>
                        </div>
                      </div>
                      <button
                        onClick={() => navigate(`/investigation?slug=${ev.slug}`)}
                        className="mt-4 flex w-full items-center justify-center gap-2 rounded-xl bg-primary py-2.5 text-sm font-semibold text-primary-foreground transition-all hover:-translate-y-px hover:bg-primary-dark hover:shadow-[0_0_20px_rgba(245,158,11,0.25)]"
                      >
                        Investigate <ArrowRight className="h-3.5 w-3.5" />
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </>
          )}

          {/* ═══ TERMINAL TAB ═══ */}
          {activeTab === "terminal" && <TerminalPanel />}

          {/* ═══ WHALES TAB ═══ */}
          {activeTab === "whales" && <WhalesPanel />}

          {/* ═══ REPORTS TAB ═══ */}
          {activeTab === "reports" && <ReportsPanel />}

          {/* ═══ VAULT TAB ═══ */}
          {activeTab === "vault" && <VaultPanel />}
        </div>
      </div>
    </div>
  );
}

// ── Terminal Panel ──────────────────────────────────────────────

function TerminalPanel() {
  const [logs] = useState<string[]>([
    "[SYSTEM] PolyWatch Investigation Engine V2 initialized",
    "[SYSTEM] Connected to gamma-api.polymarket.com",
    "[SYSTEM] Connected to data-api.polymarket.com",
    "[SYSTEM] Connected to clob.polymarket.com",
    "[SYSTEM] DeepSeek LLM endpoint ready",
    "[SYSTEM] 26 investigation tools loaded",
    "[INFO] Ready. Search a market and click Investigate to begin.",
  ]);

  return (
    <div>
      <h1 className="text-2xl font-bold">Terminal</h1>
      <p className="mt-1 text-sm text-muted-foreground">
        Investigation engine logs and system status.
      </p>
      <div className="mt-6 rounded-xl border border-border bg-[#0a0a0a] p-4 font-mono text-xs leading-relaxed max-h-[600px] overflow-y-auto">
        {logs.map((line, i) => (
          <div key={i} className={line.includes("[ERROR]") ? "text-destructive" : line.includes("[SYSTEM]") ? "text-primary" : "text-muted-foreground"}>
            <span className="text-muted-foreground/50 mr-3 select-none">{String(i + 1).padStart(3, " ")}</span>
            {line}
          </div>
        ))}
        <div className="mt-1 text-success animate-pulse">▌</div>
      </div>
    </div>
  );
}

// ── Whales Panel ───────────────────────────────────────────────

function WhalesPanel() {
  const navigate = useNavigate();

  return (
    <div>
      <h1 className="text-2xl font-bold">Whale Tracker</h1>
      <p className="mt-1 text-sm text-muted-foreground">
        Large trades are detected during investigations. Run an investigation on a market to see whale activity.
      </p>
      <div className="mt-6 rounded-xl border border-border bg-card p-8 text-center">
        <Anchor className="h-10 w-10 text-muted-foreground/30 mx-auto" />
        <p className="mt-3 text-sm text-muted-foreground">
          Whale alerts appear here when you investigate a market. The investigation engine flags trades above $1,000 and coordinated wallet activity.
        </p>
        <button
          onClick={() => navigate("/dashboard?tab=scan")}
          className="mt-4 inline-flex items-center gap-2 rounded-xl bg-primary px-5 py-2.5 text-sm font-semibold text-primary-foreground transition-all hover:-translate-y-px hover:bg-primary-dark"
        >
          Search a market <ArrowRight className="h-3.5 w-3.5" />
        </button>
      </div>
    </div>
  );
}

// ── Reports Panel ──────────────────────────────────────────────

function ReportsPanel() {
  const [reports] = useState<{ slug: string; title: string; date: string; confidence: string }[]>(() => {
    try {
      const stored = localStorage.getItem("polywatch_reports");
      return stored ? JSON.parse(stored) : [];
    } catch {
      return [];
    }
  });

  const navigate = useNavigate();

  return (
    <div>
      <h1 className="text-2xl font-bold">Investigation Reports</h1>
      <p className="mt-1 text-sm text-muted-foreground">
        Completed investigation reports are saved here.
      </p>
      {reports.length === 0 ? (
        <div className="mt-6 rounded-xl border border-border bg-card p-8 text-center">
          <FileText className="h-10 w-10 text-muted-foreground/30 mx-auto" />
          <p className="mt-3 text-sm text-muted-foreground">
            No investigation reports yet. Run an investigation to generate a report.
          </p>
          <button
            onClick={() => navigate("/dashboard")}
            className="mt-4 inline-flex items-center gap-2 rounded-xl bg-primary px-5 py-2.5 text-sm font-semibold text-primary-foreground transition-all hover:-translate-y-px hover:bg-primary-dark"
          >
            Search a market <ArrowRight className="h-3.5 w-3.5" />
          </button>
        </div>
      ) : (
        <div className="mt-6 space-y-3">
          {reports.map((r) => (
            <button
              key={r.slug + r.date}
              onClick={() => navigate(`/investigation?slug=${r.slug}`)}
              className="flex w-full items-center justify-between rounded-xl border border-border bg-card p-4 text-left transition-all hover:border-primary/20"
            >
              <div>
                <div className="font-semibold">{r.title}</div>
                <div className="text-xs text-muted-foreground mt-0.5">{r.date}</div>
              </div>
              <span className={`rounded-full px-2.5 py-0.5 text-xs font-semibold uppercase ${
                r.confidence === "HIGH" ? "bg-success/15 text-success" :
                r.confidence === "MEDIUM" ? "bg-primary/15 text-primary" :
                "bg-muted text-muted-foreground"
              }`}>
                {r.confidence}
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

// ── Vault Panel ────────────────────────────────────────────────

function VaultPanel() {
  const [savedItems] = useState<{ slug: string; title: string; note: string }[]>(() => {
    try {
      const stored = localStorage.getItem("polywatch_vault");
      return stored ? JSON.parse(stored) : [];
    } catch {
      return [];
    }
  });

  const navigate = useNavigate();

  return (
    <div>
      <h1 className="text-2xl font-bold">Evidence Vault</h1>
      <p className="mt-1 text-sm text-muted-foreground">
        Save important evidence and artifacts from investigations.
      </p>
      {savedItems.length === 0 ? (
        <div className="mt-6 rounded-xl border border-border bg-card p-8 text-center">
          <Lock className="h-10 w-10 text-muted-foreground/30 mx-auto" />
          <p className="mt-3 text-sm text-muted-foreground">
            Your evidence vault is empty. Save artifacts during investigations to store them here.
          </p>
          <button
            onClick={() => navigate("/dashboard")}
            className="mt-4 inline-flex items-center gap-2 rounded-xl bg-primary px-5 py-2.5 text-sm font-semibold text-primary-foreground transition-all hover:-translate-y-px hover:bg-primary-dark"
          >
            Start investigating <ArrowRight className="h-3.5 w-3.5" />
          </button>
        </div>
      ) : (
        <div className="mt-6 space-y-3">
          {savedItems.map((item, i) => (
            <div
              key={i}
              className="rounded-xl border border-border bg-card p-4"
            >
              <div className="font-semibold">{item.title}</div>
              <div className="text-xs text-muted-foreground mt-1">{item.note}</div>
              <button
                onClick={() => navigate(`/investigation?slug=${item.slug}`)}
                className="mt-2 text-xs text-primary hover:underline"
              >
                View investigation →
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
