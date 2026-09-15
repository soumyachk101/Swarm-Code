import { writable, get } from 'svelte/store';
import type {
 Project,
 ChatThread,
 TimelineItem,
 ProviderInfo,
 ModelOption,
 AppSettings,
 HydraPair,
 HydraHeadInfo,
 Library,
 ProviderKind,
 RuntimeMode,
 AppTheme,
 TurnStatus,
} from '$lib/types';

// ---- Library State ----

export interface AppState {
 projects: Project[];
 threads: ChatThread[];
 selectedProjectID: string | null;
 selectedThreadID: string | null;
 providers: ProviderInfo[];
 settings: AppSettings;
 hydraPairs: HydraPair[];
 timeline: TimelineItem[];
 theme: AppTheme;
 isSidebarCollapsed: boolean;
 isLoading: boolean;
}

const initialState: AppState = {
 projects: [],
 threads: [],
 selectedProjectID: null,
 selectedThreadID: null,
 providers: [],
 settings: {
 defaultProvider: ProviderKind.Codex,
 defaultRuntimeMode: RuntimeMode.Supervised,
 defaultWorkspaceMode: 'local',
 notifyWhenFinished: true,
 chimeWhenFinished: 'drop',
 confirmBeforeDeleting: true,
 autoContinueAfterLimit: false,
 threadFinishAction: { settle: true },
 settleSound: 'soft',
 showReasoning: false,
 chatZoom: 1,
 sidebarActivityView: false,
 appTheme: AppTheme.System,
 backdropOpacity: 0.5,
 binaryPaths: {},
 disabledProviders: [],
 modelList: [],
 modelPreferences: {},
 hydraEnabled: true,
 hydraQueueHeads: true,
 hydraAlwaysHeads: false,
 hydraIsolateHeads: true,
 hydraAutoMerge: false,
 hydraReviewHeads: false,
 hydraMaxHeads: undefined,
 } as AppSettings,
 hydraPairs: [],
 timeline: [],
 theme: AppTheme.System,
 isSidebarCollapsed: false,
 isLoading: false,
};

export const appStore = writable<AppState>(initialState);

// ---- Actions ----

export function selectProject(projectID: string | null) {
 appStore.update(s => ({ ...s, selectedProjectID: projectID }));
}

export function selectThread(threadID: string | null) {
 appStore.update(s => ({ ...s, selectedThreadID: threadID }));
}

export function toggleSidebar() {
 appStore.update(s => ({ ...s, isSidebarCollapsed: !s.isSidebarCollapsed }));
}

export function setTheme(theme: AppTheme) {
 appStore.update(s => ({ ...s, theme }));
}

export function setLoading(loading: boolean) {
 appStore.update(s => ({ ...s, isLoading: loading }));
}

// ---- Derived (read-only) ----

export function getSelectedThread(): ChatThread | undefined {
 const state = get(appStore);
 if (!state.selectedThreadID) return undefined;
 return state.threads.find(t => t.id === state.selectedThreadID);
}

export function getSelectedProject(): Project | undefined {
 const state = get(appStore);
 if (!state.selectedProjectID) return undefined;
 return state.projects.find(p => p.id === state.selectedProjectID);
}

export function getThreadsForProject(projectID: string): ChatThread[] {
 const state = get(appStore);
 return state.threads.filter(t => t.projectID === projectID);
}

export function getHydraHeads(thread: ChatThread): HydraHeadInfo[] {
 return thread.hydra ? [thread.hydra] : [];
}

export function isThreadRunning(thread: ChatThread): boolean {
 return thread.lastStatus === 'running';
}

export function sortedThreads(threads: ChatThread[]): ChatThread[] {
 return threads.sort((a, b) => {
 if (a.isPinned && !b.isPinned) return -1;
 if (!a.isPinned && b.isPinned) return 1;
 return new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime();
 });
}
