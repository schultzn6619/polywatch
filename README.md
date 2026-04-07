# PolyWatch

An AI-driven insider trading investigation tool for [Polymarket](https://polymarket.com). Uses Tree of Thought reasoning powered by DeepSeek to automatically analyze trading patterns, detect suspicious activity, and generate detailed investigation reports with evidence citations.

## Project Structure

```
polywatch/
├── main.jac                        # Entry point (server + client)
├── index.cl.jac                    # Client router with auth guard
├── jac.toml                        # Project configuration
├── services/
│   ├── investigation_v2.jac        # Tree of Thought investigation engine
│   ├── amar_tools.jac              # 26 investigation tools (market, statistical, news, wallet, network)
│   ├── polymarketApi.jac           # Polymarket API client (Gamma/CLOB/Data)
│   ├── polymarketService.jac       # Service wrapper for Polymarket API
│   ├── newsApi.jac                 # webz.io news API client
│   ├── newsService.jac             # News search service
│   ├── api.jac                     # Shared API utilities
│   └── appService.jac              # Demo service
├── pages/
│   ├── LoginPage.cl.jac            # Login / signup page
│   ├── DashboardPage.cl.jac        # Search & browse Polymarket events
│   └── InvestigationPage.cl.jac    # Live investigation UI with tree visualization
├── components/
│   ├── GreetCard.cl.jac            # Demo component
│   ├── InvestigationLog.cl.jac     # Investigation trace log display
│   └── InvestigationTree.cl.jac    # Tree visualization component
├── hooks/                          # Shared state and API logic
└── styles/
    └── global.css                  # Dark theme with Tailwind + custom CSS variables
```

## Getting Started

```bash
jac start main.jac
```

Then open your browser to the URL shown in the terminal.

### Environment Variables

- `DEEPSEEK_API_KEY` — required for the LLM-powered investigation engine
- `WEBZ_TOKEN` — optional, enables news correlation analysis via webz.io

## Features

- **Polymarket Event Search** — search and browse prediction market events by keyword
- **AI-Powered Investigations** — Tree of Thought algorithm recursively explores trading anomalies, news correlations, and wallet behavior
- **26 Investigation Tools** across five categories:
  - **Market Analysis** — trades, price history, large trades, market movers
  - **Statistical Anomaly** — abnormal volume, price run-ups, trade timing, synchronized traders
  - **News Correlation** — pre-news trading, sentiment analysis, event timelines
  - **Wallet Profiling** — trade history, PnL, win rates, first activity
  - **Network Analysis** — linked wallets, trader networks, fund flows
- **Real-Time Investigation UI** — live tree visualization, streaming artifacts, and tool call tracking
- **Evidence-Based Reports** — final reports with clickable citation references to collected evidence
- **User Authentication** — sign up and log in with username/password, protected routes via `AuthGuard`
- **Dark Theme** — black and golden orange design

## How It Works

1. **Search** for a Polymarket event on the dashboard
2. **Start an investigation** with an optional goal (e.g., "look for insider trading")
3. The backend spawns a background investigation thread that:
   - Fetches market data, trades, and price history as a baseline
   - Uses the LLM to plan which tools to call next (recursive DFS)
   - Executes tools and stores results as numbered artifacts
   - Evaluates whether to explore deeper or backtrack to new hypotheses
   - Continues until depth/breadth limits are reached or the goal is satisfied
4. The frontend **polls for progress** every 2 seconds, showing:
   - Live investigation tree with node status
   - Evidence artifacts as they arrive
   - Tool call log with category breakdown
5. A **final report** is generated with structured sections (executive summary, key findings, evidence analysis, limitations, next steps) and `[A1]`, `[A2]` citations linking back to collected evidence

## Architecture

- **`services/investigation_v2.jac`** — core Tree of Thought engine (max depth 6, max 30 tool calls, minimum 3 categories before closing)
- **`services/amar_tools.jac`** — tool registry with 26 investigation functions
- **`services/polymarketApi.jac`** — Polymarket Gamma/CLOB/Data API client (rate-limited)
- **`services/newsApi.jac`** / **`newsService.jac`** — webz.io news search and correlation
- **`pages/*.cl.jac`** — full-page React components, one per route
- **`components/*.cl.jac`** — reusable UI pieces (tree visualization, investigation log)
- **`hooks/*.cl.jac`** — shared state and API logic consumed by components
- **`styles/global.css`** — design tokens (`--primary`, `--background`, etc.) and utility classes
- **`main.jac`** — registers server symbols and mounts the client app

## Tech Stack

- **Jac** — full-stack language for both backend and frontend
- **React 18** with React Router and React Hook Form
- **Tailwind CSS** with custom dark theme
- **DeepSeek LLM** via the byLLM plugin
- **Polymarket APIs** — Gamma, CLOB, and Data endpoints
- **webz.io** — news search and sentiment analysis
