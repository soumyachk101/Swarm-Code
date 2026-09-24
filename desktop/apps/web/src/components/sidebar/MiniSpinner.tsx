import { useMemo } from "react";
import { cn } from "../lib/utils";

const CELL = 5;
const GAP = 2;
const COLS = 3;
const ROWS = 2;

/** 2×3 cell grid: cells animate with phase shift derived from row/col index.
 *  Tint uses the current --accent-color via CSS filter brightness. */
export function MiniSpinner({ className }: { className?: string }) {
  const cells = useMemo(
    () =>
      Array.from({ length: ROWS * COLS }, (_, i) => {
        const row = Math.floor(i / COLS);
        const col = i % COLS;
        return { row, col, delay: `${(row * COLS + col) * 0.12}s` };
      }),
    [],
  );

  return (
    <span
      aria-hidden="true"
      className={cn(
        "inline-grid shrink-0",
        `grid-cols-[${CELL}px_${GAP}px_${CELL}px_${GAP}px_${CELL}px]`,
        `grid-rows-[${CELL}px_${GAP}px_${CELL}px]`,
        className,
      )}
      style={{ width: CELL * COLS + GAP * (COLS - 1), height: CELL * ROWS + GAP * (ROWS - 1) }}
    >
      {cells.map(({ row, col, delay }) => (
        <span
          key={`${row}-${col}`}
          className="inline-block rounded-[1px]"
          style={
            {
              gridRow: row + 1,
              gridColumn: col + 1,
              width: CELL,
              height: CELL,
              backgroundColor: "var(--accent-color)",
              animation: `mini-spinner-phase 1.1s ease-in-out infinite`,
              animationDelay: delay,
            } as React.CSSProperties
          }
        />
      ))}
    </span>
  );
}

/** inject spinner keyframes (once per app via a global style tag or at root CSS). */
export function MiniSpinnerKeyframes() {
  return (
    <style>{`
      @keyframes mini-spinner-phase {
        0%, 100% { opacity: 0.15; filter: brightness(0.6); }
        50% { opacity: 1;   filter: brightness(1.4); }
      }
    `}</style>
  );
}
