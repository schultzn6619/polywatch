# Design System: PolyWatch

## 1. Visual Theme & Atmosphere

PolyWatch embodies a **dark, data-driven command center** that channels the intensity of financial surveillance with the sophistication of premium trading terminals. The interface feels **dense yet organized**, prioritizing information hierarchy and real-time data visualization above decorative elements. The design philosophy is intelligence-first, allowing investigation data and market signals to command attention as focal points.

The overall mood is **nocturnal and vigilant**, creating an atmosphere of professional forensic analysis. The interface feels **surgical in precision** but dynamic in execution, with amber/golden-orange accents cutting through the darkness like warning signals on a trading floor. The atmosphere evokes the focused intensity of a Wall Street compliance desk where analysts track suspicious activity in real-time.

**Key Characteristics:**
- Deep black backgrounds creating an immersive, distraction-free environment
- Golden-orange accent system for primary actions and alert states
- Card-based layouts with subtle border illumination on hover
- Data-dense presentation with clear typographic hierarchy
- Smooth micro-interactions with 150-200ms transitions
- Professional, authoritative tone with dark theme throughout

## 2. Color Palette & Roles

### Primary Foundation
- **Void Black** (#090909) – Primary background. An almost pure black that creates depth and immersion for the command center experience.
- **Charcoal Surface** (#111111) – Secondary surface for elevated content areas and sidebars.
- **Dark Card** (#141414) – Card backgrounds providing subtle lift from the base surface.
- **Card Hover** (#1a1a1a) – Interactive hover state for card elements.
- **Muted Dark** (#1e1e1e) – Tertiary surface for ghost buttons and recessed areas.

### Accent & Interactive
- **Golden Amber** (#f59e0b) – The signature accent. Used for primary CTAs, active states, key data highlights, and the brand identity. Represents alertness and financial significance.
- **Deep Amber** (#d97706) – Hover/active state for primary buttons. Darker amber for pressed states.
- **Amber on Dark** (#0c0c0c) – Text color on amber backgrounds ensuring contrast.

### Typography & Text Hierarchy
- **Warm Parchment** (#f5f0e8) – Primary text color. A warm off-white that reduces eye strain during extended investigation sessions.
- **Muted Gray** (#6b6b6b) – Secondary text for labels, metadata, and supporting information.
- **Border Charcoal** (#252525) – Subtle borders and dividers providing structure without visual noise.

### Functional States
- **Alert Red** (#ef4444) – Destructive actions, error states, suspicious activity flags
- **Success Emerald** (#34d399) – Positive indicators, completed investigations, verified data

## 3. Typography Rules

**Primary Font Family:** System UI / -apple-system / sans-serif
**Character:** Clean, utilitarian system fonts optimized for data readability at all sizes.

### Hierarchy & Weights
- **Page Titles (H1):** Bold weight (700), 1.75-2rem size. Used for page headers like "PolyWatch" and major section titles.
- **Section Headers (H2):** Semi-bold weight (600), 1.25-1.5rem size. Card titles, section labels.
- **Body Text:** Regular weight (400), relaxed line-height (1.6), 0.875-1rem size. Investigation content, descriptions.
- **Small Text/Meta:** Regular weight (400), 0.75-0.875rem size. Statistics, timestamps, labels.
- **CTA Buttons:** Medium weight (500), 0.875rem size with slight letter-spacing.

### Spacing Principles
- Compact but breathable spacing suited for data-dense interfaces
- Consistent vertical rhythm with 1-1.5rem between related elements
- 2-3rem between major sections

## 4. Component Stylings

### Buttons
- **Shape:** Rounded corners (12px/0.75rem) – modern and approachable
- **Primary CTA:** Golden Amber (#f59e0b) background with dark text (#0c0c0c), comfortable padding (0.625rem vertical, 1.25rem horizontal)
- **Hover State:** Shifts to Deep Amber (#d97706), subtle lift (-1px translateY), amber glow shadow (0 0 20px rgba(245, 158, 11, 0.25))
- **Ghost Button:** Transparent background with border (#252525), text in Warm Parchment. Hover adds amber border tint.
- **Disabled:** 40% opacity, no pointer events

### Cards
- **Corner Style:** Rounded (12px/0.75rem)
- **Background:** Dark Card (#141414) with 1px border in Border Charcoal (#252525)
- **Shadow:** Subtle dark shadow (0 1px 3px rgba(0,0,0,0.4))
- **Hover:** Border shifts to amber-tinted (rgba(245, 158, 11, 0.2)), amber glow appears (0 0 20px rgba(245, 158, 11, 0.15))
- **Transition:** 200ms ease on border-color and box-shadow

### Inputs & Forms
- **Background:** Charcoal Surface (#111111) with 1px border in Border Charcoal (#252525)
- **Corner Style:** Matching button roundness (12px/0.75rem)
- **Focus State:** Border shifts to Golden Amber (#f59e0b) with amber outer glow
- **Padding:** 0.75rem vertical, 1rem horizontal
- **Placeholder:** Muted Gray (#6b6b6b)

### Navigation
- **Style:** Minimal top bar with page title and action buttons
- **Sign-out:** Ghost button style
- **Search Bar:** Full-width input with adjacent primary CTA button

### Badges & Tags
- **Active Badge:** Green-tinted background (rgba(34, 197, 94, 0.15)) with green text (#22c55e)
- **Closed Badge:** Red-tinted background (rgba(239, 68, 68, 0.1)) with soft red text (#f87171)
- **Corner radius:** 9999px (fully rounded pills)

## 5. Layout Principles

### Grid & Structure
- **Max Content Width:** Centered container with generous padding (1.5-2rem sides)
- **Event Grid:** Responsive grid, 3 columns desktop, 2 tablet, 1 mobile with 1.25rem gap
- **Page Layout:** Full-height flex column with scrollable content area

### Whitespace Strategy
- **Page Padding:** 2rem top, 1.5rem sides
- **Card Internal Padding:** 1.5rem
- **Section Spacing:** 1.5-2rem between major blocks
- **Compact data displays** with 0.5-1rem between related elements

### Responsive Behavior
- Cards stack to single column on mobile
- Search bar and button stack vertically on small screens
- Touch-friendly targets (minimum 44px)

## 6. Design System Notes for Stitch Generation

When creating new screens for this project using Stitch, reference these specific instructions:

**DESIGN SYSTEM (REQUIRED):**
- Platform: Web, Desktop-first
- Theme: Dark, data-driven, command center aesthetic
- Background: Void Black (#090909) as primary, Charcoal Surface (#111111) for elevated areas
- Surface: Dark Card (#141414) for cards with Border Charcoal (#252525) edges
- Primary Accent: Golden Amber (#f59e0b) for buttons, links, highlights, and brand identity
- Accent Hover: Deep Amber (#d97706) with amber glow effect
- Text Primary: Warm Parchment (#f5f0e8) – soft off-white for readability
- Text Secondary: Muted Gray (#6b6b6b) for labels and metadata
- Font: System UI sans-serif, clean and utilitarian
- Buttons: Rounded (12px), amber primary with dark text, ghost secondary with border
- Cards: Rounded (12px), dark background, subtle border, amber glow on hover
- Layout: Centered content, responsive grid, compact but breathable spacing
- No harsh whites, no flat designs – everything has subtle depth and amber energy
