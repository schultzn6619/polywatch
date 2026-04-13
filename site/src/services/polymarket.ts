/**
 * Polymarket API client — proxied through Vite dev server to bypass CORS.
 *
 * Endpoints:
 *   /api/gamma  → gamma-api.polymarket.com  (events, markets, search)
 *   /api/clob   → clob.polymarket.com       (price history, orderbook)
 *   /api/data   → data-api.polymarket.com   (trades)
 */

// ── Types ──────────────────────────────────────────────────────

export interface PolymarketEvent {
  slug: string;
  title: string;
  active: boolean;
  closed: boolean;
  volume: number;
  liquidity: number;
  markets_count: number;
  image?: string;
  description?: string;
  endDate?: string;
  markets?: PolymarketMarket[];
}

export interface PolymarketMarket {
  id: string;
  conditionId: string;
  question: string;
  slug: string;
  outcomes: string;
  outcomePrices: string;
  volume: number;
  volume24hr: number;
  liquidity: number;
  active: boolean;
  closed: boolean;
  endDate: string;
  clobTokenIds?: string;
  bestBid?: number;
  bestAsk?: number;
  lastTradePrice?: number;
}

export interface PricePoint {
  t: number;  // unix timestamp
  p: number;  // price 0-1
}

export interface Trade {
  id: string;
  taker_order_id: string;
  market: string;
  asset_id: string;
  side: string;
  size: string;
  fee_rate_bps: string;
  price: string;
  status: string;
  match_time: string;
  last_update: string;
  outcome: string;
  bucket_index: number;
  title: string;
}

// ── Helpers ────────────────────────────────────────────────────

async function get<T>(url: string): Promise<T | null> {
  try {
    const res = await fetch(url);
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}

// ── Search ─────────────────────────────────────────────────────

interface SearchResponse {
  events?: RawEvent[];
  pagination?: { hasMore: boolean; totalResults: number };
}

interface RawEvent {
  id: string;
  slug: string;
  title: string;
  description: string;
  active: boolean;
  closed: boolean;
  volume: number;
  volume24hr: number;
  liquidity: number;
  image: string;
  endDate: string;
  markets?: RawMarket[];
}

interface RawMarket {
  id: string;
  conditionId: string;
  question: string;
  slug: string;
  outcomes: string;
  outcomePrices: string;
  volume: number;
  volume24hr: number;
  liquidity: number;
  active: boolean;
  closed: boolean;
  endDate: string;
  clobTokenIds?: string;
  bestBid?: number;
  bestAsk?: number;
  lastTradePrice?: number;
}

export async function searchEvents(query: string): Promise<PolymarketEvent[]> {
  const data = await get<SearchResponse>(
    `/api/gamma/public-search?q=${encodeURIComponent(query)}&limit_per_type=12`
  );
  if (!data?.events) return [];
  return data.events.map((ev) => ({
    slug: ev.slug,
    title: ev.title,
    active: ev.active,
    closed: ev.closed,
    volume: Number(ev.volume) || 0,
    liquidity: Number(ev.liquidity) || 0,
    markets_count: ev.markets?.length ?? 0,
    image: ev.image,
    description: ev.description,
    endDate: ev.endDate,
    markets: ev.markets?.map(parseMarket),
  }));
}

function parseMarket(m: RawMarket): PolymarketMarket {
  return {
    id: m.id,
    conditionId: m.conditionId,
    question: m.question,
    slug: m.slug,
    outcomes: m.outcomes,
    outcomePrices: m.outcomePrices,
    volume: Number(m.volume) || 0,
    volume24hr: Number(m.volume24hr) || 0,
    liquidity: Number(m.liquidity) || 0,
    active: m.active,
    closed: m.closed,
    endDate: m.endDate,
    clobTokenIds: m.clobTokenIds,
    bestBid: m.bestBid,
    bestAsk: m.bestAsk,
    lastTradePrice: m.lastTradePrice,
  };
}

// ── Event by slug ──────────────────────────────────────────────

export async function getEventBySlug(slug: string): Promise<PolymarketEvent | null> {
  const data = await get<RawEvent[]>(`/api/gamma/events?slug=${encodeURIComponent(slug)}`);
  if (!data || data.length === 0) return null;
  const ev = data[0];
  return {
    slug: ev.slug,
    title: ev.title,
    active: ev.active,
    closed: ev.closed,
    volume: Number(ev.volume) || 0,
    liquidity: Number(ev.liquidity) || 0,
    markets_count: ev.markets?.length ?? 0,
    image: ev.image,
    description: ev.description,
    endDate: ev.endDate,
    markets: ev.markets?.map(parseMarket),
  };
}

// ── Price history ──────────────────────────────────────────────

export async function getPriceHistory(
  tokenId: string,
  fidelity = 60
): Promise<PricePoint[]> {
  const data = await get<{ history: { t: number; p: number }[] }>(
    `/api/clob/prices-history?market=${encodeURIComponent(tokenId)}&interval=all&fidelity=${fidelity}`
  );
  if (!data?.history) return [];
  return data.history;
}

// ── Trades ─────────────────────────────────────────────────────

export async function getTrades(
  conditionId: string,
  limit = 100
): Promise<Trade[]> {
  const data = await get<Trade[]>(
    `/api/data/trades?market=${encodeURIComponent(conditionId)}&limit=${limit}`
  );
  return data ?? [];
}

// ── Large trades (> threshold) ─────────────────────────────────

export async function getLargeTrades(
  conditionId: string,
  minSize = 100,
  limit = 200
): Promise<Trade[]> {
  const all = await getTrades(conditionId, limit);
  return all.filter((t) => parseFloat(t.size) >= minSize);
}
