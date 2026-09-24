import type { LucideIcon } from "lucide-react";
import {
  Popover,
  PopoverPopup,
  PopoverTrigger,
} from "~/components/ui/popover";
import { cn } from "~/lib/utils";

export function ChromeMenuButton({
  symbol: Icon,
  help,
  children,
  className,
}: {
  symbol: LucideIcon;
  help?: string;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <Popover>
      <PopoverTrigger
        aria-label={help}
        className={cn(
          "btn-glass glass-interactive inline-flex items-center gap-1.5",
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
