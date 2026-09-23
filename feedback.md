# Swarm-Code Deep-Dive Feedback

**Prepared by:** Claude (Hydra lead, read-only audit)
**Date:** 2026-09
**Scope:** `/Users/soumyachakraborty/Documents/Swarm-Code`
**Rule observed:** No code changes were made to any `@SwarmCode/` file during this analysis.

This document collects every finding from a parallel three-head audit (upstream diff, code quality, build health) plus an automated security review. Recommendations are advisory; nothing here is implemented.

---

## 1. Executive Summary

| Area | Status |
|---|---|
| Upstream `droppycode` repo | ~30 new commits since our HEAD (Sep 19–22). One MR (`!386`) was a full revert of a 63-file design refresh. |
| Build / config health | Clean. No structural misconfigurations in xcodegen project, pnpm workspace, or tsconfig. |
| Open high-severity bugs | **1 SSRF** in `MarkdownView.swift` (security review). **1 launch-crash risk** in `RootView.swift:157` (`CGEventType(rawValue: ~0)!`). |
| Code quality | Mid-severity in the settings refactor (duplicate About panel, unused import, cross-layer icon import). No 4-layer architecture violations. |
| Untracked panel refactor | In flight: 4 new panels + 4 new routes sit beside a still-large `SettingsPanels.tsx`. Dead/duplicate code present. |
| Sync risk with upstream | **High** for Hydra core model (`HydraCookbook.swift`, `HydraDelegationStream.swift`) and `ProviderRegistry.swift`. |

---

## 2. droppycode Upstream — What New Push Aaya Hai

Remote `droppy-upstream` (gitlab.com/droppyformac1/droppy-code) advanced from `dd2b86efe` to `1fbf81e61` since our HEAD `d868079d3`. Highlights (oldest → newest):

| When | Commit / MR | What |
|---|---|---|
| Sep 19 | Hydra popover polish; squash GitLab merges | UI nips. |
| Sep 20 | `Fix main build regressions`; `refactor: share the trim...` | Cleanup. |
| Sep 21 | `feat(providers): split OpenCode Zen and OpenCode Go` | `ProviderRegistry.swift` +82/-5; `Provider.swift` model updated; `PlanLimits.swift` updated. **Sync priority: HIGH.** |
| Sep 21 | `fix: Stop passing Claude's --allowed-mcp-server-names to Antigravity` | One-line argv fix in `AntigravitySession.start()` that was killing every Antigravity session 0.2 s after launch when any MCP server connected. **Worth backporting.** |
| Sep 21 | `Design: Jev typed judgments for Hydra dispatch and merge decisions` (docs only) | Design doc, no code. |
| Sep 21 | `Hydra: a held-back delegation block must never be silent` | **Core model change:** `hydraDelegationRounds` + `hydraRefusedBlocks` counters → single `HydraDelegationBudget` value type in `Core/Models/Hydra.swift`. Held-back blocks now reach lead via `[Hydra]` prefix. **Sync priority: HIGH.** |
| Sep 21 | `feat/collapsible-settings-sections` (MR !376) | New `ChromeRevealLayout` (Animatable Layout) + `ChromeQuietButtonStyle` in `Chrome.swift`. Provider/Models settings pages gained expand/collapse. **Kept after revert — adopt.** |
| Sep 21 | `feat/appearance-and-legibility` (MR !380) | 46 files, net +4/-1204: new `ZoomLayout.swift`, `AppearanceSettings.swift`, `TerminalFontResolver.swift`. Per-conversation zoom removed → window-level zoom via `⌘=`/`⌘-`/`⌘0`. All 378 `.system(size:)` → `Font.TextStyle`. `.secondary`/`.tertiary` → `Chrome.secondaryText` (70% opacity). |
| Sep 21 | `fix(timeline): anchor the lazy window and clear the warning set` (MR !381) | **Critical bug fix:** lazy timeline used fixed-length suffix, evicting oldest loaded row when new blocks arrived. Now anchored on `windowStartID`. Side-fixes: 21 → 0 compiler warnings; favicons from `https://<host>/favicon.ico` (privacy: no third-party); photos >2000 px downscaled off main actor; `/compact` unified on `ProviderKind.supportsCompact`; `chronologicalTimeline` setting restored. **Sync priority: HIGH; Swarm-Code has local `Core/Models/Timeline.swift`, so conflict expected.** |
| Sep 21 | `feat: refresh regular Droppy UI and add Jev judgment heads` (MR !382) | 63 files, +515/-150 in `HydraRunMetricsView.swift` alone. JevSettingsPage added. **REVERTED next day.** |
| Sep 21 | `refactor: finish native macOS design audit` (MR !384) | 16 files. Native AppKit surfaces replacing custom glass chrome: `GroupBox`, `NavigationSplitView`, `.bordered`/`.segmented`/`.menu`, `ControlGroup`. Liquid Glass reserved for composer / floating panels / Hydra circular controls / command palette / minimap. **`ChromeSegmentedPicker.swift` lost 56 lines (native replacement). `ChromeVisualPicker.swift` lost 99 lines (native replacement).** |
| Sep 21 | `refactor: align DroppyCode with native Droppy design language` (MR !385) | 21 files. |
| Sep 22 | `Revert recent design refresh and remove Jev` (MR !386) | 63 files reverted; Jev deleted. |
| Sep 22 | `Fix build after design rollback` | Repair compile breakage from the revert. |

### 2.1 Patterns that survived the design revert (worth adopting in Swarm-Code)

- `ChromeRevealLayout` — Animatable Layout for collapsible settings sections.
- `ChromeQuietButtonStyle` — ButtonStyle without pressed-state feedback.
- `Font.TextStyle` migration (semantic text styles project-wide).
- `Chrome.secondaryText` (replaces `.secondary` / `.tertiary` foreground).
- Window-level zoom (`ZoomLayout`).
- `TerminalFontResolver` (Ghostty / iTerm2 / Terminal.app Nerd Font fallback chain).
- `ISO8601.swift` shared helper in `Core/Support/`.
- State machines as small value types (`HydraDelegationBudget`).
- Native AppKit surfaces in place of custom glass chrome.

### 2.2 Breaking changes that will bite Swarm-Code on next sync

1. `HydraDelegationBudget` replaces `hydraDelegationRounds` / `hydraRefusedBlocks`. Any code referencing the old counter names will fail to compile.
2. Per-conversation `.environment(\.chatZoom)` removed.
3. `chronologicalTimeline` setting is back; Swarm-Code `Core/Models/Timeline.swift` may have removed it.
4. `HydraRunMetricsView.swift` deleted then re-added (already drifted upstream).
5. `ChromeSegmentedPicker` / `ChromeVisualPicker` heavily slimmed — Swarm-Code copies likely diverged.
6. `ProviderKind.supportsCompact` is now the single source for `/compact`.

### 2.3 Conflict map (local modified / upstream touched)

| Local file | Upstream MR | Risk |
|---|---|---|
| `SwarmCode/Core/Models/HydraCookbook.swift` | !375 (delegation budget) | **HIGH** |
| `SwarmCode/Core/Models/HydraDelegationStream.swift` | !375 | **HIGH** |
| `SwarmCode/Core/Models/Timeline.swift` | !381 (`chronologicalTimeline`) | **HIGH** |
| `SwarmCode/Core/Models/Provider.swift` | !379 (OpenCode split) | MEDIUM |
| `SwarmCode/Services/Providers/ProviderRegistry.swift` | !379 (+82/-5) | **HIGH** |
| `SwarmCode/App/Views/Chat/HydraProgressBar.swift` | !382 (+515/-150) | **HIGH** |
| `SwarmCode/App/Views/Chat/TimelineRows.swift` | !381, !382, !384 | MEDIUM |
| `SwarmCode/App/Views/Chat/HydraRunMetricsView.swift` | !382 (deleted then re-added) | LOW |
| `SwarmCode/App/Views/Chat/HydraMergePopover.swift` | !384 (42 lines) | MEDIUM |
| `SwarmCode/App/Views/Settings/ModelsSettingsPage.swift` | !376 (+87/-9), !382, !385 | MEDIUM |
| `SwarmCode/UI/Chrome/ChromeSegmentedPicker.swift` | !384 (+4/-56) | **HIGH** |
| `SwarmCode/UI/Chrome/ChromeVisualPicker.swift` | !384 (+5/-99) | **HIGH** |

Note: upstream's directory root is `DroppyCode/`, ours is `SwarmCode/` — file-level merges need path mapping.

---

## 3. Code Quality & Bug Audit (within current HEAD)

### 3.1 Security — HIGH

| # | File | Lines | Severity | Issue |
|---|---|---|---|---|
| S1 | `SwarmCode/UI/Markdown/MarkdownView.swift` | favicon loader | **HIGH** | **SSRF.** Fetches `https://<host>/favicon.ico` directly from user-controlled host string with `URLSession.shared`, no DNS pinning, no IP allowlist, no redirect guard. A hostile host in chat can probe loopback / RFC1918 / 169.254.0.0/16 — internal services are common SSRF targets. |

**Suggested remediation** (one of):
- (a) Keep a third-party favicon service path.
- (b) Resolve `host` via `getaddrinfo`, reject any resolved address that is loopback / 169.254.0.0/16 / RFC1918 / link-local, then use a `URLSession` with a delegate that applies the same public-IP check after every redirect.
- (c) Route the fetch through an allowlisted backend proxy that validates server-side.

This was flagged by the automated security review. Surface it to the user before/with the fix; it is a real risk.

### 3.2 Swift bugs — HIGH / MEDIUM

| # | File:Line | Severity | Issue |
|---|---|---|---|
| B1 | `SwarmCode/App/Views/RootView.swift:157` | **HIGH (launch crash)** | `private static let anyInput = CGEventType(rawValue: ~0)!` — `~0` is `UInt32.max`, not a valid `CGEventType` case. If this code path is exercised at launch the app will trap immediately. Needs verification + a correct value or a different masking approach. |
| B2 | `SwarmCode/App/HydraCookbook+Resolve.swift:58` | MEDIUM | Double force-unwrap `options.firstIndex(...)! > options.firstIndex(...)!`. Defended upstream by the `matches` filter but has no defensive check of its own. Replace with `guard let l = options.firstIndex(...), let r = options.firstIndex(...) else { ... }`. |
| B3 | `SwarmCode/App/Runtime/ThreadRuntime.swift:820` | LOW | Redundant `remove(at:)!` after a guarded nil check on line 817. Cosmetic — convert early-return / force-unwrap into a `guard let`. |
| B4 | `SwarmCode/Services/Providers/ProviderRegistry.swift:557-564` | LOW | Watchdog + main task both call `loadingLimits.remove(provider)` and `drainedForcedRead(provider)`. Safe today because the class is `@MainActor`, but the double-revoke pattern is easy to mis-edit. |

**Cleared:**
- No retain cycles found in `@Observable` Services (`ProviderRegistry`, `MCPStore`, `TokenLedger`).
- All `@Observable` Services are `@MainActor`-isolated; mutations are serialized.
- No 4-layer architecture violations (`Core` reaches into nothing else; `Services` / `UI` reach only into `Core`; `App` reaches into everything).
- Hardcoded `static let` URL force-unwraps across `Provider.swift`, `UpdateChecker.swift`, `DeepSeekAPI.swift`, `ZaiAPI.swift`, `MetaAPI.swift`, `PlanLimits.swift`, `CommandCodeAPI.swift`, `PiPlanLimits.swift` are compile-time-acceptable but would be better with `precondition` for diagnostics.

### 3.3 React / TypeScript quality

| # | File:Line | Severity | Issue |
|---|---|---|---|
| W1 | `desktop/apps/web/src/components/settings/SettingsPanels.tsx:264-271, 3195-3203` | MEDIUM | `AboutVersionTitle` / `AboutVersionSection` are inlined here **and** exist in the new `AboutSettingsPanel.tsx`. Two implementations. Either delete the inline versions or remove the new file. |
| W2 | `desktop/apps/web/src/components/settings/SourceControlSettings.tsx:6` | MEDIUM | `import { MCPSettingsPanel }` is **unused** in this file. Remove the import. |
| W3 | `desktop/apps/web/src/components/settings/SettingsSidebarNav.tsx:35` | MEDIUM | `import { HydraMarkSvg } from "./HydraSettingsPanel"` — sidebar (nav) depends on a panel implementation detail. Move `HydraMarkSvg` to a shared icons module (e.g. `pierre-icons.ts` or a new `settings/icons.ts`). |
| W4 | `desktop/apps/web/src/components/settings/SourceControlSettings.tsx:110-131` | LOW | `backgroundActivityOverrideSettings` is duplicated against the copy imported in `SettingsPanels.tsx`. Consolidate into one shared helper. |
| W5 | `desktop/apps/web/src/components/settings/SettingsPanels.tsx` (whole file) | LOW | 3200+ lines, mid-refactor. New panel files are showing the intended split; finish the move. |
| W6 | `desktop/apps/web/src/components/settings/SettingsPanels.tsx:912-925` | LOW | String-literal comparisons (`value === "balanced"`) instead of a typed enum. |
| W7 | `desktop/apps/web/src/components/settings/SettingsSidebarNav.tsx:188-198` | LOW | `data-slot$="popup"` is too broad; risks matching unintended elements for the global keydown trap. |
| W8 | `desktop/apps/web/src/themePalette.ts:24` | LOW (debt) | `SWARM_CODE_CHAT_THEME as T3_CHAT_THEME` — legacy alias from the T3 fork. Plan a removal. |
| W9 | `desktop/apps/web/src/themePalette.ts:34` | LOW (debt) | `CUSTOM_THEMES_STORAGE_KEY = "t3code:themes:v1"` — legacy `t3code:` prefix. |
| W10 | `desktop/apps/web/src/canonicalThemes.ts` | LOW | No runtime validation of hex colour strings. Add a regex check or use a typed colour utility. |

### 3.4 Untracked files — review notes

| File | Notes |
|---|---|
| `AboutSettingsPanel.tsx` | Clean split. |
| `HydraSettingsPanel.tsx` | Clean, except it leaks `HydraMarkSvg` into the sidebar (see W3). |
| `MCPIcons.tsx` | Good — dedicated icon module for MCP settings. |
| `MCPSettingsPanel.tsx`, `ModelsSettingsPanel.tsx`, `TokenActivityHeatmap.tsx` | Clean structure, no issues. |
| `canonicalThemes.ts` | Clean schema; needs colour-string validation (W10). |
| `routes/settings.about.tsx`, `settings.hydra.tsx`, `settings.mcp.tsx`, `settings.models.tsx` | All follow the same `createFileRoute` pattern. Clean. |

---

## 4. Build & Project Health

| Area | Result |
|---|---|
| Swift native app (xcodegen → pbxproj) | Consistent. macOS 26.0, arm64 only, Swift 6.0 with `SWIFT_APPROACHABLE_CONCURRENCY = YES`, single SPM dep (SwiftTerm 1.20.0), hardened runtime, marketing 1.8.0 build 29. |
| pnpm workspace | Catalog-managed versions, patched deps (`@effect/vitest`, `@ff-labs/fff-node`, `@legendapp/list`, `@pierre/diffs`, `dbus-next`, `effect`), `allowBuilds` + overrides stripping platform-specific binaries from `@anthropic-ai/claude-agent-sdk`. Node ^24.13.1, pnpm 11.10.0. |
| Workspace packages | `@swarmcode/monorepo`, `@swarmcode/desktop` (Electron 44.4.2), `@swarmcode/web` (React 19.2.6), `swarmcode` (server), `@swarmcode/contracts`, plus private `@swarmcode/shared`, `@swarmcode/client-runtime`, `@swarmcode/ssh`, `@swarmcode/tailscale`, `effect-acp`, `effect-codex-app-server`. |
| tsconfig.base.json | ESNext + NodeNext + strict + `noUncheckedIndexedAccess` + `exactOptionalPropertyTraits` + `noImplicitOverride` + `erasableSyntaxOnly` + `verbatimModuleSyntax` + `@effect/language-service` plugin. No structural issues. |
| TypeScript versions | TS 7.0.2 (early), Effect 4.0.0-rc.115, React 19.2.6, Electron 44.4.2, Vite via `@voidzero-dev/vite-plus-core@0.3.0`. |
| Test target | None, per AGENTS.md — build is the check. |
| TODO / FIXME debt | Very low in Swift (only the "omit speculative TODOs" guidance string itself). One server-side `// TODO: Verify packages/effect-codex-app-server/scripts/generate.ts`. |
| Open audit items | `docs/audit-2026-09-15.md`: P0/P1s resolved, P2s remain (K1 = 21 compiler warnings, K3 = provider compact support, H7/H8/H9 = Hydra panel / report polish, D6 = text size scaling). `docs/performance-2026-09-15.md` lists performance items still "not done". |
| Minor cosmetic debt | `apps/server/package.json` `repository` field still references `pingdotgg/t3code`. |
| README / docs | `README.md`, `docs/architecture.md`, `docs/audit-2026-09-15.md`, `docs/performance-2026-09-15.md` are thorough. No `desktop/AGENTS.md` or `desktop/CLAUDE.md` exist. |

---

## 5. Suggested Modifications (Advisory)

Grouped by priority. No changes have been made — these are recommendations for Soumya to consider.

### 5.1 Security

- **Fix the SSRF in `MarkdownView.swift`.** Pick (b) — DNS resolve + reject loopback/RFC1918/link-local + redirect delegate — or (c) — proxy via backend. Surfacing this to the user in plain language before changing code is appropriate.

### 5.2 Correctness

- **Verify `RootView.swift:157` `CGEventType(rawValue: ~0)!`** at the next launch. If `CGEventType` has no case at raw value `UInt32.max` the app traps. Either correct the bitmask value or refactor the masking approach.
- **Tighten `HydraCookbook+Resolve.swift:58`** to `guard let`.
- **Refactor the watchdog double-revoke** in `ProviderRegistry.swift:557-564`.

### 5.3 Sync with droppycode

Use a worktree (per AGENTS.md) and port, in this order:

1. **MR !373** (Antigravity `--allowed-mcp-server-names` fix) — one-liner, immediate value.
2. **MR !375** (`HydraDelegationBudget` value type) — high-leverage core model change; backport to `SwarmCode/Core/Models/Hydra.swift` and update consumers.
3. **MR !379** (OpenCode Zen / Go split) — `ProviderRegistry.swift` +82/-5 + `Provider.swift` + `PlanLimits.swift`.
4. **MR !381** (timeline anchor + chronologicalTimeline) — affects `Core/Models/Timeline.swift`.
5. **MR !376** (collapsible settings) — keep the `ChromeRevealLayout` / `ChromeQuietButtonStyle` pattern; add a web equivalent if the refactor in `SettingsPanels.tsx` continues.
6. **MR !380** (appearance / window-level zoom / font migration) — pattern-only adopt; consider a smaller-scope backport of `Font.TextStyle` + `Chrome.secondaryText` rather than the full zoom rewrite.

Do **not** re-port Jev (`MRs !382`, !386) — it was reverted upstream.

### 5.4 Settings refactor (in progress, complete it)

- Remove the inline `AboutVersionTitle` / `AboutVersionSection` from `SettingsPanels.tsx` (W1).
- Delete the unused `MCPSettingsPanel` import in `SourceControlSettings.tsx:6` (W2).
- Move `HydraMarkSvg` out of `HydraSettingsPanel.tsx` into a shared icons module (W3).
- Consolidate `backgroundActivityOverrideSettings` to a single copy (W4).
- Continue splitting `SettingsPanels.tsx` (W5).
- Tighten the `data-slot$="popup"` selector in the global keydown listener (W7).
- Schedule a pass to remove `t3code` branding (W8, W9).
- Add hex-colour validation in `canonicalThemes.ts` (W10).

### 5.5 Optional follow-ups

- Decide whether to backport `TerminalFontResolver`, `ZoomLayout`, `ChromeQuietButtonStyle` from upstream.
- Land the remaining audit items (K3 = `supportsCompact`, D6 = text-size scaling).
- Run `docs/performance-2026-09-15.md` items still flagged "not done".
- Update the legacy `apps/server/package.json` `repository` field to `soumyachk101/Swarm-Code`.

---

## 6. Files Touched In This Audit

None. Per Soumya's instruction "**@SwarmCode/ ispe kuch bhi changes mat karna**", this document is the only output produced.

---

## 7. Open Questions for Soumya

1. **SSRF fix path** — go with (b) inline validation, (c) backend proxy, or (a) third-party service route?
2. **`RootView.swift:157` verification** — should a Hydra head write a small launcher repro / boot-trace to confirm whether the launch trap fires today?
3. **Sync direction** — full rebase onto droppy-upstream/main, or cherry-pick each MR by hand?
4. **`@anthropic-ai/claude-agent-sdk` version pinning** — keep stripped-platform overrides, or re-evaluate now?
5. **T3 → Swarm-Code rename** — schedule a single cleanup MR for `T3_CHAT_THEME`, `t3code:` storage keys, and the server `repository` field, or piecemeal?
