import type { LucideIcon } from "lucide-react";
import { cn } from "~/lib/utils";

export function ChromeIconLabel({
  symbol: Icon,
  className,
}: {
  symbol: LucideIcon;
  className?: string;
}) {
  return (
    <div
      className={cn(
        "chromeGlassCapsule flex h-7 w-7 items-center justify-center",
        className,
      )}
    >
      <Icon size={14} strokeWidth={1.5} />
    </div>
  );
}
