import { writable, get } from 'svelte/store';
import {
	Project,
	ChatThread,
	TimelineItem,
	AppSettings,
	HydraPair,
	HydraHeadInfo,
	Provider,
	ProviderKind,
	RuntimeMode,
	AppTheme,
} from '$lib/types';

// ---- Library State ----

export interface AppState {
	projects: Project[];
	threads: ChatThread[];
	selectedProjectID: string | null;
	selectedThreadID: string | null;
	providers: Provider[];
	settings: AppSettings;
	hydraPairs: HydraPair[];
	timeline: TimelineItem[];
	theme: AppTheme;
	isSidebarCollapsed: boolean;
	isLoading: boolean;
}

function createDefaultSettings(): AppSettings {
	return {
		theme: AppTheme.System,
		theme_mode: 'system',
		font_size: 14,
		font_family: 'system',
		sidebar_width: 220,
		show_timeline: true,
		show_usage: true,
		auto_scroll: true,
		streaming: true,
		sound_enabled: true,
		notification_enabled: true,
		default_provider: ProviderKind.Codex,
		default_model: null,
		default_effort: null,
		default_runtime_mode: RuntimeMode.Supervised,
		pinned_models: [],
		shortcuts: [],
		recent_threads: [],
		editor_path: null,
		terminal_shell: '/bin/bash',
		terminal_rows: 24,
		terminal_cols: 80,
		hydra_max_heads: 5,
		hydra_auto_merge: false,
		hydra_review_heads: false,
		hydra_isolate_heads: true,
		notify_when_finished: true,
		chime_when_finished: 'drop',
		confirm_before_deleting: true,
		auto_continue_after_limit: false,
		thread_finish_action: 'settle',
		settle_sound: 'soft',
		show_reasoning: false,
		chat_zoom: 1,
		sidebar_activity_view: false,
		app_theme: AppTheme.System,
		backdrop_opacity: 0.5,
		binary_paths: {},
		disabled_providers: [],
		model_list: [],
		model_preferences: {},
		hydra_enabled: true,
		hydra_queue_heads: true,
		hydra_always_heads: false,
		last_project_id: null,
		last_effort: {},
		default_workspace_mode: 'local',
	};
}

const initialState: AppState = {
	projects: [],
	threads: [],
	selectedProjectID: null,
	selectedThreadID: null,
	providers: [],
	settings: createDefaultSettings(),
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

export function addThread(thread: ChatThread) {
	appStore.update(s => ({
		...s,
		threads: [thread, ...s.threads]
	}));
}

export function removeThread(threadId: string) {
	appStore.update(s => ({
		...s,
		threads: s.threads.filter(t => t.id !== threadId),
		selectedThreadID: s.selectedThreadID === threadId ? null : s.selectedThreadID
	}));
}

export function updateThread(threadId: string, updates: Partial<ChatThread>) {
	appStore.update(s => ({
		...s,
		threads: s.threads.map(t => t.id === threadId ? { ...t, ...updates } : t)
	}));
}

export function addProject(project: Project) {
	appStore.update(s => ({
		...s,
		projects: [...s.projects, project]
	}));
}

export function removeProject(projectId: string) {
	appStore.update(s => ({
		...s,
		projects: s.projects.filter(p => p.id !== projectId),
		threads: s.threads.filter(t => t.project_id !== projectId)
	}));
}

export function updateSettings(settings: Partial<AppSettings>) {
	appStore.update(s => ({
		...s,
		settings: { ...s.settings, ...settings }
	}));
}

export function addTimelineItem(item: TimelineItem) {
	appStore.update(s => ({
		...s,
		timeline: [...s.timeline, item]
	}));
}

export function setHydraPairs(pairs: HydraPair[]) {
	appStore.update(s => ({ ...s, hydraPairs: pairs }));
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
	return state.threads.filter(t => t.project_id === projectID);
}

export function getHydraHeads(thread: ChatThread): HydraHeadInfo[] {
	return thread.hydra ? [thread.hydra] : [];
}

export function isThreadRunning(thread: ChatThread): boolean {
	return thread.last_status === 'running';
}

export function sortedThreads(threads: ChatThread[]): ChatThread[] {
	return [...threads].sort((a, b) => {
		if (a.is_pinned && !b.is_pinned) return -1;
		if (!a.is_pinned && b.is_pinned) return 1;
		return new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime();
	});
}
