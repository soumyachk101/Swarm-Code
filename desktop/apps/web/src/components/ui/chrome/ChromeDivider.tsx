import { cn } from "~/lib/utils";

export function ChromeDivider({ className }: { className?: string }) {
  return (
    <div
      aria-orientation="vertical"
      className={cn(
        "mx-0.5 inline-block h-3.5 w-px shrink-0 bg-current/15",
        className,
      )}
      role="separator"
    />
  );
}
