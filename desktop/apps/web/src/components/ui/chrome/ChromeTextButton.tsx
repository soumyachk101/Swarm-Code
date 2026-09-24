import type { LucideIcon } from "lucide-react";
import { cn } from "~/lib/utils";

export function ChromeTextButton({
  symbol: Icon,
  title,
  help,
  destructive = false,
  onClick,
  className,
}: {
  symbol?: LucideIcon;
  title: string;
  help?: string;
  destructive?: boolean;
  onClick?: () => void;
  className?: string;
}) {
  return (
    <button
      aria-label={help}
      className={cn(
        "btn-glass glass-interactive inline-flex items-center gap-1.5",
        destructive && "text-red-500 dark:text-red-400",
        className,
      )}
      onClick={onClick}
      title={help}
      type="button"
    >
      {Icon && <Icon size={14} strokeWidth={1.5} />}
      <span>{title}</span>
    </button>
  );
}
