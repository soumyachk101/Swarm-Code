import type { LucideIcon } from "lucide-react";
import { cn } from "~/lib/utils";

export function ChromeIconButton({
  symbol: Icon,
  help,
  onClick,
  className,
}: {
  symbol: LucideIcon;
  help?: string;
  onClick?: () => void;
  className?: string;
}) {
  return (
    <button
      aria-label={help}
      className={cn(
        "chromeGlassCapsule glass-interactive flex h-7 w-7 items-center justify-center",
        className,
      )}
      onClick={onClick}
      title={help}
      type="button"
    >
      <Icon size={14} strokeWidth={1.5} />
    </button>
  );
}
