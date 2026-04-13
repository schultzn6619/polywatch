import { useState, type FormEvent } from "react";
import { useNavigate } from "react-router-dom";
import { Search, LogOut, ArrowRight } from "lucide-react";

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

export default function DashboardPage() {
  const [query, setQuery] = useState("");
  const [events, setEvents] = useState<PolymarketEvent[]>(demoEvents);
  const [loading, setLoading] = useState(false);
  const [searched, setSearched] = useState(false);
  const navigate = useNavigate();

  function handleLogout() {
    localStorage.removeItem("polywatch_user");
    navigate("/login");
  }

  function handleSearch(e: FormEvent) {
    e.preventDefault();
    const q = query.trim();
    if (!q) {
      setEvents(demoEvents);
      setSearched(false);
      return;
    }
    setLoading(true);
    setSearched(true);
    setTimeout(() => {
      const filtered = demoEvents.filter((ev) =>
        ev.title.toLowerCase().includes(q.toLowerCase())
      );
      setEvents(filtered);
      setLoading(false);
    }, 400);
  }

  function handleInvestigateCustom() {
    const slug = query.trim().toLowerCase().replace(/\s+/g, "-");
    if (slug) {
      navigate(`/investigation?slug=${encodeURIComponent(slug)}`);
    }
  }

  return (
    <div className="min-h-screen pt-16">
      <div className="px-6 py-8 max-w-6xl mx-auto">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold">Search and explore Polymarket events</h1>
            <p className="mt-1 text-sm text-muted-foreground">
              Investigate prediction markets with AI-powered chain analysis.
            </p>
          </div>
          <button
            onClick={handleLogout}
            className="inline-flex items-center gap-2 rounded-xl border border-border px-4 py-2 text-sm text-muted-foreground hover:text-foreground hover:border-primary/30 transition-colors"
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
              placeholder="Search events or enter a market slug..."
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

        {/* Loading */}
        {loading && (
          <div className="mt-8 text-center text-sm text-muted-foreground">Searching...</div>
        )}

        {/* No results — offer direct investigation */}
        {!loading && searched && events.length === 0 && (
          <div className="mt-8 text-center">
            <p className="text-sm text-muted-foreground">
              No matching events found for "<span className="text-foreground font-medium">{query}</span>".
            </p>
            <button
              onClick={handleInvestigateCustom}
              className="mt-3 inline-flex items-center gap-2 rounded-xl bg-primary px-5 py-2.5 text-sm font-semibold text-primary-foreground transition-all hover:-translate-y-px hover:bg-primary-dark hover:shadow-[0_0_20px_rgba(245,158,11,0.25)]"
            >
              Investigate "{query}" directly <ArrowRight className="h-3.5 w-3.5" />
            </button>
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
      </div>
    </div>
  );
}
