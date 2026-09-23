import {
  useState,
  useMemo,
  useCallback,
  type ReactElement,
} from "react";
import {
  ArrowLeftIcon,
  GripVerticalIcon,
  MinusCircleIcon,
  PlusCircleIcon,
  CheckCircle2Icon,
  SearchIcon,
  ZapIcon,
  BotIcon,
  ChevronDownIcon,
} from "lucide-react";
import { useNavigate } from "@tanstack/react-router";
import { cn } from "~/lib/utils";
import { Input } from "../ui/input";
import { Button } from "../ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "../ui/popover";
import { SettingsPageContainer } from "./settingsLayout";
import { SettingsBreadcrumb } from "./SettingsBreadcrumb";

export interface PinnedModel {
  id: string;
  modelId: string;
  provider: string;
  name: string;
  shortName: string;
  description: string;
  effort?: "none" | "low" | "medium" | "high" | "max" | undefined;
  fastMode?: boolean | undefined;
}

export interface CatalogModel {
  id: string;
  provider: string;
  providerName: string;
  name: string;
  shortName: string;
  description: string;
  supportsFast: boolean;
  efforts: Array<"none" | "low" | "medium" | "high" | "max">;
  defaultEffort?: "none" | "low" | "medium" | "high" | "max";
}

const DEFAULT_PINNED_MODELS: PinnedModel[] = [
  {
    id: "anthropic/claude-3-7-sonnet",
    modelId: "claude-3-7-sonnet-20250219",
    provider: "Anthropic",
    name: "Claude 3.7 Sonnet",
    shortName: "Claude 3.7 Sonnet",
    description: "Hybrid reasoning and agentic coding",
    effort: "max",
    fastMode: false,
  },
  {
    id: "anthropic/claude-3-5-sonnet",
    modelId: "claude-3-5-sonnet-20241022",
    provider: "Anthropic",
    name: "Claude 3.5 Sonnet",
    shortName: "Claude 3.5 Sonnet",
    description: "High-intelligence workhorse for complex tasks",
    effort: "high",
    fastMode: false,
  },
  {
    id: "google/gemini-2-5-pro",
    modelId: "gemini-2.5-pro",
    provider: "Google Antigravity",
    name: "Gemini 2.5 Pro",
    shortName: "Gemini 2.5 Pro",
    description: "Advanced reasoning with large context window",
    effort: "high",
    fastMode: false,
  },
  {
    id: "google/gemini-2-5-flash",
    modelId: "gemini-2.5-flash",
    provider: "Google Antigravity",
    name: "Gemini 2.5 Flash",
    shortName: "Gemini 2.5 Flash",
    description: "Ultra-fast response with high coding accuracy",
    effort: "medium",
    fastMode: true,
  },
  {
    id: "openai/o3-mini",
    modelId: "o3-mini",
    provider: "OpenAI Codex",
    name: "o3-mini",
    shortName: "o3-mini",
    description: "Fast reasoning model optimized for math and code",
    effort: "high",
    fastMode: false,
  },
  {
    id: "openai/gpt-4o",
    modelId: "gpt-4o",
    provider: "OpenAI Codex",
    name: "GPT-4o",
    shortName: "GPT-4o",
    description: "Omni-modal model with broad world knowledge",
    effort: "none",
    fastMode: true,
  },
  {
    id: "deepseek/deepseek-r1",
    modelId: "deepseek-r1",
    provider: "DeepSeek",
    name: "DeepSeek R1",
    shortName: "DeepSeek R1",
    description: "Open reasoning model with competitive benchmark performance",
    effort: "max",
    fastMode: false,
  },
];

const CATALOG_MODELS: CatalogModel[] = [
  // Anthropic
  {
    id: "claude-3-7-sonnet-20250219",
    provider: "Anthropic",
    providerName: "Anthropic",
    name: "Claude 3.7 Sonnet",
    shortName: "Claude 3.7 Sonnet",
    description: "Hybrid reasoning and coding model with controllable thinking tokens",
    supportsFast: true,
    efforts: ["low", "medium", "high", "max"],
    defaultEffort: "high",
  },
  {
    id: "claude-3-5-sonnet-20241022",
    provider: "Anthropic",
    providerName: "Anthropic",
    name: "Claude 3.5 Sonnet",
    shortName: "Claude 3.5 Sonnet",
    description: "High-intelligence model with state-of-the-art coding and agentic performance",
    supportsFast: false,
    efforts: ["none"],
  },
  {
    id: "claude-3-5-haiku-20241022",
    provider: "Anthropic",
    providerName: "Anthropic",
    name: "Claude 3.5 Haiku",
    shortName: "Claude 3.5 Haiku",
    description: "Fastest Claude model for sub-agent tasks and lightweight completions",
    supportsFast: true,
    efforts: ["none"],
  },
  {
    id: "claude-3-opus-20240229",
    provider: "Anthropic",
    providerName: "Anthropic",
    name: "Claude 3 Opus",
    shortName: "Claude 3 Opus",
    description: "Deep reasoning model for high-ambiguity research and creative architecture",
    supportsFast: false,
    efforts: ["none"],
  },
  // Google Antigravity
  {
    id: "gemini-2.5-pro",
    provider: "Google Antigravity",
    providerName: "Google Antigravity",
    name: "Gemini 2.5 Pro",
    shortName: "Gemini 2.5 Pro",
    description: "State-of-the-art coding and reasoning with 1M+ context window",
    supportsFast: true,
    efforts: ["low", "medium", "high", "max"],
    defaultEffort: "high",
  },
  {
    id: "gemini-2.5-flash",
    provider: "Google Antigravity",
    providerName: "Google Antigravity",
    name: "Gemini 2.5 Flash",
    shortName: "Gemini 2.5 Flash",
    description: "Near-instant responses with high code synthesis capability",
    supportsFast: true,
    efforts: ["low", "medium", "high"],
    defaultEffort: "medium",
  },
  {
    id: "gemini-2.0-flash-thinking",
    provider: "Google Antigravity",
    providerName: "Google Antigravity",
    name: "Gemini 2.0 Flash Thinking",
    shortName: "Gemini 2.0 Flash Thinking",
    description: "Visible thought trace with quick execution turn-around",
    supportsFast: false,
    efforts: ["low", "medium", "high"],
    defaultEffort: "medium",
  },
  // OpenAI Codex
  {
    id: "o3-mini",
    provider: "OpenAI Codex",
    providerName: "OpenAI Codex",
    name: "o3-mini",
    shortName: "o3-mini",
    description: "Compact reasoning model designed for high-throughput coding tasks",
    supportsFast: false,
    efforts: ["low", "medium", "high"],
    defaultEffort: "medium",
  },
  {
    id: "o1",
    provider: "OpenAI Codex",
    providerName: "OpenAI Codex",
    name: "o1",
    shortName: "o1",
    description: "Full-scale reasoning model for deep algorithm design and complex proofs",
    supportsFast: false,
    efforts: ["low", "medium", "high"],
    defaultEffort: "high",
  },
  {
    id: "gpt-4o",
    provider: "OpenAI Codex",
    providerName: "OpenAI Codex",
    name: "GPT-4o",
    shortName: "GPT-4o",
    description: "Fast multi-modal flagship model with strong code tool use",
    supportsFast: true,
    efforts: ["none"],
  },
  {
    id: "gpt-4o-mini",
    provider: "OpenAI Codex",
    providerName: "OpenAI Codex",
    name: "GPT-4o mini",
    shortName: "GPT-4o mini",
    description: "Lightweight and cost-effective model for routine tasks",
    supportsFast: true,
    efforts: ["none"],
  },
  // DeepSeek & OpenCode
  {
    id: "deepseek-r1",
    provider: "DeepSeek",
    providerName: "DeepSeek",
    name: "DeepSeek R1",
    shortName: "DeepSeek R1",
    description: "Open reasoning model with emergent reinforcement learning reasoning",
    supportsFast: false,
    efforts: ["medium", "high", "max"],
    defaultEffort: "high",
  },
  {
    id: "deepseek-v3",
    provider: "DeepSeek",
    providerName: "DeepSeek",
    name: "DeepSeek V3",
    shortName: "DeepSeek V3",
    description: "671B parameter Mixture-of-Experts model for general programming",
    supportsFast: true,
    efforts: ["none"],
  },
];

const PINNED_STORAGE_KEY = "swarmcode:models:pinned:v1";

function loadPinnedModels(): PinnedModel[] {
  if (typeof window === "undefined") return DEFAULT_PINNED_MODELS;
  try {
    const raw = window.localStorage.getItem(PINNED_STORAGE_KEY);
    if (!raw) return DEFAULT_PINNED_MODELS;
    const parsed = JSON.parse(raw);
    if (Array.isArray(parsed) && parsed.length > 0) return parsed;
  } catch {
    // fallback
  }
  return DEFAULT_PINNED_MODELS;
}

function savePinnedModels(models: PinnedModel[]) {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.setItem(PINNED_STORAGE_KEY, JSON.stringify(models));
  } catch {
    // ignore
  }
}

export function ModelsSettingsPanel() {
  const navigate = useNavigate();
  const [pinned, setPinned] = useState<PinnedModel[]>(loadPinnedModels);
  const [query, setQuery] = useState("");
  const [draggedIndex, setDraggedIndex] = useState<number | null>(null);

  const persistPinned = useCallback((next: PinnedModel[]) => {
    setPinned(next);
    savePinnedModels(next);
  }, []);

  const trimmed = query.trim().toLowerCase();

  const filteredPinned = useMemo(() => {
    if (!trimmed) return pinned;
    return pinned.filter(
      (m) =>
        m.name.toLowerCase().includes(trimmed) ||
        m.shortName.toLowerCase().includes(trimmed) ||
        m.provider.toLowerCase().includes(trimmed) ||
        m.description.toLowerCase().includes(trimmed),
    );
  }, [pinned, trimmed]);

  const providerGroups = useMemo(() => {
    const groups = new Map<string, CatalogModel[]>();
    for (const model of CATALOG_MODELS) {
      if (
        trimmed &&
        !model.name.toLowerCase().includes(trimmed) &&
        !model.shortName.toLowerCase().includes(trimmed) &&
        !model.provider.toLowerCase().includes(trimmed) &&
        !model.description.toLowerCase().includes(trimmed)
      ) {
        continue;
      }
      const list = groups.get(model.provider) ?? [];
      list.push(model);
      groups.set(model.provider, list);
    }
    return Array.from(groups.entries());
  }, [trimmed]);

  const isPinned = useCallback(
    (modelId: string) => pinned.some((p) => p.modelId === modelId),
    [pinned],
  );

  const togglePin = useCallback(
    (catalog: CatalogModel) => {
      if (isPinned(catalog.id)) {
        persistPinned(pinned.filter((p) => p.modelId !== catalog.id));
      } else {
        if (pinned.length >= 30) return;
        const newPin: PinnedModel = {
          id: `${catalog.provider.toLowerCase()}/${catalog.id}`,
          modelId: catalog.id,
          provider: catalog.provider,
          name: catalog.name,
          shortName: catalog.shortName,
          description: catalog.description,
          effort: catalog.defaultEffort ?? (catalog.efforts[0] ?? "none"),
          fastMode: catalog.supportsFast,
        };
        persistPinned([...pinned, newPin]);
      }
    },
    [isPinned, pinned, persistPinned],
  );

  const handleDragStart = (index: number) => {
    setDraggedIndex(index);
  };

  const handleDragOver = (e: React.DragEvent, targetIndex: number) => {
    e.preventDefault();
    if (draggedIndex === null || draggedIndex === targetIndex) return;
    const reordered = [...pinned];
    const [moved] = reordered.splice(draggedIndex, 1);
    if (!moved) return;
    reordered.splice(targetIndex, 0, moved);
    setDraggedIndex(targetIndex);
    persistPinned(reordered);
  };

  const handleDragEnd = () => {
    setDraggedIndex(null);
  };

  const updateEffort = useCallback(
    (modelId: string, effort: PinnedModel["effort"]) => {
      persistPinned(
        pinned.map((p) => (p.modelId === modelId ? { ...p, effort } : p)),
      );
    },
    [pinned, persistPinned],
  );

  const toggleFastMode = useCallback(
    (modelId: string) => {
      persistPinned(
        pinned.map((p) =>
          p.modelId === modelId ? { ...p, fastMode: !p.fastMode } : p,
        ),
      );
    },
    [pinned, persistPinned],
  );

  return (
    <SettingsPageContainer>
      <div className="space-y-6">
        {/* Top Header & Search Capsule */}
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <div className="space-y-2.5">
            {/* Back + Breadcrumb row */}
            <div className="flex items-center gap-1.5">
              <button
                onClick={() => {
                  navigate({ to: "/settings", replace: true });
                }}
                className="flex size-7 items-center justify-center rounded-md text-foreground/60 hover:bg-white/[0.06] hover:text-foreground transition-colors"
                aria-label="Back to settings"
              >
                <ArrowLeftIcon className="size-3.5" />
              </button>
              <SettingsBreadcrumb pathname="/settings/models" />
            </div>
            <h2 className="text-xl font-semibold tracking-tight text-foreground pl-[9px]">
              Models
            </h2>
            <p className="text-xs text-muted-foreground mt-0.5 pl-[9px]">
              Chooses the models the composer's picker offers, and each one's effort and fast mode.
            </p>
          </div>

          <div className="relative w-full sm:w-64">
            <SearchIcon className="absolute left-3 top-1/2 size-3.5 -translate-y-1/2 text-muted-foreground/60" />
            <Input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search models..."
              className="h-8 pl-8 text-xs rounded-full bg-sidebar/50 border-white/10 focus-visible:ring-1 focus-visible:ring-accent"
            />
          </div>
        </div>

        {/* Your Models Section */}
        <div className="space-y-2">
          <div className="flex items-center justify-between">
            <h3 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              Your models
            </h3>
            <span className="text-[11px] text-muted-foreground">
              {pinned.length} of 30 pinned
            </span>
          </div>

          <div className="rounded-2xl border border-white/10 bg-card/60 backdrop-blur-md overflow-hidden divide-y divide-white/5 shadow-sm">
            {filteredPinned.length === 0 ? (
              <div className="p-8 text-center text-xs text-muted-foreground">
                No pinned models match "{query}". Add some from the providers below.
              </div>
            ) : (
              filteredPinned.map((model, idx) => (
                <div
                  key={model.id}
                  draggable
                  onDragStart={() => handleDragStart(idx)}
                  onDragOver={(e) => handleDragOver(e, idx)}
                  onDragEnd={handleDragEnd}
                  className={cn(
                    "flex items-center gap-3 px-4 py-3 transition-colors hover:bg-white/[0.03]",
                    draggedIndex === idx && "bg-white/[0.08] opacity-75",
                  )}
                >
                  <button
                    type="button"
                    aria-label="Drag to reorder"
                    className="cursor-grab active:cursor-grabbing text-muted-foreground/50 hover:text-foreground transition-colors"
                  >
                    <GripVerticalIcon className="size-4" />
                  </button>

                  <div className="flex size-7 items-center justify-center rounded-lg bg-accent/10 text-accent shrink-0">
                    <BotIcon className="size-4" />
                  </div>

                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-medium text-foreground truncate">
                        {model.shortName}
                      </span>
                      <span className="text-[10px] font-semibold px-1.5 py-0.5 rounded bg-white/[0.06] text-muted-foreground">
                        {model.provider}
                      </span>
                    </div>
                    <p className="text-[11px] text-muted-foreground truncate">
                      {model.description}
                    </p>
                  </div>

                  {/* Effort and Fast Mode Controls */}
                  <div className="flex items-center gap-2 shrink-0">
                    {/* Reasoning Effort Popover */}
                    <Popover>
                      <PopoverTrigger
                        className="inline-flex items-center h-7 gap-1 px-2 text-xs font-normal rounded-md border border-white/10 bg-white/[0.03] hover:bg-white/[0.08] transition-colors cursor-pointer"
                      >
                        <span className="text-muted-foreground">Effort:</span>
                        <span className="font-medium capitalize text-foreground">
                          {model.effort ?? "none"}
                        </span>
                        <ChevronDownIcon className="size-3 text-muted-foreground" />
                      </PopoverTrigger>
                      <PopoverContent align="end" className="w-36 p-1 bg-card/95 backdrop-blur-xl border border-white/10">
                        <div className="space-y-0.5">
                          {(["none", "low", "medium", "high", "max"] as const).map(
                            (lvl) => (
                              <button
                                key={lvl}
                                type="button"
                                onClick={() => updateEffort(model.modelId, lvl)}
                                className={cn(
                                  "w-full text-left px-2.5 py-1.5 text-xs rounded-md capitalize transition-colors flex items-center justify-between",
                                  model.effort === lvl
                                    ? "bg-accent text-accent-foreground font-medium"
                                    : "hover:bg-white/[0.08] text-foreground",
                                )}
                              >
                                {lvl}
                                {model.effort === lvl && (
                                  <CheckCircle2Icon className="size-3" />
                                )}
                              </button>
                            ),
                          )}
                        </div>
                      </PopoverContent>
                    </Popover>

                    {/* Fast Mode Toggle */}
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      aria-label="Toggle fast mode"
                      onClick={() => toggleFastMode(model.modelId)}
                      className={cn(
                        "size-7 border border-white/10 transition-colors",
                        model.fastMode
                          ? "bg-amber-500/20 text-amber-400 border-amber-500/30"
                          : "text-muted-foreground/50 hover:text-foreground bg-white/[0.03]",
                      )}
                    >
                      <ZapIcon className="size-3.5 fill-current" />
                    </Button>

                    {/* Unpin Button */}
                    <Button
                      variant="ghost"
                      size="icon-sm"
                      aria-label="Remove model from picker"
                      onClick={() =>
                        persistPinned(pinned.filter((p) => p.modelId !== model.modelId))
                      }
                      className="size-7 text-muted-foreground hover:text-destructive hover:bg-destructive/10 transition-colors"
                    >
                      <MinusCircleIcon className="size-4" />
                    </Button>
                  </div>
                </div>
              ))
            )}
          </div>
          <p className="px-1 text-[11px] text-muted-foreground">
            Click a model's effort to set default thinking tokens and fast mode for every new chat.
          </p>
        </div>

        {/* Provider Catalogs */}
        <div className="space-y-6 pt-2">
          {providerGroups.map(([providerName, models]) => (
            <div key={providerName} className="space-y-2">
              <div className="flex items-center gap-2 px-1">
                <BotIcon className="size-4 text-accent" />
                <h3 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
                  {providerName}
                </h3>
              </div>

              <div className="rounded-2xl border border-white/10 bg-card/60 backdrop-blur-md overflow-hidden divide-y divide-white/5 shadow-sm">
                {models.map((model) => {
                  const pinnedAlready = isPinned(model.id);
                  return (
                    <div
                      key={model.id}
                      className="flex items-center justify-between gap-4 px-4 py-3 transition-colors hover:bg-white/[0.03]"
                    >
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-2">
                          <span className="text-sm font-medium text-foreground">
                            {model.shortName}
                          </span>
                          {model.supportsFast && (
                            <span className="flex items-center gap-0.5 text-[10px] text-amber-400 bg-amber-400/10 px-1.5 py-0.5 rounded font-medium">
                              <ZapIcon className="size-2.5 fill-current" />
                              Fast
                            </span>
                          )}
                        </div>
                        <p className="text-[11px] text-muted-foreground mt-0.5">
                          {model.description}
                        </p>
                      </div>

                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() => togglePin(model)}
                        className={cn(
                          "h-8 gap-1.5 px-3 text-xs font-medium rounded-full transition-all",
                          pinnedAlready
                            ? "bg-accent/15 text-accent hover:bg-accent/25 border border-accent/20"
                            : "border border-white/10 bg-white/[0.04] text-foreground hover:bg-white/[0.08]",
                        )}
                      >
                        {pinnedAlready ? (
                          <>
                            <CheckCircle2Icon className="size-3.5 text-accent" />
                            Pinned
                          </>
                        ) : (
                          <>
                            <PlusCircleIcon className="size-3.5 text-muted-foreground" />
                            Add to picker
                          </>
                        )}
                      </Button>
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      </div>
    </SettingsPageContainer>
  );
}
