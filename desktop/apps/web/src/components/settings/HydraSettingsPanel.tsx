import { useState, useEffect } from "react";
import {
  InfoIcon,
  SlidersHorizontalIcon,
  PlusIcon,
  BookOpenIcon,
  CheckIcon,
  XIcon,
  MinusCircleIcon,
  ArrowRightIcon,
  FileTextIcon,
  FolderIcon,
  LayersIcon,
  LayoutGridIcon,
  BarChart2Icon,
  ListOrderedIcon,
  ArrowLeftIcon,
} from "lucide-react";
import { useNavigate } from "@tanstack/react-router";
import { SettingsPageContainer } from "./settingsLayout";
import { Switch } from "../ui/switch";
import { ClaudeAI, OpenAI, GithubCopilotIcon, AntigravityIcon } from "../Icons";
import { SettingsBreadcrumb } from "./SettingsBreadcrumb";

export function HydraMarkSvg({ className = "size-4" }: { className?: string }) {
  return (
    <svg viewBox="0 0 100 100" fill="currentColor" className={className} aria-hidden="true">
      <path
        fillRule="nonzero"
        d="M16.00 94.00 C16.00 94.00 16.17 80.33 17.00 74.00 C17.83 67.67 19.50 61.00 21.00 56.00 C22.50 51.00 25.50 47.33 26.00 44.00 C26.50 40.67 26.17 38.83 24.00 36.00 C21.83 33.17 15.83 30.17 13.00 27.00 C10.17 23.83 7.00 17.00 7.00 17.00 C7.00 17.00 16.50 24.50 20.00 27.00 C23.50 29.50 27.50 33.17 28.00 32.00 C28.50 30.83 24.33 24.50 23.00 20.00 C21.67 15.50 20.00 5.00 20.00 5.00 C20.00 5.00 27.50 12.67 31.00 16.00 C34.50 19.33 37.17 23.67 41.00 25.00 C44.83 26.33 50.17 23.33 54.00 24.00 C57.83 24.67 61.00 26.67 64.00 29.00 C67.00 31.33 68.67 34.50 72.00 38.00 C75.33 41.50 80.33 46.33 84.00 50.00 C87.67 53.67 92.17 57.33 94.00 60.00 C95.83 62.67 95.33 64.33 95.00 66.00 C94.67 67.67 93.83 69.00 92.00 70.00 C90.17 71.00 87.33 71.67 84.00 72.00 C80.67 72.33 75.33 71.50 72.00 72.00 C68.67 72.50 67.33 72.67 64.00 75.00 C60.67 77.33 55.33 83.17 52.00 86.00 C48.67 88.83 46.00 90.67 44.00 92.00 C42.00 93.33 40.00 94.00 40.00 94.00 C40.00 94.00 16.00 94.00 16.00 94.00 Z M63.00 38.00 C60.24 38.00 58.00 40.24 58.00 43.00 C58.00 45.76 60.24 48.00 63.00 48.00 C65.76 48.00 68.00 45.76 68.00 43.00 C68.00 40.24 65.76 38.00 63.00 38.00 Z M86.00 61.20 C85.01 61.20 84.20 62.01 84.20 63.00 C84.20 63.99 85.01 64.80 86.00 64.80 C86.99 64.80 87.80 63.99 87.80 63.00 C87.80 62.01 86.99 61.20 86.00 61.20 Z"
      />
    </svg>
  );
}

const ROSTER_COLORS = ["#FF8A3D", "#3D8BFF", "#34C46A", "#A35BE0", "#F25C9A"];

interface HydraPairConfig {
  id: string;
  name?: string | undefined;
  leadProvider: string;
  leadModel: string;
  leadEffort?: string | undefined;
  headsProvider: string;
  headsModel: string;
  headsEffort?: string | undefined;
  maxHeads?: number | null | undefined;
}

const DEFAULT_PAIRS: HydraPairConfig[] = [
  {
    id: "default-1",
    name: "Opus 5 leads Sonnet 3.5",
    leadProvider: "Claude",
    leadModel: "Opus 5",
    leadEffort: "high",
    headsProvider: "Claude",
    headsModel: "Sonnet 3.5",
    headsEffort: "medium",
    maxHeads: 3,
  },
  {
    id: "default-2",
    name: "Opus 5 leads Gemini 3.8 Flash",
    leadProvider: "Claude",
    leadModel: "Opus 5",
    leadEffort: "high",
    headsProvider: "Antigravity",
    headsModel: "Gemini 3.8 Flash",
    headsEffort: "medium",
    maxHeads: 6,
  },
  {
    id: "default-3",
    name: "Astra 6 leads Terra 5.6",
    leadProvider: "Codex",
    leadModel: "Astra 6",
    leadEffort: "high",
    headsProvider: "Codex",
    headsModel: "Terra 5.6",
    headsEffort: "medium",
    maxHeads: 3,
  },
];

interface CookbookRecipe {
  id: string;
  title: string;
  tagline: string;
  leadProvider: string;
  leadModel: string;
  leadEffort?: string | undefined;
  headsProvider: string;
  headsModel: string;
  headsEffort?: string | undefined;
  maxHeads?: number | undefined;
}

const COOKBOOK_RECIPES: CookbookRecipe[] = [
  {
    id: "claude-fable-opus",
    title: "Fable 5.1 leads Opus 5",
    tagline:
      "The deepest lead over the strongest builders: Fable plans and checks, Opus heads build. Set the thinking effort of each side yourself.",
    leadProvider: "Claude",
    leadModel: "Fable 5.1",
    headsProvider: "Claude",
    headsModel: "Opus 5",
  },
  {
    id: "claude-opus-gemini-flash",
    title: "Opus 5 leads Gemini 3.8 Flash",
    tagline:
      "A careful lead and a wide, fast team: Opus writes the briefs, six Gemini Flash heads sprint through them.",
    leadProvider: "Claude",
    leadModel: "Opus 5",
    leadEffort: "high",
    headsProvider: "Antigravity",
    headsModel: "Gemini 3.8 Flash",
    headsEffort: "medium",
    maxHeads: 6,
  },
  {
    id: "claude-opus-deepseek",
    title: "Opus 5 leads DeepSeek V4.1",
    tagline:
      "Opus keeps the plan tight; DeepSeek V4.1 Flash heads keep the bill small on the routine parts.",
    leadProvider: "Claude",
    leadModel: "Opus 5",
    leadEffort: "high",
    headsProvider: "DeepSeek",
    headsModel: "V4.1 Flash",
    headsEffort: "high",
  },
  {
    id: "astra-terra",
    title: "Astra 6 leads Terra 5.6",
    tagline: "OpenAI top to bottom: Astra plans and reviews, Terra does the work at medium.",
    leadProvider: "Codex",
    leadModel: "Astra 6",
    leadEffort: "high",
    headsProvider: "Codex",
    headsModel: "Terra 5.6",
    headsEffort: "medium",
  },
  {
    id: "claude-opus-opus",
    title: "Opus 5 max, Opus 5 medium",
    tagline: "Opus thinks as hard as it can where it counts; Opus heads at medium do the building.",
    leadProvider: "Claude",
    leadModel: "Opus 5",
    leadEffort: "max",
    headsProvider: "Claude",
    headsModel: "Opus 5",
    headsEffort: "medium",
  },
];

export function HydraSettingsPanel() {
  const navigate = useNavigate();
  const [hydraEnabled, setHydraEnabled] = useState(true);
  const [isolateHeads, setIsolateHeads] = useState(true);
  const [maxHeads, setMaxHeads] = useState<number | null>(3);
  const [autoClearFinished, setAutoClearFinished] = useState(true);
  const [autoHidesIdleHeads, setAutoHidesIdleHeads] = useState(true);
  const [showsHeadDetails, setShowsHeadDetails] = useState(false);
  const [autoPopsHeads, setAutoPopsHeads] = useState(false);
  const [tempersHeadEffort, setTempersHeadEffort] = useState(true);
  const [queueHeads, setQueueHeads] = useState(true);
  const [alwaysHeads, setAlwaysHeads] = useState(false);
  const [reviewHeads, setReviewHeads] = useState(true);
  const [autoMerge, setAutoMerge] = useState(false);

  const [pairs, setPairs] = useState<HydraPairConfig[]>(DEFAULT_PAIRS);
  const [isCookbookOpen, setIsCookbookOpen] = useState(false);
  const [editingPair, setEditingPair] = useState<HydraPairConfig | null>(null);
  const [isAddingPair, setIsAddingPair] = useState(false);

  // Load from localStorage if present
  useEffect(() => {
    try {
      const saved = localStorage.getItem("swarmcode_hydra_settings_v1");
      if (saved) {
        const parsed = JSON.parse(saved);
        if (typeof parsed.hydraEnabled === "boolean") setHydraEnabled(parsed.hydraEnabled);
        if (typeof parsed.isolateHeads === "boolean") setIsolateHeads(parsed.isolateHeads);
        if (parsed.maxHeads !== undefined) setMaxHeads(parsed.maxHeads);
        if (typeof parsed.autoClearFinished === "boolean")
          setAutoClearFinished(parsed.autoClearFinished);
        if (typeof parsed.autoHidesIdleHeads === "boolean")
          setAutoHidesIdleHeads(parsed.autoHidesIdleHeads);
        if (typeof parsed.showsHeadDetails === "boolean")
          setShowsHeadDetails(parsed.showsHeadDetails);
        if (typeof parsed.autoPopsHeads === "boolean") setAutoPopsHeads(parsed.autoPopsHeads);
        if (typeof parsed.tempersHeadEffort === "boolean")
          setTempersHeadEffort(parsed.tempersHeadEffort);
        if (typeof parsed.queueHeads === "boolean") setQueueHeads(parsed.queueHeads);
        if (typeof parsed.alwaysHeads === "boolean") setAlwaysHeads(parsed.alwaysHeads);
        if (typeof parsed.reviewHeads === "boolean") setReviewHeads(parsed.reviewHeads);
        if (typeof parsed.autoMerge === "boolean") setAutoMerge(parsed.autoMerge);
        if (Array.isArray(parsed.pairs) && parsed.pairs.length > 0) setPairs(parsed.pairs);
      }
    } catch {
      // Ignore
    }
  }, []);

  // Save to localStorage on change
  const saveState = (overrides?: Partial<{ pairs: HydraPairConfig[] }>) => {
    try {
      const stateToSave = {
        hydraEnabled,
        isolateHeads,
        maxHeads,
        autoClearFinished,
        autoHidesIdleHeads,
        showsHeadDetails,
        autoPopsHeads,
        tempersHeadEffort,
        queueHeads,
        alwaysHeads,
        reviewHeads,
        autoMerge,
        pairs: overrides?.pairs ?? pairs,
      };
      localStorage.setItem("swarmcode_hydra_settings_v1", JSON.stringify(stateToSave));
    } catch {
      // Ignore
    }
  };

  const handleToggleHydra = (enabled: boolean) => {
    setHydraEnabled(enabled);
  };

  const handleDeletePair = (id: string) => {
    const next = pairs.filter((p) => p.id !== id);
    setPairs(next);
    saveState({ pairs: next });
  };

  const handleAddRecipe = (recipe: CookbookRecipe) => {
    const newPair: HydraPairConfig = {
      id: `pair-${Date.now()}`,
      name: recipe.title,
      leadProvider: recipe.leadProvider,
      leadModel: recipe.leadModel,
      leadEffort: recipe.leadEffort,
      headsProvider: recipe.headsProvider,
      headsModel: recipe.headsModel,
      headsEffort: recipe.headsEffort,
      maxHeads: recipe.maxHeads ?? 3,
    };
    const next = [newPair, ...pairs];
    setPairs(next);
    saveState({ pairs: next });
    setIsCookbookOpen(false);
  };

  const handleSavePair = (pair: HydraPairConfig) => {
    let next: HydraPairConfig[];
    if (pairs.some((p) => p.id === pair.id)) {
      next = pairs.map((p) => (p.id === pair.id ? pair : p));
    } else {
      next = [pair, ...pairs];
    }
    setPairs(next);
    saveState({ pairs: next });
    setEditingPair(null);
    setIsAddingPair(false);
  };

  return (
    <SettingsPageContainer className="pb-24 max-w-4xl space-y-6">
      {/* Back + Breadcrumb */}
      <div className="flex items-center gap-1.5">
        <button
          onClick={() => navigate({ to: "/settings", replace: true })}
          className="flex size-7 items-center justify-center rounded-md text-foreground/60 hover:bg-white/[0.06] hover:text-foreground transition-colors"
          aria-label="Back to settings"
        >
          <ArrowLeftIcon className="size-3.5" />
        </button>
        <SettingsBreadcrumb pathname="/settings/hydra" />
      </div>

      {/* Top Banner / Hydra Master Switch Card */}
      <div className="rounded-2xl border border-white/[0.08] bg-[#1c1c1e]/60 p-4 sm:p-5 flex items-center justify-between gap-4 shadow-xs">
        <div className="flex items-center gap-4 min-w-0">
          {/* Overlapping 5 dragon heads avatar stack */}
          <div className="flex items-center -space-x-2.5 shrink-0" aria-hidden="true">
            {ROSTER_COLORS.map((color, i) => (
              <div
                key={color}
                style={{ backgroundColor: color }}
                className="size-7 rounded-full flex items-center justify-center text-white ring-2 ring-[#1c1c1e] shadow-xs"
              >
                <HydraMarkSvg className="size-4" />
              </div>
            ))}
          </div>

          <div className="min-w-0">
            <div className="flex items-center gap-1.5">
              <h2 className="text-[15px] font-semibold text-foreground">Hydra</h2>
              <button
                type="button"
                className="text-muted-foreground/60 hover:text-foreground transition-colors"
                aria-label="How Hydra works"
              >
                <InfoIcon className="size-3.5" />
              </button>
            </div>
            <p className="text-xs text-muted-foreground mt-0.5 truncate">
              One chat leads a team of heads on big jobs.
            </p>
          </div>
        </div>

        <Switch
          checked={hydraEnabled}
          onCheckedChange={handleToggleHydra}
          aria-label="Enable Hydra"
        />
      </div>

      {!hydraEnabled ? (
        <p className="text-xs text-muted-foreground px-1">
          Switch Hydra on to set up its heads.
        </p>
      ) : null}

      {/* Subordinate sections — dimmed when Hydra is off */}
      <div
        className={`space-y-6 transition-opacity duration-200 ${
          hydraEnabled ? "opacity-100" : "opacity-40 pointer-events-none"
        }`}
      >
        {/* Section: Heads */}
        <div className="space-y-2">
          <div className="flex items-center gap-1.5 px-0.5">
            <h3 className="text-sm font-semibold tracking-tight text-foreground">Heads</h3>
            <button
              type="button"
              className="text-muted-foreground/60 hover:text-foreground transition-colors"
              aria-label="How heads work"
            >
              <InfoIcon className="size-3.5" />
            </button>
          </div>

          <div className="rounded-2xl border border-white/[0.08] bg-[#1c1c1e]/60 divide-y divide-white/[0.06] shadow-xs overflow-hidden">
            {/* Checkout */}
            <div className="p-4 flex items-center justify-between gap-4">
              <div className="min-w-0 flex-1">
                <div className="text-xs font-semibold text-foreground">Checkout</div>
                <div className="text-xs text-muted-foreground mt-0.5 leading-relaxed">
                  {isolateHeads
                    ? "Each head works in a copy of its own; its changes land in the chat's checkout when it reports."
                    : "Heads work in the chat's checkout itself."}
                </div>
              </div>

              <div className="inline-flex rounded-lg bg-white/[0.06] p-0.5 shrink-0 border border-white/10">
                <button
                  type="button"
                  onClick={() => setIsolateHeads(true)}
                  className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-md text-xs font-medium transition-colors cursor-pointer ${
                    isolateHeads
                      ? "bg-[#af52de] text-white shadow-xs"
                      : "text-muted-foreground hover:text-foreground"
                  }`}
                >
                  <FileTextIcon className="size-3.5" />
                  <span>Own copy</span>
                </button>
                <button
                  type="button"
                  onClick={() => setIsolateHeads(false)}
                  className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-md text-xs font-medium transition-colors cursor-pointer ${
                    !isolateHeads
                      ? "bg-[#af52de] text-white shadow-xs"
                      : "text-muted-foreground hover:text-foreground"
                  }`}
                >
                  <FolderIcon className="size-3.5" />
                  <span>Shared</span>
                </button>
              </div>
            </div>

            {/* Heads at once */}
            <div className="p-4 flex items-center justify-between gap-4">
              <div className="min-w-0 flex-1">
                <div className="text-xs font-semibold text-foreground">Heads at once</div>
                <div className="text-xs text-muted-foreground mt-0.5 leading-relaxed">
                  {maxHeads
                    ? `At most ${maxHeads} heads in parallel.`
                    : "As many heads as the job needs."}
                </div>
              </div>

              <div className="inline-flex rounded-lg bg-white/[0.06] p-0.5 shrink-0 border border-white/10 text-xs">
                {[null, 2, 3, 4, 5, 8].map((cap) => (
                  <button
                    key={cap ?? "none"}
                    type="button"
                    onClick={() => setMaxHeads(cap)}
                    className={`px-2.5 py-1 rounded-md font-medium transition-colors cursor-pointer ${
                      maxHeads === cap
                        ? "bg-[#af52de] text-white shadow-xs"
                        : "text-muted-foreground hover:text-foreground"
                    }`}
                  >
                    {cap === null ? "∞" : cap}
                  </button>
                ))}
              </div>
            </div>

            {/* Clear finished heads */}
            <div className="p-4 flex items-center justify-between gap-4">
              <div className="min-w-0 flex-1">
                <div className="text-xs font-semibold text-foreground">Clear finished heads</div>
                <div className="text-xs text-muted-foreground mt-0.5 leading-relaxed">
                  A finished head moves from the panel to the sidebar.
                </div>
              </div>
              <Switch
                checked={autoClearFinished}
                onCheckedChange={setAutoClearFinished}
                aria-label="Clear finished heads"
              />
            </div>

            {/* Auto-hide heads in sidebar */}
            <div className="p-4 flex items-center justify-between gap-4">
              <div className="min-w-0 flex-1">
                <div className="text-xs font-semibold text-foreground">
                  Auto-hide heads in the sidebar
                </div>
                <div className="text-xs text-muted-foreground mt-0.5 leading-relaxed">
                  A chat's heads show in the sidebar while one of them runs; the whole card leaves
                  once every head of that chat has finished.
                </div>
              </div>
              <Switch
                checked={autoHidesIdleHeads}
                onCheckedChange={setAutoHidesIdleHeads}
                aria-label="Auto-hide heads in the sidebar"
              />
            </div>

            {/* Head panel */}
            <div className="p-4 flex items-center justify-between gap-4">
              <div className="min-w-0 flex-1">
                <div className="text-xs font-semibold text-foreground">Head panel</div>
                <div className="text-xs text-muted-foreground mt-0.5 leading-relaxed">
                  The head's progress bar, or each of its steps as it goes.
                </div>
              </div>

              <div className="inline-flex rounded-lg bg-white/[0.06] p-0.5 shrink-0 border border-white/10">
                <button
                  type="button"
                  onClick={() => setShowsHeadDetails(false)}
                  className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-md text-xs font-medium transition-colors cursor-pointer ${
                    !showsHeadDetails
                      ? "bg-[#af52de] text-white shadow-xs"
                      : "text-muted-foreground hover:text-foreground"
                  }`}
                >
                  <BarChart2Icon className="size-3.5" />
                  <span>Progress</span>
                </button>
                <button
                  type="button"
                  onClick={() => setShowsHeadDetails(true)}
                  className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-md text-xs font-medium transition-colors cursor-pointer ${
                    showsHeadDetails
                      ? "bg-[#af52de] text-white shadow-xs"
                      : "text-muted-foreground hover:text-foreground"
                  }`}
                >
                  <ListOrderedIcon className="size-3.5" />
                  <span>Every step</span>
                </button>
              </div>
            </div>

            {/* Heads' panels */}
            <div className="p-4 flex items-center justify-between gap-4">
              <div className="min-w-0 flex-1">
                <div className="text-xs font-semibold text-foreground">Heads' panels</div>
                <div className="text-xs text-muted-foreground mt-0.5 leading-relaxed">
                  {autoPopsHeads
                    ? "Each head after the first gets a panel of its own beside the chat while there is room."
                    : "One panel over the chat lists every head."}
                </div>
              </div>

              <div className="inline-flex rounded-lg bg-white/[0.06] p-0.5 shrink-0 border border-white/10">
                <button
                  type="button"
                  onClick={() => setAutoPopsHeads(false)}
                  className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-md text-xs font-medium transition-colors cursor-pointer ${
                    !autoPopsHeads
                      ? "bg-[#af52de] text-white shadow-xs"
                      : "text-muted-foreground hover:text-foreground"
                  }`}
                >
                  <LayersIcon className="size-3.5" />
                  <span>One panel</span>
                </button>
                <button
                  type="button"
                  onClick={() => setAutoPopsHeads(true)}
                  className={`inline-flex items-center gap-1.5 px-3 py-1 rounded-md text-xs font-medium transition-colors cursor-pointer ${
                    autoPopsHeads
                      ? "bg-[#af52de] text-white shadow-xs"
                      : "text-muted-foreground hover:text-foreground"
                  }`}
                >
                  <LayoutGridIcon className="size-3.5" />
                  <span>A panel each</span>
                </button>
              </div>
            </div>

            {/* Heads work at a working effort */}
            <div className="p-4 flex items-center justify-between gap-4">
              <div className="min-w-0 flex-1">
                <div className="text-xs font-semibold text-foreground">
                  Heads work at a working effort
                </div>
                <div className="text-xs text-muted-foreground mt-0.5 leading-relaxed">
                  A lead thinking above medium sends its heads out at medium on the same model.
                </div>
              </div>
              <Switch
                checked={tempersHeadEffort}
                onCheckedChange={setTempersHeadEffort}
                aria-label="Heads work at a working effort"
              />
            </div>
          </div>
        </div>

        {/* Section: Messages */}
        <div className="space-y-2">
          <h3 className="text-sm font-semibold tracking-tight text-foreground px-0.5">Messages</h3>
          <div className="rounded-2xl border border-white/[0.08] bg-[#1c1c1e]/60 divide-y divide-white/[0.06] shadow-xs overflow-hidden">
            <div className="p-4 flex items-center justify-between gap-4">
              <div className="min-w-0 flex-1">
                <div className="text-xs font-semibold text-foreground">
                  Queued follow-ups start on heads
                </div>
                <div className="text-xs text-muted-foreground mt-0.5 leading-relaxed">
                  A prompt queued behind a running turn goes out at once.
                </div>
              </div>
              <Switch
                checked={queueHeads}
                onCheckedChange={setQueueHeads}
                aria-label="Queued follow-ups start on heads"
              />
            </div>

            <div className="p-4 flex items-center justify-between gap-4">
              <div className="min-w-0 flex-1">
                <div className="text-xs font-semibold text-foreground">
                  Every message goes to a head
                </div>
                <div className="text-xs text-muted-foreground mt-0.5 leading-relaxed">
                  The lead only hears the reports.
                </div>
              </div>
              <Switch
                checked={alwaysHeads}
                onCheckedChange={setAlwaysHeads}
                aria-label="Every message goes to a head"
              />
            </div>
          </div>
        </div>

        {/* Section: When the team is done */}
        <div className="space-y-2">
          <h3 className="text-sm font-semibold tracking-tight text-foreground px-0.5">
            When the team is done
          </h3>
          <div className="rounded-2xl border border-white/[0.08] bg-[#1c1c1e]/60 divide-y divide-white/[0.06] shadow-xs overflow-hidden">
            <div className="p-4 flex items-center justify-between gap-4">
              <div className="min-w-0 flex-1">
                <div className="text-xs font-semibold text-foreground">
                  Lead checks the heads' work
                </div>
                <div className="text-xs text-muted-foreground mt-0.5 leading-relaxed">
                  Reads every changed file and corrects it. Slower, more careful.
                </div>
              </div>
              <Switch
                checked={reviewHeads}
                onCheckedChange={setReviewHeads}
                aria-label="Lead checks the heads' work"
              />
            </div>

            <div className="p-4 flex items-center justify-between gap-4">
              <div className="min-w-0 flex-1">
                <div className="text-xs font-semibold text-foreground">Merge automatically</div>
                <div className="text-xs text-muted-foreground mt-0.5 leading-relaxed">
                  The team's changes go out as a merge request and are merged.
                </div>
              </div>
              <Switch
                checked={autoMerge}
                onCheckedChange={setAutoMerge}
                aria-label="Merge automatically"
              />
            </div>
          </div>
        </div>

        {/* Section: Pairs */}
        <div className="space-y-2">
          <div className="flex items-center justify-between px-0.5">
            <h3 className="text-sm font-semibold tracking-tight text-foreground">Pairs</h3>
            <button
              type="button"
              onClick={() => setIsCookbookOpen(true)}
              className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold bg-white/[0.08] hover:bg-white/[0.12] text-foreground transition-colors cursor-pointer"
            >
              <BookOpenIcon className="size-3.5 text-[#af52de]" />
              <span>Open cookbook</span>
            </button>
          </div>

          {/* Explainer card */}
          <div className="rounded-2xl border border-white/[0.08] bg-[#1c1c1e]/60 p-4 sm:p-5 flex items-start gap-3.5 shadow-xs">
            <div className="flex items-center gap-1.5 pt-0.5 shrink-0" aria-hidden="true">
              <div className="size-7 rounded-full bg-[#FF8A3D] flex items-center justify-center text-white shadow-xs">
                <HydraMarkSvg className="size-4" />
              </div>
              <ArrowRightIcon className="size-3 text-muted-foreground" />
              <div className="flex -space-x-1.5">
                <div className="size-5 rounded-full bg-[#3D8BFF] flex items-center justify-center text-white shadow-xs">
                  <HydraMarkSvg className="size-3" />
                </div>
                <div className="size-5 rounded-full bg-[#34C46A] flex items-center justify-center text-white shadow-xs">
                  <HydraMarkSvg className="size-3" />
                </div>
                <div className="size-5 rounded-full bg-[#A35BE0] flex items-center justify-center text-white shadow-xs">
                  <HydraMarkSvg className="size-3" />
                </div>
              </div>
            </div>

            <div className="min-w-0 flex-1 space-y-1">
              <h4 className="text-[13px] font-semibold text-foreground">One leads, the others build</h4>
              <p className="text-xs text-muted-foreground leading-relaxed">
                A pair says which model leads and which runs the heads. Put a deep thinker over
                quick hands on one provider, or lead on one provider and send the heads out on
                another: the strongest lead with the fastest team, every time.
              </p>
            </div>
          </div>

          {/* Configured Pairs list card */}
          <div className="rounded-2xl border border-white/[0.08] bg-[#1c1c1e]/60 divide-y divide-white/[0.06] shadow-xs overflow-hidden">
            {pairs.map((pair) => (
              <div
                key={pair.id}
                className="p-4 flex items-center justify-between gap-4 hover:bg-white/[0.02] transition-colors"
              >
                <div className="flex items-center gap-3 min-w-0">
                  <div className="flex items-center gap-1 text-muted-foreground shrink-0">
                    <ProviderMiniIcon provider={pair.leadProvider} />
                    <ArrowRightIcon className="size-2.5 text-muted-foreground/60" />
                    <ProviderMiniIcon provider={pair.headsProvider} />
                  </div>

                  <div className="min-w-0">
                    <div className="text-[13px] font-semibold text-foreground truncate">
                      {pair.name || `${pair.leadModel} → ${pair.headsModel}`}
                    </div>
                    <div className="text-[11px] text-muted-foreground truncate mt-0.5">
                      {pair.leadProvider} · {pair.leadModel} leading {pair.headsModel}
                      {pair.leadEffort ? ` · ${pair.leadEffort} → ${pair.headsEffort ?? "medium"}` : ""}
                      {pair.maxHeads ? ` · Up to ${pair.maxHeads} heads` : ""}
                    </div>
                  </div>
                </div>

                <div className="flex items-center gap-1.5 shrink-0">
                  <button
                    type="button"
                    onClick={() => setEditingPair(pair)}
                    className="p-1.5 rounded-lg text-muted-foreground hover:text-foreground hover:bg-white/[0.06] transition-colors cursor-pointer"
                    aria-label="Edit pair"
                  >
                    <SlidersHorizontalIcon className="size-3.5" />
                  </button>
                  <button
                    type="button"
                    onClick={() => handleDeletePair(pair.id)}
                    className="p-1.5 rounded-lg text-muted-foreground hover:text-red-400 hover:bg-red-500/10 transition-colors cursor-pointer"
                    aria-label="Remove pair"
                  >
                    <MinusCircleIcon className="size-3.5" />
                  </button>
                </div>
              </div>
            ))}

            <div className="p-3.5 px-4 flex items-center justify-between">
              <button
                type="button"
                onClick={() => setIsAddingPair(true)}
                className="inline-flex items-center gap-2 text-xs font-semibold text-foreground hover:text-[#af52de] transition-colors cursor-pointer"
              >
                <span className="size-4.5 rounded-full border border-white/40 flex items-center justify-center text-xs font-bold leading-none">
                  +
                </span>
                <span>Add pair</span>
              </button>
            </div>
          </div>

          <p className="text-xs text-muted-foreground px-1 leading-relaxed">
            Pairs sit at the top of the model picker: a tap puts the chat in one. Right-click a
            project in the sidebar to start each of its new chats on one pair.
          </p>
        </div>

        {/* Section: Where heads run */}
        <div className="space-y-2">
          <h3 className="text-sm font-semibold tracking-tight text-foreground px-0.5">
            Where heads run
          </h3>
          <div className="rounded-2xl border border-white/[0.08] bg-[#1c1c1e]/60 divide-y divide-white/[0.06] shadow-xs overflow-hidden">
            <div className="p-4 flex items-center justify-between gap-4">
              <div className="min-w-0 flex-1">
                <div className="text-xs font-semibold text-foreground">Claude, Codex and Copilot</div>
                <div className="text-xs text-muted-foreground mt-0.5 leading-relaxed">
                  In the provider's own session, through the lead's own agent tools.
                </div>
              </div>
              <div className="flex items-center gap-2 text-muted-foreground shrink-0">
                <ClaudeAI className="size-4" />
                <OpenAI className="size-4" />
                <GithubCopilotIcon className="size-4.5" />
              </div>
            </div>

            <div className="p-4 flex items-center justify-between gap-4">
              <div className="min-w-0 flex-1">
                <div className="text-xs font-semibold text-foreground">Other providers</div>
                <div className="text-xs text-muted-foreground mt-0.5 leading-relaxed">
                  As threads of their own, asked for at the end of the lead's reply.
                </div>
              </div>
            </div>

            <div className="p-4 flex items-center justify-between gap-4">
              <div className="min-w-0 flex-1">
                <div className="text-xs font-semibold text-foreground">Across providers</div>
                <div className="text-xs text-muted-foreground mt-0.5 leading-relaxed">
                  A pair can lead on one provider and run its heads on another.
                </div>
              </div>
              <div className="flex items-center gap-1.5 text-muted-foreground shrink-0">
                <ClaudeAI className="size-4" />
                <ArrowRightIcon className="size-3 text-muted-foreground/60" />
                <AntigravityIcon className="size-4" />
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Cookbook Modal */}
      {isCookbookOpen ? (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 animate-in fade-in duration-150">
          <div className="w-full max-w-lg rounded-2xl border border-white/[0.12] bg-[#1c1c1e] p-6 shadow-2xl space-y-4 max-h-[85vh] flex flex-col">
            <div className="flex items-center justify-between pb-1 border-b border-white/[0.08]">
              <div>
                <h3 className="text-base font-semibold text-foreground">Hydra Cookbook</h3>
                <p className="text-xs text-muted-foreground mt-0.5">
                  Pairs built from the models in your library. Add one to use it immediately.
                </p>
              </div>
              <button
                type="button"
                onClick={() => setIsCookbookOpen(false)}
                className="p-1.5 rounded-lg text-muted-foreground hover:text-foreground hover:bg-white/[0.06]"
              >
                <XIcon className="size-4" />
              </button>
            </div>

            <div className="space-y-3 overflow-y-auto pr-1 flex-1">
              {COOKBOOK_RECIPES.map((recipe) => {
                const isAdded = pairs.some(
                  (p) =>
                    p.leadModel === recipe.leadModel && p.headsModel === recipe.headsModel,
                );
                return (
                  <div
                    key={recipe.id}
                    className="p-3.5 rounded-xl border border-white/[0.06] bg-white/[0.03] hover:bg-white/[0.05] transition-colors flex items-start justify-between gap-3"
                  >
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2">
                        <span className="text-[13px] font-semibold text-foreground">
                          {recipe.title}
                        </span>
                      </div>
                      <p className="text-xs text-muted-foreground leading-relaxed mt-1">
                        {recipe.tagline}
                      </p>
                      <div className="text-[11px] font-mono text-muted-foreground/70 mt-2">
                        {recipe.leadProvider} → {recipe.headsProvider}
                        {recipe.maxHeads ? ` · ${recipe.maxHeads} heads` : ""}
                      </div>
                    </div>

                    <button
                      type="button"
                      disabled={isAdded}
                      onClick={() => handleAddRecipe(recipe)}
                      className={`px-3 py-1 rounded-full text-xs font-semibold shrink-0 transition-colors cursor-pointer ${
                        isAdded
                          ? "bg-white/[0.08] text-muted-foreground"
                          : "bg-[#af52de] hover:bg-[#9d3ed0] text-white shadow-xs"
                      }`}
                    >
                      {isAdded ? "Added" : "Add pair"}
                    </button>
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      ) : null}

      {/* Add / Edit Pair Modal */}
      {isAddingPair || editingPair ? (
        <PairEditorModal
          initial={editingPair}
          onClose={() => {
            setIsAddingPair(false);
            setEditingPair(null);
          }}
          onSave={handleSavePair}
        />
      ) : null}
    </SettingsPageContainer>
  );
}

function ProviderMiniIcon({ provider }: { provider: string }) {
  const norm = provider.toLowerCase();
  if (norm.includes("claude")) return <ClaudeAI className="size-3.5" />;
  if (norm.includes("codex") || norm.includes("openai")) return <OpenAI className="size-3.5" />;
  if (norm.includes("copilot")) return <GithubCopilotIcon className="size-4" />;
  if (norm.includes("antigravity") || norm.includes("gemini"))
    return <AntigravityIcon className="size-3.5" />;
  return <div className="size-3.5 rounded-full bg-white/20" />;
}

function PairEditorModal({
  initial,
  onClose,
  onSave,
}: {
  initial: HydraPairConfig | null;
  onClose: () => void;
  onSave: (pair: HydraPairConfig) => void;
}) {
  const [name, setName] = useState(initial?.name ?? "");
  const [leadProvider, setLeadProvider] = useState(initial?.leadProvider ?? "Claude");
  const [leadModel, setLeadModel] = useState(initial?.leadModel ?? "Opus 5");
  const [leadEffort, setLeadEffort] = useState(initial?.leadEffort ?? "high");
  const [headsProvider, setHeadsProvider] = useState(initial?.headsProvider ?? "Claude");
  const [headsModel, setHeadsModel] = useState(initial?.headsModel ?? "Sonnet 3.5");
  const [headsEffort, setHeadsEffort] = useState(initial?.headsEffort ?? "medium");
  const [maxHeads, setMaxHeads] = useState<number>(initial?.maxHeads ?? 3);

  const handleSubmit = () => {
    onSave({
      id: initial?.id ?? `pair-${Date.now()}`,
      name: name.trim() || `${leadModel} → ${headsModel}`,
      leadProvider,
      leadModel,
      leadEffort,
      headsProvider,
      headsModel,
      headsEffort,
      maxHeads: maxHeads || null,
    });
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4 animate-in fade-in duration-150">
      <div className="w-full max-w-md rounded-2xl border border-white/[0.12] bg-[#1c1c1e] p-6 shadow-2xl space-y-4">
        <div className="flex items-center justify-between pb-1 border-b border-white/[0.08]">
          <h3 className="text-base font-semibold text-foreground">
            {initial ? "Edit Pair" : "Add Hydra Pair"}
          </h3>
          <button
            type="button"
            onClick={onClose}
            className="p-1.5 rounded-lg text-muted-foreground hover:text-foreground hover:bg-white/[0.06]"
          >
            <XIcon className="size-4" />
          </button>
        </div>

        <div className="space-y-3.5 text-xs">
          <div>
            <label className="block font-medium text-foreground mb-1">Pair Name (optional)</label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. Deep Thinker & Fast Coder"
              className="w-full rounded-xl border border-white/10 bg-white/[0.04] px-3 py-2 text-foreground focus:outline-none focus:ring-1 focus:ring-[#af52de]"
            />
          </div>

          <div className="p-3 rounded-xl border border-white/[0.06] bg-white/[0.02] space-y-2.5">
            <div className="font-semibold text-foreground flex items-center gap-1.5">
              <span>Lead (Orchestrator)</span>
            </div>
            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className="block text-[11px] text-muted-foreground mb-1">Provider</label>
                <select
                  value={leadProvider}
                  onChange={(e) => setLeadProvider(e.target.value)}
                  className="w-full rounded-lg border border-white/10 bg-white/[0.06] px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-[#af52de]"
                >
                  <option value="Claude" className="bg-[#1c1c1e]">Claude</option>
                  <option value="Codex" className="bg-[#1c1c1e]">Codex</option>
                  <option value="Antigravity" className="bg-[#1c1c1e]">Antigravity</option>
                  <option value="Copilot" className="bg-[#1c1c1e]">Copilot</option>
                </select>
              </div>
              <div>
                <label className="block text-[11px] text-muted-foreground mb-1">Model</label>
                <input
                  type="text"
                  value={leadModel}
                  onChange={(e) => setLeadModel(e.target.value)}
                  className="w-full rounded-lg border border-white/10 bg-white/[0.06] px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-[#af52de]"
                />
              </div>
            </div>
            <div>
              <label className="block text-[11px] text-muted-foreground mb-1">Thinking Effort</label>
              <div className="flex gap-1">
                {["low", "medium", "high", "max"].map((effort) => (
                  <button
                    key={effort}
                    type="button"
                    onClick={() => setLeadEffort(effort)}
                    className={`flex-1 py-1 rounded-md text-[11px] font-medium capitalize transition-colors ${
                      leadEffort === effort
                        ? "bg-[#af52de] text-white"
                        : "bg-white/[0.05] text-muted-foreground hover:text-foreground"
                    }`}
                  >
                    {effort}
                  </button>
                ))}
              </div>
            </div>
          </div>

          <div className="p-3 rounded-xl border border-white/[0.06] bg-white/[0.02] space-y-2.5">
            <div className="font-semibold text-foreground flex items-center gap-1.5">
              <span>Heads (Builders)</span>
            </div>
            <div className="grid grid-cols-2 gap-2">
              <div>
                <label className="block text-[11px] text-muted-foreground mb-1">Provider</label>
                <select
                  value={headsProvider}
                  onChange={(e) => setHeadsProvider(e.target.value)}
                  className="w-full rounded-lg border border-white/10 bg-white/[0.06] px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-[#af52de]"
                >
                  <option value="Claude" className="bg-[#1c1c1e]">Claude</option>
                  <option value="Codex" className="bg-[#1c1c1e]">Codex</option>
                  <option value="Antigravity" className="bg-[#1c1c1e]">Antigravity</option>
                  <option value="DeepSeek" className="bg-[#1c1c1e]">DeepSeek</option>
                </select>
              </div>
              <div>
                <label className="block text-[11px] text-muted-foreground mb-1">Model</label>
                <input
                  type="text"
                  value={headsModel}
                  onChange={(e) => setHeadsModel(e.target.value)}
                  className="w-full rounded-lg border border-white/10 bg-white/[0.06] px-2.5 py-1.5 text-foreground focus:outline-none focus:ring-1 focus:ring-[#af52de]"
                />
              </div>
            </div>
            <div className="flex items-center justify-between gap-2 pt-1">
              <span className="text-[11px] text-muted-foreground">Parallel heads cap:</span>
              <div className="flex gap-1">
                {[1, 2, 3, 4, 6].map((num) => (
                  <button
                    key={num}
                    type="button"
                    onClick={() => setMaxHeads(num)}
                    className={`size-6 rounded-md text-[11px] font-medium transition-colors ${
                      maxHeads === num
                        ? "bg-[#af52de] text-white"
                        : "bg-white/[0.05] text-muted-foreground hover:text-foreground"
                    }`}
                  >
                    {num}
                  </button>
                ))}
              </div>
            </div>
          </div>
        </div>

        <div className="flex justify-end gap-2 pt-2 border-t border-white/[0.08]">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-1.5 text-xs text-muted-foreground hover:text-foreground"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={handleSubmit}
            className="rounded-full bg-[#af52de] hover:bg-[#9d3ed0] text-white px-5 py-1.5 text-xs font-semibold shadow-xs transition-colors cursor-pointer"
          >
            Save Pair
          </button>
        </div>
      </div>
    </div>
  );
}
