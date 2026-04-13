import { useState, type FormEvent } from "react";
import { useNavigate } from "react-router-dom";
import { Search, TrendingUp, Droplets, BarChart3, LogOut } from "lucide-react";

interface PolymarketEvent {
  slug: string;
  title: string;
  active: boolean;
  volume: number;
  liquidity: number;
  markets_count: number;
}

function formatVolume(vol: number): string {
  if (vol >= 1_000_000) return `$${(vol / 1_000_000).toFixed(1)}M`;
  if (vol >= 1_000) return `$${(vol / 1_000).toFixed(1)}K`;
  return `$${vol.toFixed(0)}`;
}

// Demo data for the static site
const demoEvents: PolymarketEvent[] = [
  { slug: "presidential-election-2024", title: "Presidential Election Winner 2024", active: true, volume: 3200000000, liquidity: 45000000, markets_count: 12 },
  { slug: "fed-rate-decision-june", title: "Fed Rate Decision — June Meeting", active: true, volume: 180000000, liquidity: 8500000, markets_count: 3 },
  { slug: "bitcoin-100k-2025", title: "Bitcoin to reach $100K in 2025?", active: true, volume: 95000000, liquidity: 4200000, markets_count: 1 },
  { slug: "ai-regulation-us-2025", title: "US AI Regulation Bill Passed in 2025?", active: true, volume: 42000000, liquidity: 1800000, markets_count: 2 },
  { slug: "spacex-starship-success", title: "SpaceX Starship Successful Orbital Flight", active: false, volume: 28000000, liquidity: 0, markets_count: 1 },
  { slug: "nba-finals-2025", title: "NBA Finals 2025 Winner", active: true, volume: 67000000, liquidity: 3100000, markets_count: 8 },
];

export default function DashboardPage() {
  const [query, setQuery] = useState("");
  const [events, setEvents] = useState<PolymarketEvent[]>([]);
  const [loading, setLoading] = useState(false);
  const [searched, setSearched] = useState(false);
  const navigate = useNavigate();

  function handleLogout() {
    localStorage.removeItem("polywatch_user");
    navigate("/login");
  }

  function handleSearch(e: FormEvent) {
    e.preventDefault();
    if (!query.trim()) return;
    setLoading(true);
    setSearched(true);

    // Simulate search with demo data
    setTimeout(() => {
      const filtered = demoEvents.filter((ev) =>
        ev.title.toLowerCase().includes(query.toLowerCase())
      );
      setEvents(filtered.length > 0 ? filtered : demoEvents.slice(0, 3));
      setLoading(false);
    }, 800);
  }

  return (
    <div className="min-h-screen pt-16">
      <div className="mx-auto max-w-6xl px-6 py-8">
        {/* Header */}
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold">PolyWatch</h1>
            <p className="text-sm text-muted-foreground">
              Search and explore Polymarket events
            </p>
          </div>
          <button
            onClick={handleLogout}
            className="inline-flex items-center gap-2 rounded-xl border border-border px-4 py-2 text-sm text-foreground transition-colors hover:border-primary/30 hover:bg-muted"
          >
            <LogOut className="h-4 w-4" /> Sign out
          </button>
        </div>

        {/* Search */}
        <form onSubmit={handleSearch} className="mt-8 flex gap-3">
          <div className="relative flex-1">
            <Search className="absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
            <input
              type="text"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search events... (e.g. election, bitcoin, fed)"
              className="w-full rounded-xl border border-border bg-surface py-2.5 pl-10 pr-4 text-sm text-foreground placeholder:text-muted-foreground outline-none transition-colors focus:border-primary"
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

        {/* Results */}
        <div className="mt-8">
          {loading && (
            <p className="text-center text-sm text-muted-foreground">
              Searching Polymarket...
            </p>
          )}

          {!loading && searched && events.length === 0 && (
            <p className="text-center text-sm text-muted-foreground">
              No events found. Try a different search term.
            </p>
          )}

          {events.length > 0 && (
            <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
              {events.map((ev) => (
                <div
                  key={ev.slug}
                  className="rounded-xl border border-border bg-card p-5 transition-all hover:border-primary/20 hover:shadow-[0_0_20px_rgba(245,158,11,0.1)]"
                >
                  <div className="flex items-start justify-between gap-3">
                    <h3 className="font-semibold leading-snug">{ev.title}</h3>
                    <span
                      className={`shrink-0 rounded-full px-2.5 py-0.5 text-xs font-medium ${
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
                      <div className="flex items-center gap-1 text-xs text-muted-foreground">
                        <TrendingUp className="h-3 w-3" /> Volume
                      </div>
                      <div className="mt-0.5 text-sm font-semibold">
                        {formatVolume(ev.volume)}
                      </div>
                    </div>
                    <div>
                      <div className="flex items-center gap-1 text-xs text-muted-foreground">
                        <Droplets className="h-3 w-3" /> Liquidity
                      </div>
                      <div className="mt-0.5 text-sm font-semibold">
                        {formatVolume(ev.liquidity)}
                      </div>
                    </div>
                    <div>
                      <div className="flex items-center gap-1 text-xs text-muted-foreground">
                        <BarChart3 className="h-3 w-3" /> Markets
                      </div>
                      <div className="mt-0.5 text-sm font-semibold">
                        {ev.markets_count}
                      </div>
                    </div>
                  </div>
                  <button
                    onClick={() =>
                      navigate(`/investigation?slug=${ev.slug}`)
                    }
                    className="mt-4 w-full rounded-xl bg-primary py-2 text-sm font-semibold text-primary-foreground transition-all hover:-translate-y-px hover:bg-primary-dark hover:shadow-[0_0_20px_rgba(245,158,11,0.25)]"
                  >
                    Investigate
                  </button>
                </div>
              ))}
            </div>
          )}

          {!searched && (
            <p className="text-center text-sm text-muted-foreground">
              Search for Polymarket events to get started.
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
