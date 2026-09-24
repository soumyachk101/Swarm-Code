"use client";

import { cellDelay } from "~/lib/spinnerMath";

const ROW_BRIGHTNESS = [1.4, 1.0, 0.75] as const;

function formatElapsed(ms: number): string {
  const totalSeconds = Math.floor(ms / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
}

export function WorkingSpinner({
  className,
  toolName,
  elapsedMs,
}: {
  readonly className?: string;
  readonly toolName?: string;
  readonly elapsedMs?: number;
}) {
  return (
    <div className={cn("flex flex-col items-center gap-2", className)}>
      <div
        className="grid grid-cols-3 grid-rows-3"
        style={{ gap: 2, width: 22, height: 22 }}
      >
        {Array.from({ length: 3 }, (_, row) =>
          Array.from({ length: 3 }, (_, col) => (
            <div
              key={`${row}-${col}`}
              className="rounded-[3px]"
              style={{
                width: 4,
                height: 4,
                backgroundColor: "var(--accent-color)",
                filter: `brightness(${ROW_BRIGHTNESS[row]})`,
                animation: "cell-pulse 1.4s ease-in-out infinite",
                animationDelay: cellDelay(row, col),
              }}
            />
          )),
        )}
      </div>
      {(toolName || elapsedMs !== undefined) && (
        <div
          className="flex items-center gap-2 text-xs"
          style={{ color: "var(--text-secondary, var(--muted-foreground))" }}
        >
          {toolName && <span>{toolName}</span>}
          {elapsedMs !== undefined && (
            <span className="opacity-70">{formatElapsed(elapsedMs)}</span>
          )}
        </div>
      )}
    </div>
  );
}
