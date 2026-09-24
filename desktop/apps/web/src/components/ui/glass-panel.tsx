import type { ReactNode } from "react";
import { cn } from "~/lib/utils";

export type GlassPanelVariant = "panel" | "capsule" | "card" | "sheet";

const VARIANT_CLASS: Record<GlassPanelVariant, string> = {
  panel: "glass-panel",
  capsule: "glass-capsule",
  card: "card",
  sheet: "glass-panel",
};

export function GlassPanel({
  variant,
  children,
  className,
}: {
  variant: GlassPanelVariant;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={cn(
        VARIANT_CLASS[variant],
        variant === "capsule" && "rounded-full",
        variant === "sheet" && "rounded-[var(--sheet-corner-radius)]",
        variant === "card" && "rounded-[var(--card-corner-radius)]",
        className,
      )}
    >
      {children}
    </div>
  );
}
