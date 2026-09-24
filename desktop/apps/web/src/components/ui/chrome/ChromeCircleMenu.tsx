import type { LucideIcon } from "lucide-react";
import {
  Popover,
  PopoverPopup,
  PopoverTrigger,
} from "~/components/ui/popover";
import { cn } from "~/lib/utils";

export function ChromeCircleMenu({
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
