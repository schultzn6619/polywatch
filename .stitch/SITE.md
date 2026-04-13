# Project Vision & Constitution

> **AGENT INSTRUCTION:** Read this file before every iteration. It serves as the project's "Long-Term Memory."

## 1. Core Identity
* **Project Name:** PolyWatch
* **Mission:** AI-driven insider trading investigation platform for Polymarket prediction markets. Uses Tree of Thought reasoning to automatically analyze trading patterns, detect suspicious activity, and generate detailed investigation reports.
* **Target Audience:** Crypto traders, market analysts, compliance professionals, and prediction market enthusiasts investigating suspicious trading activity.
* **Voice:** Professional, authoritative, data-driven. The tone of a forensic analyst presenting evidence — precise yet accessible.

## 2. Visual Language
*Reference these descriptors when prompting Stitch.*

* **The "Vibe" (Adjectives):**
    * *Primary:* Dark command center
    * *Secondary:* Financial surveillance terminal
    * *Tertiary:* Golden amber intelligence dashboard

## 3. Architecture & File Structure
* **Root:** `site/public/`
* **Asset Flow:** Stitch generates to `.stitch/designs/` → Validate → Move to `site/public/`
* **Navigation Strategy:** Top navigation bar with logo and primary page links. Auth-guarded routes.

## 4. Live Sitemap (Current State)
*Update this when a new page is successfully merged.*

* [x] `index.html` - Landing page / hero with product overview and CTA
* [x] `login.html` - Authentication page with sign in / sign up toggle
* [x] `dashboard.html` - Search and browse Polymarket events with volume/liquidity stats
* [x] `investigation.html` - Live investigation UI with tree visualization, artifacts, and reports

## 5. The Roadmap (Backlog)
*Pick the next task from here if available.*

### High Priority
- [x] `index.html` - Landing/marketing page showcasing features
- [x] `login.html` - Authentication with login/signup
- [x] `dashboard.html` - Event search and browsing
- [x] `investigation.html` - Full investigation interface

### Medium Priority
- [ ] `about.html` - About the team and technology behind PolyWatch
- [ ] `pricing.html` - Pricing tiers and feature comparison
- [ ] `docs.html` - Documentation and API reference

### Low Priority
- [ ] `blog.html` - Investigation case studies and market insights
- [ ] `changelog.html` - Product updates and release notes

## 6. Creative Freedom Guidelines
*When the backlog is empty, follow these guidelines to innovate.*

1. **Stay On-Brand:** Dark theme, amber accents, data-focused
2. **Enhance the Core:** Support the investigation and trading analysis mission
3. **Naming Convention:** Use lowercase, descriptive filenames

### Ideas to Explore
- [ ] `stats.html` - Global platform statistics and investigation metrics
- [ ] `alerts.html` - Custom alert configuration for market anomalies
- [ ] `watchlist.html` - Saved markets and investigations dashboard
- [ ] `network.html` - Wallet network visualization explorer

## 7. Rules of Engagement
1. Do not recreate pages in Section 4
2. Always update `next-prompt.md` before completing
3. Consume ideas from Section 6 when you use them
4. Maintain the dark/amber design language across all pages
5. All pages must be responsive and accessible
