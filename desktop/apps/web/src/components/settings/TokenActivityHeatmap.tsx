import { useMemo, useState } from "react";
import { cn } from "~/lib/utils";

type TokenActivityMode = "daily" | "weekly" | "cumulative";

const MONTH_LABELS = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
] as const;

export function TokenActivityHeatmap({ className }: { className?: string }) {
  const [mode, setMode] = useState<TokenActivityMode>("daily");

  // Generate 52 weeks x 7 days pseudo-activity pattern matching native Swarm Code
  const grid = useMemo(() => {
    // 52 columns, 7 rows (Sunday=0 to Saturday=6 or Monday to Sunday)
    const weeks: number[][] = [];
    // Seed an organic distribution reminiscent of the screenshot (dense in late months Sep/Oct)
    for (let w = 0; w < 52; w++) {
      const days: number[] = [];
      for (let d = 0; d < 7; d++) {
        // Late months (weeks 35 to 45) have active bursts like in Screenshot 7.02.33 PM
        if (w >= 37 && w <= 42) {
          if (w === 39 && (d === 0 || d === 1)) days.push(4);
          else if (w === 38 && d === 1) days.push(2);
          else if (w === 39 && d === 6) days.push(3);
          else if ((w + d) % 5 === 0) days.push(1);
          else days.push(0);
        } else if (w > 42) {
          // Future or current empty weeks
          days.push(0);
        } else if ((w * 7 + d) % 23 === 0) {
          days.push(1);
        } else {
          days.push(0);
        }
      }
      weeks.push(days);
    }
    return weeks;
  }, []);

  const totalTokens = "136.8M";

  return (
    <div className={cn("space-y-3 pb-2", className)}>
      {/* Header with Title and Mode Capsule Switches */}
      <div className="flex items-center justify-between">
        <h3 className="text-[15px] font-semibold tracking-tight text-foreground">
          Token activity
        </h3>
        <div className="flex items-center gap-1 bg-white/[0.04] p-0.5 rounded-full border border-white/5">
          {(
            [
              { id: "daily", label: "Daily" },
              { id: "weekly", label: "Weekly" },
              { id: "cumulative", label: "Cumulative" },
            ] as const
          ).map((item) => (
            <button
              key={item.id}
              type="button"
              onClick={() => setMode(item.id)}
              className={cn(
                "px-3 py-1 text-xs font-medium rounded-full transition-all duration-150 cursor-pointer",
                mode === item.id
                  ? "bg-purple-600/90 text-white shadow-xs font-semibold"
                  : "text-muted-foreground hover:text-foreground hover:bg-white/[0.05]",
              )}
            >
              {item.label}
            </button>
          ))}
        </div>
      </div>

      {/* Heatmap Grid (52 weeks x 7 days) */}
      <div className="w-full overflow-x-auto no-scrollbar pt-1">
        <div className="min-w-[680px]">
          <div className="grid grid-flow-col grid-rows-7 gap-[3px]">
            {grid.map((week, wIdx) =>
              week.map((level, dIdx) => {
                let cellColor = "bg-white/[0.06]";
                if (level === 1) cellColor = "bg-purple-400/35";
                else if (level === 2) cellColor = "bg-purple-400/60";
                else if (level === 3) cellColor = "bg-purple-300/80";
                else if (level === 4) cellColor = "bg-[#c084fc]";

                return (
                  <div
                    key={`${wIdx}-${dIdx}`}
                    className={cn(
                      "size-[10px] rounded-[2.5px] transition-colors duration-150",
                      cellColor,
                    )}
                  />
                );
              }),
            )}
          </div>

          {/* Month Labels Strip */}
          <div className="grid grid-cols-12 text-[11px] font-medium text-muted-foreground/75 pt-2 px-0.5">
            {MONTH_LABELS.map((month) => (
              <span key={month} className="text-left">
                {month}
              </span>
            ))}
          </div>
        </div>
      </div>

      {/* Footer Legend */}
      <div className="flex items-center justify-between text-[11px] text-muted-foreground pt-1">
        <span>{totalTokens} tokens recorded</span>
        <div className="flex items-center gap-1.5">
          <span className="text-[10px]">Less</span>
          <div className="flex items-center gap-[3px]">
            <div className="size-[9px] rounded-[2px] bg-white/[0.06]" />
            <div className="size-[9px] rounded-[2px] bg-purple-400/35" />
            <div className="size-[9px] rounded-[2px] bg-purple-400/60" />
            <div className="size-[9px] rounded-[2px] bg-purple-300/80" />
            <div className="size-[9px] rounded-[2px] bg-[#c084fc]" />
          </div>
          <span className="text-[10px]">More</span>
        </div>
      </div>
    </div>
  );
}
