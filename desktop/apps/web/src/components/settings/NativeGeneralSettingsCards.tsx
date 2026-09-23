import { useState } from "react";
import {
  FolderIcon,
  GitBranchIcon,
  LockIcon,
  RectangleHorizontalIcon,
  MinusIcon,
  RotateCcwIcon,
  ColumnsIcon,
  AppWindowIcon,
  LayoutIcon,
  ListIcon,
  AlignLeftIcon,
  ImageIcon,
} from "lucide-react";
import { cn } from "~/lib/utils";
import { Switch } from "../ui/switch";
import { Button } from "../ui/button";
import { TokenActivityHeatmap } from "./TokenActivityHeatmap";

export function NativeGeneralSettingsCards() {
  // New threads state
  const [permission, setPermission] = useState<"full" | "commands" | "edits">("full");
  const [workspaceMode, setWorkspaceMode] = useState<"local" | "worktree">("local");

  // Conversation state
  const [showThinking, setShowThinking] = useState(true);
  const [conciseReplies, setConciseReplies] = useState(true);
  const [workingLineMode, setWorkingLineMode] = useState<"card" | "line">("card");
  const [recentDownloads, setRecentDownloads] = useState(true);
  const [notifyFinished, setNotifyFinished] = useState(true);
  const [chimeFinished, setChimeFinished] = useState(true);
  const [confirmDeleting, setConfirmDeleting] = useState(true);
  const [continueAfterLimit, setContinueAfterLimit] = useState(true);
  const [showUsagePanel, setShowUsagePanel] = useState(false);

  // Projects
  const [projectsEnabled, setProjectsEnabled] = useState(true);

  // Appearance & Window
  const [transparency, setTransparency] = useState(80);
  const [sidebarMode, setSidebarMode] = useState<"column" | "floating" | "panel">("column");
  const [activityListMode, setActivityListMode] = useState<"icon" | "name">("name");
  const [openSidebarAtLaunch, setOpenSidebarAtLaunch] = useState(true);

  return (
    <div className="space-y-7">
      {/* 1. Token Activity Section */}
      <TokenActivityHeatmap />

      {/* 2. New Threads Section */}
      <div className="space-y-2">
        <h4 className="text-[13px] font-semibold text-muted-foreground px-0.5">New threads</h4>
        <div className="rounded-2xl border border-white/10 bg-white/[0.02] divide-y divide-white/5 overflow-hidden">
          {/* Provider and model row */}
          <div className="p-4 space-y-1">
            <div className="text-sm font-medium text-foreground">Provider and model</div>
            <p className="text-xs text-muted-foreground leading-relaxed">
              A new thread follows the one you are in: its provider, model, effort and Hydra pair.
              With no thread open it starts on the provider you last chose.
            </p>
          </div>

          {/* Permissions row */}
          <div className="p-4 flex items-center justify-between gap-4">
            <div className="space-y-1">
              <div className="text-sm font-medium text-foreground">Permissions</div>
              <p className="text-xs text-muted-foreground">
                {permission === "full"
                  ? "Runs commands and edits without asking"
                  : permission === "commands"
                    ? "Asks before running bash commands"
                    : "Asks before modifying files"}
              </p>
            </div>
            <div className="relative">
              <button
                type="button"
                onClick={() =>
                  setPermission((p) => (p === "full" ? "commands" : p === "commands" ? "edits" : "full"))
                }
                className="inline-flex items-center gap-2 px-3 py-1.5 rounded-lg border border-white/10 bg-white/[0.05] hover:bg-white/[0.08] text-xs font-medium text-foreground transition-colors cursor-pointer"
              >
                <LockIcon className="size-3.5 text-muted-foreground" />
                <span>
                  {permission === "full"
                    ? "Full access"
                    : permission === "commands"
                      ? "Ask commands"
                      : "Ask edits"}
                </span>
                <span className="text-[10px] text-muted-foreground">▾</span>
              </button>
            </div>
          </div>

          {/* Workspace row */}
          <div className="p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
            <div className="space-y-1">
              <div className="text-sm font-medium text-foreground">Workspace</div>
              <p className="text-xs text-muted-foreground">Where a new thread makes its changes</p>
            </div>
            <div className="flex items-center gap-2.5 shrink-0">
              <button
                type="button"
                onClick={() => setWorkspaceMode("local")}
                className={cn(
                  "flex flex-col items-center justify-center w-24 h-16 rounded-xl border transition-all cursor-pointer",
                  workspaceMode === "local"
                    ? "border-purple-500/80 bg-purple-500/15 text-foreground ring-1 ring-purple-500/40"
                    : "border-white/10 bg-white/[0.02] text-muted-foreground hover:bg-white/[0.05] hover:text-foreground",
                )}
              >
                <FolderIcon className="size-5 mb-1" />
                <span className="text-[11px] font-medium">Local</span>
              </button>

              <button
                type="button"
                onClick={() => setWorkspaceMode("worktree")}
                className={cn(
                  "flex flex-col items-center justify-center w-24 h-16 rounded-xl border transition-all cursor-pointer",
                  workspaceMode === "worktree"
                    ? "border-purple-500/80 bg-purple-500/15 text-foreground ring-1 ring-purple-500/40"
                    : "border-white/10 bg-white/[0.02] text-muted-foreground hover:bg-white/[0.05] hover:text-foreground",
                )}
              >
                <GitBranchIcon className="size-5 mb-1" />
                <span className="text-[11px] font-medium">New worktree</span>
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* 3. Conversation Section */}
      <div className="space-y-2">
        <h4 className="text-[13px] font-semibold text-muted-foreground px-0.5">Conversation</h4>
        <div className="rounded-2xl border border-white/10 bg-white/[0.02] divide-y divide-white/5 overflow-hidden">
          {/* Show thinking */}
          <div className="p-4 flex items-center justify-between gap-4">
            <div className="space-y-1">
              <div className="text-sm font-medium text-foreground">Show thinking</div>
              <p className="text-xs text-muted-foreground">
                The working line opens to the agent&apos;s thinking
              </p>
            </div>
            <Switch checked={showThinking} onCheckedChange={setShowThinking} aria-label="Show thinking" />
          </div>

          {/* Concise AI replies */}
          <div className="p-4 flex items-center justify-between gap-4">
            <div className="space-y-1">
              <div className="text-sm font-medium text-foreground">Concise AI replies</div>
              <p className="text-xs text-muted-foreground leading-relaxed">
                Built-in guidance for shorter replies, useful code comments, and focused work,
                including Hydra heads. Changes apply on the next message.
              </p>
            </div>
            <Switch
              checked={conciseReplies}
              onCheckedChange={setConciseReplies}
              aria-label="Concise AI replies"
            />
          </div>

          {/* Working line */}
          <div className="p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
            <div className="space-y-1">
              <div className="text-sm font-medium text-foreground">Working line</div>
              <p className="text-xs text-muted-foreground">
                A card with the turn&apos;s progress bar, or a plain line
              </p>
            </div>
            <div className="flex items-center gap-2.5 shrink-0">
              <button
                type="button"
                onClick={() => setWorkingLineMode("card")}
                className={cn(
                  "flex flex-col items-center justify-center w-24 h-16 rounded-xl border transition-all cursor-pointer",
                  workingLineMode === "card"
                    ? "border-purple-500/80 bg-purple-500/15 text-foreground ring-1 ring-purple-500/40"
                    : "border-white/10 bg-white/[0.02] text-muted-foreground hover:bg-white/[0.05] hover:text-foreground",
                )}
              >
                <RectangleHorizontalIcon className="size-5 mb-1" />
                <span className="text-[11px] font-medium">Card</span>
              </button>

              <button
                type="button"
                onClick={() => setWorkingLineMode("line")}
                className={cn(
                  "flex flex-col items-center justify-center w-24 h-16 rounded-xl border transition-all cursor-pointer",
                  workingLineMode === "line"
                    ? "border-purple-500/80 bg-purple-500/15 text-foreground ring-1 ring-purple-500/40"
                    : "border-white/10 bg-white/[0.02] text-muted-foreground hover:bg-white/[0.05] hover:text-foreground",
                )}
              >
                <MinusIcon className="size-5 mb-1" />
                <span className="text-[11px] font-medium">Line</span>
              </button>
            </div>
          </div>

          {/* Recent downloads */}
          <div className="p-4 flex items-center justify-between gap-4">
            <div className="space-y-1">
              <div className="text-sm font-medium text-foreground">Recent downloads</div>
              <p className="text-xs text-muted-foreground">
                The attach button offers recent downloads first
              </p>
            </div>
            <Switch
              checked={recentDownloads}
              onCheckedChange={setRecentDownloads}
              aria-label="Recent downloads"
            />
          </div>

          {/* Notify when a turn finishes */}
          <div className="p-4 flex items-center justify-between gap-4">
            <div className="space-y-1">
              <div className="text-sm font-medium text-foreground">Notify when a turn finishes</div>
              <p className="text-xs text-muted-foreground">
                Desktop alerts and in-app banner when the agent finishes a task
              </p>
            </div>
            <div className="flex items-center gap-3">
              <Button
                variant="ghost"
                size="sm"
                className="h-6 px-2 text-[11px] text-muted-foreground bg-white/[0.06] hover:bg-white/[0.12] rounded"
                onClick={() => {
                  if ("Notification" in window && Notification.permission === "granted") {
                    new Notification("Swarm Code", { body: "Turn finished demo alert" });
                  }
                }}
              >
                Test
              </Button>
              <Switch
                checked={notifyFinished}
                onCheckedChange={setNotifyFinished}
                aria-label="Notify when finished"
              />
            </div>
          </div>

          {/* Chime when a turn finishes */}
          <div className="p-4 flex items-center justify-between gap-4">
            <div className="space-y-1">
              <div className="text-sm font-medium text-foreground">Chime when a turn finishes</div>
              <p className="text-xs text-muted-foreground">
                A soft chime, whether or not the thread is in view
              </p>
            </div>
            <Switch
              checked={chimeFinished}
              onCheckedChange={setChimeFinished}
              aria-label="Chime when finished"
            />
          </div>

          {/* Confirm before deleting threads */}
          <div className="p-4 flex items-center justify-between gap-4">
            <div className="space-y-1">
              <div className="text-sm font-medium text-foreground">Confirm before deleting threads</div>
            </div>
            <Switch
              checked={confirmDeleting}
              onCheckedChange={setConfirmDeleting}
              aria-label="Confirm before deleting"
            />
          </div>

          {/* Continue after a usage limit */}
          <div className="p-4 flex items-center justify-between gap-4">
            <div className="space-y-1">
              <div className="text-sm font-medium text-foreground">Continue after a usage limit</div>
              <p className="text-xs text-muted-foreground leading-relaxed">
                When the provider&apos;s limit is spent, the chat waits for the reset and then tells
                the agent to carry on
              </p>
            </div>
            <Switch
              checked={continueAfterLimit}
              onCheckedChange={setContinueAfterLimit}
              aria-label="Continue after limit"
            />
          </div>

          {/* Show a usage panel */}
          <div className="p-4 flex items-center justify-between gap-4">
            <div className="space-y-1">
              <div className="text-sm font-medium text-foreground">Show a usage panel</div>
              <p className="text-xs text-muted-foreground leading-relaxed">
                The plan&apos;s limits and credits in a floating panel beside every chat, for the
                model in use or a pair&apos;s two; the usage popover&apos;s pop-out button switches it
                on as well, and it keeps the corner it was last dragged to
              </p>
            </div>
            <Switch
              checked={showUsagePanel}
              onCheckedChange={setShowUsagePanel}
              aria-label="Show usage panel"
            />
          </div>
        </div>
      </div>

      {/* 4. Projects Section */}
      <div className="space-y-2">
        <h4 className="text-[13px] font-semibold text-muted-foreground px-0.5">Projects</h4>
        <div className="rounded-2xl border border-white/10 bg-white/[0.02] overflow-hidden p-4 flex items-center justify-between gap-4">
          <div className="space-y-1">
            <div className="text-sm font-medium text-foreground">Projects</div>
            <p className="text-xs text-muted-foreground">
              Activates every project at once unless explicitly overridden
            </p>
          </div>
          <Switch
            checked={projectsEnabled}
            onCheckedChange={setProjectsEnabled}
            aria-label="Projects enabled"
          />
        </div>
      </div>

      {/* 5. Window & Appearance Section (from Screenshot 7.03.29 PM) */}
      <div className="space-y-2">
        <h4 className="text-[13px] font-semibold text-muted-foreground px-0.5">Appearance & Window</h4>
        <div className="rounded-2xl border border-white/10 bg-white/[0.02] divide-y divide-white/5 overflow-hidden">
          {/* Transparency slider */}
          <div className="p-4 flex items-center justify-between gap-4">
            <div className="space-y-1">
              <div className="text-sm font-medium text-foreground">Transparency</div>
              <p className="text-xs text-muted-foreground">How much shows through the window</p>
            </div>
            <div className="flex items-center gap-3 w-48">
              <button
                type="button"
                onClick={() => setTransparency(80)}
                className="text-muted-foreground hover:text-foreground transition-colors cursor-pointer"
              >
                <RotateCcwIcon className="size-3.5" />
              </button>
              <input
                type="range"
                min={0}
                max={100}
                value={transparency}
                onChange={(e) => setTransparency(Number(e.target.value))}
                className="w-full accent-purple-500 cursor-pointer"
              />
            </div>
          </div>

          {/* Sidebar Mode Picker */}
          <div className="p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
            <div className="space-y-1">
              <div className="text-sm font-medium text-foreground">Sidebar</div>
              <p className="text-xs text-muted-foreground">
                A column beside the chat; the sidebar button in the toolbar shows and hides it
              </p>
            </div>
            <div className="flex items-center gap-2 shrink-0">
              <button
                type="button"
                onClick={() => setSidebarMode("column")}
                className={cn(
                  "flex flex-col items-center justify-center w-20 h-16 rounded-xl border transition-all cursor-pointer",
                  sidebarMode === "column"
                    ? "border-purple-500/80 bg-purple-500/15 text-foreground ring-1 ring-purple-500/40"
                    : "border-white/10 bg-white/[0.02] text-muted-foreground hover:bg-white/[0.05] hover:text-foreground",
                )}
              >
                <ColumnsIcon className="size-4 mb-1" />
                <span className="text-[10px] font-medium">Column</span>
              </button>

              <button
                type="button"
                onClick={() => setSidebarMode("floating")}
                className={cn(
                  "flex flex-col items-center justify-center w-20 h-16 rounded-xl border transition-all cursor-pointer",
                  sidebarMode === "floating"
                    ? "border-purple-500/80 bg-purple-500/15 text-foreground ring-1 ring-purple-500/40"
                    : "border-white/10 bg-white/[0.02] text-muted-foreground hover:bg-white/[0.05] hover:text-foreground",
                )}
              >
                <AppWindowIcon className="size-4 mb-1" />
                <span className="text-[10px] font-medium">Floating</span>
              </button>

              <button
                type="button"
                onClick={() => setSidebarMode("panel")}
                className={cn(
                  "flex flex-col items-center justify-center w-20 h-16 rounded-xl border transition-all cursor-pointer",
                  sidebarMode === "panel"
                    ? "border-purple-500/80 bg-purple-500/15 text-foreground ring-1 ring-purple-500/40"
                    : "border-white/10 bg-white/[0.02] text-muted-foreground hover:bg-white/[0.05] hover:text-foreground",
                )}
              >
                <LayoutIcon className="size-4 mb-1" />
                <span className="text-[10px] font-medium">Panel only</span>
              </button>
            </div>
          </div>

          {/* Activity list */}
          <div className="p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
            <div className="space-y-1">
              <div className="text-sm font-medium text-foreground">Activity list</div>
              <p className="text-xs text-muted-foreground">
                The project&apos;s name, with a folder mark, on a line under the thread&apos;s title
              </p>
            </div>
            <div className="flex items-center gap-2 shrink-0">
              <button
                type="button"
                onClick={() => setActivityListMode("icon")}
                className={cn(
                  "flex flex-col items-center justify-center w-24 h-16 rounded-xl border transition-all cursor-pointer",
                  activityListMode === "icon"
                    ? "border-purple-500/80 bg-purple-500/15 text-foreground ring-1 ring-purple-500/40"
                    : "border-white/10 bg-white/[0.02] text-muted-foreground hover:bg-white/[0.05] hover:text-foreground",
                )}
              >
                <ListIcon className="size-4 mb-1" />
                <span className="text-[11px] font-medium">Icon</span>
              </button>

              <button
                type="button"
                onClick={() => setActivityListMode("name")}
                className={cn(
                  "flex flex-col items-center justify-center w-24 h-16 rounded-xl border transition-all cursor-pointer",
                  activityListMode === "name"
                    ? "border-purple-500/80 bg-purple-500/15 text-foreground ring-1 ring-purple-500/40"
                    : "border-white/10 bg-white/[0.02] text-muted-foreground hover:bg-white/[0.05] hover:text-foreground",
                )}
              >
                <AlignLeftIcon className="size-4 mb-1" />
                <span className="text-[11px] font-medium">Project name</span>
              </button>
            </div>
          </div>

          {/* Open the sidebar at launch */}
          <div className="p-4 flex items-center justify-between gap-4">
            <div className="space-y-1">
              <div className="text-sm font-medium text-foreground">Open the sidebar at launch</div>
              <p className="text-xs text-muted-foreground">
                Collapsed otherwise; the sidebar button in the toolbar shows and hides it any time
              </p>
            </div>
            <Switch
              checked={openSidebarAtLaunch}
              onCheckedChange={setOpenSidebarAtLaunch}
              aria-label="Open sidebar at launch"
            />
          </div>

          {/* Wallpaper Drop Target */}
          <div className="p-4 space-y-3">
            <div className="rounded-xl border border-dashed border-white/15 bg-white/[0.01] hover:bg-white/[0.03] transition-colors p-8 flex flex-col items-center justify-center text-center cursor-pointer">
              <ImageIcon className="size-8 text-muted-foreground/60 mb-2" />
              <p className="text-xs font-medium text-muted-foreground">
                Drop a picture here, or choose one
              </p>
            </div>
            <div className="flex items-center justify-between">
              <div className="space-y-0.5">
                <div className="text-xs font-medium text-foreground">Wallpaper</div>
                <p className="text-[11px] text-muted-foreground">
                  A picture of your own behind the glass, mixed with the desktop
                </p>
              </div>
              <Button
                variant="outline"
                size="sm"
                className="h-7 text-xs rounded-full border-white/10 bg-white/[0.05] hover:bg-white/[0.1]"
              >
                Choose...
              </Button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
