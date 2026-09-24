import type { CanonicalThemeSpec } from "./canonicalThemes";

export type CanonicalTheme = CanonicalThemeSpec;

/**
 * Map a CanonicalTheme to CSS custom properties on :root and set the
 * data-theme attribute on documentElement.
 *
 * Called on theme change so every glass control, capsule, and status hue
 * recolors at once.
 */
export function emitThemeCssVariables(theme: CanonicalTheme, mode: "light" | "dark" | "system"): void {
  if (typeof document === "undefined") return;

  const root = document.documentElement;

  // Determine the effective appearance
  const effectiveMode =
    mode === "system"
      ? window.matchMedia("(prefers-color-scheme: light)").matches
        ? "light"
        : "dark"
      : mode;

  // Set data-theme attribute (used for per-theme CSS selectors)
  root.setAttribute("data-theme", theme.id);

  // Colors derived from the theme spec
  const accent = theme.accent;

  // Glass tint — semi-transparent canvas color
  const tintAlpha = effectiveMode === "dark" ? 0.65 : 0.72;
  const glassTint = hexToRgba(theme.canvas, tintAlpha);

  // Glass border — subtle white or black tint depending on mode
  const glassBorder =
    effectiveMode === "dark"
      ? "rgba(255, 255, 255, 0.08)"
      : "rgba(0, 0, 0, 0.06)";

  // Text colors
  const textPrimary =
    effectiveMode === "dark"
      ? "rgba(255, 255, 255, 0.92)"
      : "rgba(0, 0, 0, 0.88)";
  const textSecondary =
    effectiveMode === "dark"
      ? "rgba(255, 255, 255, 0.6)"
      : "rgba(0, 0, 0, 0.55)";

  // Status colors — standard, not theme-tinted
  const successColor = "#4ade80";
  const warningColor = "#facc15";
  const dangerColor = "#f87171";

  // Emit variables
  root.style.setProperty("--accent-color", accent);
  root.style.setProperty("--glass-tint", glassTint);
  root.style.setProperty("--glass-border", glassBorder);
  root.style.setProperty("--text-primary", textPrimary);
  root.style.setProperty("--text-secondary", textSecondary);
  root.style.setProperty("--success-color", successColor);
  root.style.setProperty("--warning-color", warningColor);
  root.style.setProperty("--danger-color", dangerColor);

  // Theme appearance class on <html> for light/dark-scoped tokens
  root.classList.toggle("dark", effectiveMode === "dark");
  root.classList.toggle("light", effectiveMode === "light");

  // Liquid Glass gets extra well tokens
  if (theme.id === "liquid-glass") {
    root.style.setProperty("--bg-well", "#131823");
    root.style.setProperty("--bg-well-raised", "#1a2030");
    root.style.setProperty("--accent-glow", "rgba(79, 156, 255, 0.45)");
    root.style.setProperty("--accent-soft", "rgba(79, 156, 255, 0.16)");
  } else {
    root.style.removeProperty("--bg-well");
    root.style.removeProperty("--bg-well-raised");
    root.style.removeProperty("--accent-glow");
    root.style.removeProperty("--accent-soft");
  }
}

/**
 * Convert a hex color (#rrggbb or #rgb) to rgba string.
 */
function hexToRgba(hex: string, alpha: number): string {
  const clean = hex.replace("#", "");
  const r = parseInt(clean.substring(0, 2), 16);
  const g = parseInt(clean.substring(2, 4), 16);
  const b = parseInt(clean.substring(4, 6), 16);
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

/**
 * Clear all theme-emitted CSS variables from the document.
 * Called when no theme is active.
 */
export function clearThemeCssVariables(): void {
  if (typeof document === "undefined") return;
  const root = document.documentElement;
  root.removeAttribute("data-theme");
  root.classList.remove("dark", "light");
  const vars = [
    "--accent-color",
    "--glass-tint",
    "--glass-border",
    "--text-primary",
    "--text-secondary",
    "--success-color",
    "--warning-color",
    "--danger-color",
    "--bg-well",
    "--bg-well-raised",
    "--accent-glow",
    "--accent-soft",
  ];
  for (const v of vars) root.style.removeProperty(v);
}
