import type { ReactNode } from "react";
import { cn } from "~/lib/utils";

export function ChromeCapsule({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={cn("chromeGlassCapsule flex items-center gap-1", className)}>
      {children}
    </div>
  );
}
