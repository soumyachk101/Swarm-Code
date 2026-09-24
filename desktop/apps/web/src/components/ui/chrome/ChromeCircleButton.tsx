import type { LucideIcon } from "lucide-react";
import {
  Popover,
  PopoverPopup,
  PopoverTrigger,
} from "~/components/ui/popover";
import { cn } from "~/lib/utils";

export function ChromeCircleButton({
  symbol: Icon,
  help,
  onClick,
  className,
  children,
}: {
  symbol: LucideIcon;
  help?: string;
  onClick?: () => void;
  className?: string;
  children?: React.ReactNode;
}) {
  if (children) {
    return (
      <Popover>
        <PopoverTrigger
          aria-label={help}
          className={cn(
            "chromeGlassCapsule glass-interactive flex h-7 w-7 items-center justify-center",
            className,
          )}
          title={help}
        >
          <Icon size={14} strokeWidth={1.5} />
        </PopoverTrigger>
        <PopoverPopup>{children}</PopoverPopup>
      </Popover>
    );
  }

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
