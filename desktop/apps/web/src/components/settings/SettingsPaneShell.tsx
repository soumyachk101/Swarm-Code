import { cn } from "~/lib/utils";

interface SettingsPaneShellProps {
  readonly sidebar: React.ReactNode;
  readonly children: React.ReactNode;
  readonly className?: string;
}

export function SettingsPaneShell({ sidebar, children, className }: SettingsPaneShellProps) {
  return (
    <div className="flex min-h-0">
      <aside
        className="shrink-0 w-64 overflow-y-auto overflow-x-hidden"
        style={{
          background: "var(--glass-tint)",
          borderRight: "1px solid var(--glass-border)",
          backdropFilter: "blur(24px) saturate(1.2)",
          WebkitBackdropFilter: "blur(24px) saturate(1.2)",
        }}
      >
        {sidebar}
      </aside>
      <main
        className={cn(
          "flex-1 min-w-0 overflow-y-auto overflow-x-hidden",
          className,
        )}
        style={{ background: "transparent" }}
      >
        {children}
      </main>
    </div>
  );
}
