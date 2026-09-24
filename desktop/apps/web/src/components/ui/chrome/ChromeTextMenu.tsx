import { ChevronDown } from "lucide-react";
import {
  Popover,
  PopoverPopup,
  PopoverTrigger,
} from "~/components/ui/popover";
import { cn } from "~/lib/utils";

export function ChromeTextMenu({
  title,
  help,
  children,
  className,
}: {
  title: string;
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
        <span className="truncate">{title}</span>
        <ChevronDown size={10} strokeWidth={2} />
      </PopoverTrigger>
      <PopoverPopup>{children}</PopoverPopup>
    </Popover>
  );
}
