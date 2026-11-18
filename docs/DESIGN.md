---
name: Hello Buddy Neo-Graphic System
colors:
  surface: '#0F1015'
  surface-dim: '#08080B'
  surface-bright: '#1B1C24'
  surface-container-lowest: '#050508'
  surface-container-low: '#12131A'
  surface-container: '#181922'
  surface-container-high: '#22232E'
  surface-container-highest: '#2D2E3C'
  canvas-light: '#F3F2EE'
  canvas-paper: '#FFFFFF'
  on-surface: '#F3F2EE'
  on-surface-variant: '#9D9CA8'
  primary: '#D2F858'
  on-primary: '#0B0D03'
  primary-container: '#B8DC3D'
  on-primary-container: '#050701'
  secondary: '#7C7B89'
  on-secondary: '#FFFFFF'
  secondary-container: '#2A2A36'
  on-secondary-container: '#D6D5E0'
  tertiary: '#FF5E5B'
  on-tertiary: '#FFFFFF'
  outline: '#262734'
  outline-strong: '#000000'
  outline-light: '#E2E0D8'
  background: '#F3F2EE'
  on-background: '#0F1015'
typography:
  display-lg:
    fontFamily: Cabinet Grotesk
    fontSize: 34px
    fontWeight: '800'
    lineHeight: 40px
    letterSpacing: -0.03em
  display-md:
    fontFamily: Cabinet Grotesk
    fontSize: 26px
    fontWeight: '800'
    lineHeight: 32px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Cabinet Grotesk
    fontSize: 20px
    fontWeight: '700'
    lineHeight: 26px
    letterSpacing: -0.01em
  title-sm:
    fontFamily: Satoshi
    fontSize: 15px
    fontWeight: '700'
    lineHeight: 20px
    letterSpacing: 0.01em
  body-md:
    fontFamily: Satoshi
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 22px
    letterSpacing: 0em
  body-sm:
    fontFamily: Satoshi
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 18px
    letterSpacing: 0.01em
  caption-mono:
    fontFamily: Satoshi
    fontSize: 11px
    fontWeight: '700'
    lineHeight: 14px
    letterSpacing: 0.06em
spacing:
  unit: 4px
  card-padding: 18px
  screen-margin: 16px
  gutter: 12px
---

# Hello Buddy — Neo-Graphic Industrial Companion Design System

## 1. Design Manifesto & Overrides

This design system deliberately overthrows standard AI generative clichés:
- **NO Cliché Orange Buttons / Terracotta**: Replaced by **Acid Celadon Lime (`#D2F858`)**, an electric, razor-sharp high-fashion tech ink paired with pitch black (`#0B0D03`) typography.
- **NO Generic Warm Minimalism**: Replaced by **Stark Liquid Contrast** (Deep Carbon Obsidian `#0F1015` vs Bone White `#F3F2EE`), drawing direct inspiration from graphic Japanese neo-pop, Teenage Engineering interfaces, and high-contrast character-driven illustrated art.
- **NO Cliché Rounded AI Fonts (Inter / Fredoka / Space Grotesk)**: Replaced by **Cabinet Grotesk** (Display, 800/900 weight, sharp editorial geometry) and **Satoshi** (Body, 400/500/700 weight, crisp contemporary Swiss/Dutch grotesque).
- **NO Generic AI Status Tiers (`.online` / Pulsing Green Dot)**: Replaced by functional hardware telemetry: battery percentage badge, active firmware revision, and physical desk orientation.
- **NO Complex Firmware Telemetry in App**: Raw face tracking calculations and centroid angle mathematics belong strictly in ESP32-CAM C++ firmware. The mobile app provides a clean, tactile companion deck: Focus Guard, Friendly Nods, Sleep, and directional pan presets.

## 2. Complete Color Architecture (5 Committed Inks)

1. **Carbon Obsidian (`#0F1015`)**: Deepest pitch chassis ink. Used for fluid dripping headers, liquid silhouettes, cat character silhouette, and dark tactile cards.
2. **Bone White (`#F3F2EE`)**: Smooth matte canvas background. Replaces sterile pure white with an editorial, paper-grade feel.
3. **Solid Pitch (`#000000`)**: Hard 2px structural borders, deep drop shadows (`0 4px 0 #000000`), and primary readable typography on light surfaces.
4. **Acid Celadon Lime (`#D2F858`)**: Sole committed high-priority interactive ink. Used for primary CTAs, active audio waveforms, current date indicator, and focus timer ring.
5. **Muted Smoke (`#7C7B89`)**: Secondary text, inactive track states, and subtle alignment guides.

## 3. Structural Layout & Screen Architecture

### Screen 1: Login & Identity Gate
- Fluid dripping carbon ink canopy drooping from top bezel.
- Stark vector cat companion peeker with massive expressive white eyes and dilated pupils.
- Headline: "HELLO AGAIN" in Cabinet Grotesk 800.
- Clean pill input containers with 2px solid pitch borders.
- Full-width Acid Celadon Lime CTA pill: "ENTER SANCTUARY" with solid black bold typography.
- Secondary black pill button: "CREATE ACCOUNT".
- Firmware bridge indicator: "buddy_bot_01 paired (88% battery)".

### Screen 2: Companion Cockpit & Study Agenda
- Top header: Companion avatar ("Buddy • Level 4"), hardware status, and quick mute toggle.
- Simple Bland Robot Control: 3-way segmented pill (`Focus Guard` | `Friendly` | `Sleep`) + simple Left / Center / Right / Nod buttons.
- Today's Study Agenda: Horizontal date strip with current day highlighted in Acid Celadon, task checklist with bold graphic checkmarks.
- Focus Sprint Timer: High-contrast 25:00 dial with Acid Celadon progress ring and pause/extend buttons.

### Screen 3: Lo-Fi Soundscape & Ambient Music Deck (The Missing Core Feature)
- Dedicated audio companion deck for student focus:
  - Track card: "Lo-Fi Beats for Deep Work #04 • 128 BPM" with scrub bar.
  - Ambient Noise Mixer with vertical faders:
    -  Rain on Glass
    -  Tokyo Study Cafe
    -  Vinyl Crackle
    -  40Hz Gamma Focus Wave
  - Playback routing toggle: Stream through **Desktop Robot Speaker (ESP32 I2S)** vs Phone Audio / Headphones.

### Screen 4: Interactive Study Chatbot & Hardware Bridge
- Context ribbon: Active course code (ECE 402: Digital Signal Processing).
- Conversational bubble feed with illustrated buddy reactions.
- Interactive study quiz cards with instant causal feedback.
- Physical OLED Bridge button: "Push Formula / Note to Robot 1.3-inch OLED".
- Multimodal photo attachment (trigger ESP32-CAM to photograph physical textbook problem).
