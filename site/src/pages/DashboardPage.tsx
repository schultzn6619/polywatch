import { useState, type FormEvent } from "react";
import { useNavigate } from "react-router-dom";
import {
  Search,
  LogOut,
  Terminal,
  Anchor,
  Radar,
  FileText,
  Lock,
  Settings,
  Bell,
  User,
  ArrowRight,
  AlertTriangle,
  Activity,
  HelpCircle,
} from "lucide-react";

interface PolymarketEvent {
  slug: string;
  title: string;
  active: boolean;
  volume: number;
  liquidity: number;
  markets_count: number;
}

function formatVolume(vol: number): string {
  if (vol >= 1_000_000_000) return `$${(vol / 1_000_000_000).toFixed(1)}B`;
  if (vol >= 1_000_000) return `$${(vol / 1_000_000).toFixed(0)}M`;
  if (vol >= 1_000) return `$${(vol / 1_000).toFixed(0)}K`;
  return `$${vol.toFixed(0)}`;
}

const demoEvents: PolymarketEvent[] = [
  { slug: "presidential-election-2024", title: "2024 Presidential Election", active: true, volume: 3200000000, liquidity: 45000000, markets_count: 12 },
  { slug: "fed-rate-decision-june", title: "Fed Rate Decision", active: true, volume: 180000000, liquidity: 12000000, markets_count: 4 },
  { slug: "bitcoin-100k-2025", title: "Bitcoin to $100K", active: true, volume: 95000000, liquidity: 8000000, markets_count: 2 },
  { slug: "ai-regulation-us-2025", title: "US AI Regulation", active: true, volume: 42000000, liquidity: 3000000, markets_count: 5 },
  { slug: "spacex-starship-success", title: "SpaceX Starship", active: false, volume: 28000000, liquidity: 1000000, markets_count: 3 },
  { slug: "nba-finals-2025", title: "NBA Finals", active: true, volume: 67000000, liquidity: 5000000, markets_count: 8 },
];

const sidebarNav = [
  { icon: Terminal, label: "Terminal", active: false },
  { icon: Anchor, label: "Whales", active: false },
  { icon: Radar, label: "Scan", active: true },
  { icon: FileText, label: "Reports", active: false },
  { icon: Lock, label: "Vault", active: false },
];

export default function DashboardPage() {
  const [query, setQuery] = useState("");
  const [events, setEvents] = useState<PolymarketEvent[]>(demoEvents);
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  function handleLogout() {
    localStorage.removeItem("polywatch_user");
    navigate("/login");
  }

  function handleSearch(e: FormEvent) {
    e.preventDefault();
    if (!query.trim()) {
      setEvents(demoEvents);
      return;
    }
    setLoading(true);
    setTimeout(() => {
      const filtered = demoEvents.filter((ev) =>
        ev.title.toLowerCase().includes(query.toLowerCase())
      );
      setEvents(filtered.length > 0 ? filtered : demoEvents.slice(0, 3));
      setLoading(false);
    }, 400);
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
              className={`flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-sm transition-colors ${
                item.active
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
        {/* Top bar */}
        <div className="flex items-center justify-between border-b border-border bg-surface px-6 py-3">
          <span className="text-sm font-bold tracking-wider uppercase">PolyWatch</span>
          <div className="flex items-center gap-3">
            <button className="p-2 rounded-lg text-muted-foreground hover:text-foreground hover:bg-muted transition-colors">
              <Bell className="h-4 w-4" />
            </button>
            <button className="p-2 rounded-lg text-muted-foreground hover:text-foreground hover:bg-muted transition-colors">
              <Settings className="h-4 w-4" />
            </button>
            <button
              onClick={handleLogout}
              className="inline-flex items-center gap-2 rounded-lg border border-border px-3 py-1.5 text-xs text-muted-foreground hover:border-primary/30 hover:bg-muted transition-colors"
            >
              Sign out
            </button>
            <div className="h-8 w-8 rounded-full bg-primary/20 flex items-center justify-center">
              <User className="h-4 w-4 text-primary" />
            </div>
          </div>
        </div>

        <div className="px-6 py-8 max-w-6xl">
          <h1 className="text-2xl font-bold">Search and explore Polymarket events</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Access deep-chain investigation tools and real-time market data to track insider patterns across high-volume prediction markets.
          </p>

          {/* Search */}
          <form onSubmit={handleSearch} className="mt-6 flex gap-3">
            <div className="relative flex-1">
              <Search className="absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <input
                type="text"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="Search events..."
                className="w-full rounded-xl border border-border bg-background py-2.5 pl-10 pr-4 text-sm text-foreground placeholder:text-muted-foreground outline-none transition-colors focus:border-primary"
              />
            </div>
            <button
              type="submit"
              disabled={loading}
              className="rounded-xl bg-primary px-6 py-2.5 text-sm font-semibold text-primary-foreground transition-all hover:-translate-y-px hover:bg-primary-dark hover:shadow-[0_0_20px_rgba(245,158,11,0.25)] disabled:opacity-40"
            >
              Search
            </button>
          </form>

          {/* Event grid */}
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

          {/* Bottom panels */}
          <div className="mt-8 grid gap-5 lg:grid-cols-2">
            <div className="rounded-xl border border-border bg-card p-6">
              <h3 className="text-lg font-semibold text-primary">Network Liquidity Heatmap</h3>
              <p className="mt-2 text-sm text-muted-foreground">
                Real-time visualization of capital flows across major prediction pairs and cross-exchange arbitrage opportunities.
              </p>
              <a href="#" className="mt-4 inline-flex items-center gap-1 text-sm font-medium text-primary hover:text-primary-dark transition-colors">
                View full analysis <ArrowRight className="h-3.5 w-3.5" />
              </a>
            </div>

            <div className="rounded-xl border border-primary/30 bg-card p-6">
              <div className="flex items-center gap-2 mb-3">
                <AlertTriangle className="h-5 w-5 text-primary" />
                <h3 className="text-lg font-bold text-primary">Whale Alert</h3>
              </div>
              <p className="text-sm text-muted-foreground">
                Multiple $50k+ positions detected on "US AI Regulation" markets within last 5 minutes.
              </p>
              <div className="mt-4 flex items-center gap-4">
                <div>
                  <div className="text-2xl font-bold text-primary">24h Peak</div>
                  <div className="text-xs text-muted-foreground">14.2% Volatility Delta</div>
                </div>
                <Activity className="h-10 w-10 text-success/50 ml-auto" />
              </div>
            </div>
          </div>

          {/* Status bar */}
          <div className="mt-6 flex items-center justify-between text-xs text-muted-foreground border-t border-border pt-4">
            <div className="flex items-center gap-4">
              <span className="flex items-center gap-1">
                <span className="h-1.5 w-1.5 rounded-full bg-success" /> Network Live
              </span>
              <span>Latency: 14ms</span>
            </div>
            <span>&copy; 2024 PolyWatch AI Unit</span>
            <span>SEC Alpha Risk Deployment</span>
          </div>
        </div>
      </div>
    </div>
  );
}
