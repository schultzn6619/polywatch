export const features = [
  {
    icon: "Brain",
    title: "Tree of Thought AI",
    description:
      "Recursive DFS-based reasoning engine that explores multiple investigation hypotheses simultaneously, backtracking and refining until evidence is conclusive.",
  },
  {
    icon: "Wrench",
    title: "26 Investigation Tools",
    description:
      "Market analysis, statistical anomaly detection, news correlation, wallet profiling, and network analysis — all automated and orchestrated by AI.",
  },
  {
    icon: "Activity",
    title: "Real-Time Analysis",
    description:
      "Live investigation UI with streaming artifacts, tree visualization, and tool call tracking as the AI works through its analysis.",
  },
  {
    icon: "Shield",
    title: "Evidence-Based Reports",
    description:
      "Structured final reports with executive summaries, key findings, evidence citations ([A1], [A2]), limitations, and recommended next steps.",
  },
  {
    icon: "Search",
    title: "Polymarket Integration",
    description:
      "Direct connection to Gamma, CLOB, and Data APIs for comprehensive market data — trades, price history, liquidity, and volume.",
  },
  {
    icon: "Network",
    title: "Network Analysis",
    description:
      "Trace wallet connections, fund flows, and synchronized trading patterns to uncover coordinated market manipulation.",
  },
] as const;

export const steps = [
  {
    number: "01",
    title: "Search",
    description: "Find a Polymarket event by keyword — elections, crypto, sports, or any prediction market.",
  },
  {
    number: "02",
    title: "Investigate",
    description: "Set an investigation goal and let the AI engine recursively analyze trading patterns and anomalies.",
  },
  {
    number: "03",
    title: "Analyze",
    description: "Watch in real-time as the AI explores hypotheses, calls tools, and collects evidence artifacts.",
  },
  {
    number: "04",
    title: "Report",
    description: "Receive a structured investigation report with findings, evidence citations, and next steps.",
  },
] as const;

export const toolCategories = [
  { name: "Market Analysis", count: 6, examples: ["Trade history", "Price movements", "Large trades", "Market movers"] },
  { name: "Statistical Anomaly", count: 6, examples: ["Abnormal volume", "Price run-ups", "Trade timing", "Synchronized traders"] },
  { name: "News Correlation", count: 5, examples: ["Pre-news trading", "Sentiment analysis", "Event timelines"] },
  { name: "Wallet Profiling", count: 5, examples: ["Trade history", "PnL analysis", "Win rates", "First activity"] },
  { name: "Network Analysis", count: 4, examples: ["Linked wallets", "Trader networks", "Fund flows"] },
] as const;

export const stats = [
  { label: "Investigation Tools", value: "26" },
  { label: "Tool Categories", value: "5" },
  { label: "Max Tree Depth", value: "6" },
  { label: "Min Categories", value: "3" },
] as const;

export const navLinks = [
  { label: "Features", href: "#features" },
  { label: "How It Works", href: "#how-it-works" },
  { label: "Tools", href: "#tools" },
] as const;

export const footerLinks = {
  product: [
    { label: "Features", href: "#features" },
    { label: "How It Works", href: "#how-it-works" },
    { label: "Tools", href: "#tools" },
    { label: "Dashboard", href: "/dashboard" },
  ],
  resources: [
    { label: "Documentation", href: "#" },
    { label: "API Reference", href: "#" },
    { label: "Case Studies", href: "#" },
    { label: "Blog", href: "#" },
  ],
  legal: [
    { label: "Privacy Policy", href: "#" },
    { label: "Terms of Service", href: "#" },
    { label: "Disclaimer", href: "#" },
  ],
} as const;
