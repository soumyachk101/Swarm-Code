# 🎬 Swarm Code — Cinematic Brand Video

A production-grade, fully programmatic cinematic brand video for **Swarm Code** — built entirely with **Remotion** (React for video).

## 🎯 What's in this video

A **84-second cinematic brand film** at 30fps, 1920×1080, structured as 7 cinematic scenes:

| Scene | Frames | Duration | Description |
|---|---|---|---|
| **Cinematic Intro** | 0–270 | 0–9s | Particle field, brand emergence, gradient title reveal |
| **Brand Reveal** | 270–570 | 9–19s | Logo mark with animated gradient, brand tagline, feature tags |
| **Problem Statement** | 570–930 | 19–31s | The pain points modern developers face |
| **Solution Reveal** | 930–1350 | 31–45s | Multi-agent swarm introduction (Hydra, Titan, Apex, Nexus) |
| **Feature Showcase** | 1350–1950 | 45–65s | 6-card bento grid of core capabilities |
| **Stats Impact** | 1950–2250 | 65–75s | Performance metrics in tabular-num display |
| **Closing CTA** | 2250–2520 | 75–84s | Animated concentric ring swarm, brand CTA |

## 🎨 Visual language

- **Palette**: Deep space (#050510) base, cyan (#00e5ff) + violet (#7c3aed) + crimson (#ff2d55) accents
- **Typography**: System-native (-apple-system) for tight macOS alignment
- **Motion**: Custom easing curves (`easeOutExpo`, `easeInOutCubic`) for cinematic feel
- **Effects**: Particle systems, gradient text clips, glassmorphic cards, animated radial glows

## 🚀 Quick start

### Preview in browser (Remotion Studio)

```bash
cd swarm-video
npm start
# Opens http://localhost:3000 with live preview
```

### Render to MP4

```bash
npm run build
# Output: out/swarm-code-cinematic.mp4 (~4K, ~30MB)
```

### Render individual scenes

```bash
npx remotion render src/Root.tsx BrandReveal out/brand-reveal.mp4
npx remotion render src/Root.tsx FeatureShowcase out/features.mp4
```

## 📁 Project structure

```
swarm-video/
├── src/
│   ├── Root.tsx                              # Remotion root registration
│   ├── compositions/
│   │   ├── SwarmCodeCinematic.tsx            # Master composition (84s)
│   │   ├── CinematicIntro.tsx                # Scene 1: Particle intro
│   │   ├── BrandReveal.tsx                   # Scene 2: Logo + brand
│   │   ├── ProblemStatement.tsx              # Scene 3: Pain points
│   │   ├── SolutionReveal.tsx                # Scene 4: Agent swarm
│   │   ├── FeatureShowcase.tsx               # Scene 5: Bento grid
│   │   ├── StatsImpact.tsx                   # Scene 6: Numbers
│   │   └── ClosingCTA.tsx                    # Scene 7: Final CTA
│   └── utils/
│       └── styles.ts                         # Colors, easings, helpers
├── remotion.config.tsx
├── tsconfig.json
└── package.json
```

## ✏️ Customization

### Change colors

Edit `src/utils/styles.ts` → `COLORS` object:

```ts
export const COLORS = {
  bg: "#050510",
  primary: "#00e5ff",   // Change brand primary here
  secondary: "#7c3aed",
  ...
};
```

### Change copy

Each composition has hardcoded copy. Search for the text you want to change:

```bash
grep -rn "Swarm Code" src/compositions/
```

### Change timing

Edit scene durations in `src/Root.tsx`:

```ts
durationInFrames: 2520,  // Total: 84s @ 30fps
```

## 🎬 Advanced: Programmatic rendering

```typescript
import { bundle } from "@remotion/bundler";
import { renderMedia, selectComposition } from "@remotion/renderer";

const bundled = await bundle({ entryPoint: "./src/Root.tsx" });
const composition = await selectComposition({ serveUrl: bundled, id: "SwarmCodeCinematic" });

await renderMedia({
  composition,
  serveUrl: bundled,
  outputLocation: "out/swarm.mp4",
  codec: "h264",
  crf: 18,           // Quality (lower = better, larger file)
  pixelFormat: "yuv420p",
});
```

## 📤 Output specs

- **Codec**: H.264 (default), ProRes, WebM, GIF available
- **Resolution**: 1920×1080 (FHD) — change to 3840×2160 for 4K
- **Frame rate**: 30fps
- **Bitrate**: ~8 Mbps default

## 🔧 Tech stack

- **Remotion 4.x** — React-based video framework
- **React 19** — Component model
- **TypeScript** — Type safety
- **Node.js** — Server-side rendering

---

Built for **Swarm Code** by Soumya Chakraborty · MIT License
