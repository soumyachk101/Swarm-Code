// =============================================================================
// SwarmAI Tauri Frontend — Settings Store
// =============================================================================

import { writable, derived, type Readable, type Writable } from 'svelte/store';
import type {
	AppSettings,
	Provider,
	ProviderKind,
	UUID,
} from '$lib/types';
import * as Commands from '$lib/api/commands';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

export const settings: Writable<AppSettings> = writable({
	theme: 'system',
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
	default_provider: 'codex' as ProviderKind,
	default_model: null,
	default_effort: null,
	default_runtime_mode: 'supervised',
	pinned_models: [],
	shortcuts: [],
	recent_threads: [],
	editor_path: null,
	terminal_shell: '/bin/bash',
	terminal_rows: 24,
	terminal_cols: 80,
	hydra_max_heads: 5,
	hydra_auto_merge: false,
	hydra_reviews_heads: false,
	hydra_isolates_heads: true,
	notify_when_finished: true,
	chime_when_finished: 'drop',
	confirm_before_deleting: true,
	auto_continue_after_limit: false,
	thread_finish_action: 'settle',
	settle_sound: 'soft',
	show_reasoning: false,
	chat_zoom: 1,
	sidebar_activity_view: false,
	app_theme: 'system',
	backdrop_opacity: 0.5,
	binary_paths: {},
	disabled_providers: [],
	model_list: [],
	model_preferences: {},
	hydra_enabled: true,
	hydra_queue_heads: true,
	hydra_always_heads: false,
	hydra_isolate_heads: true,
	hydra_auto_merge: false,
	hydra_review_heads: false,
	hydra_max_heads: 5,
	last_project_id: null,
	last_effort: {},
	default_workspace_mode: 'local',
});

export const providers: Writable<Provider[]> = writable([]);
export const activeSettingsTab: Writable<string> = writable('providers');
export const hasUnsavedChanges: Writable<boolean> = writable(false);

// ---------------------------------------------------------------------------
// Derived
// ---------------------------------------------------------------------------

export const activeProvider: Readable<Provider | null> = derived(
	[providers, settings],
	([$providers, $settings]) =>
		$providers.find((p) => p.id === $settings.default_provider) ?? null,
);

export const themeMode: Readable<string> = derived(
	settings,
	($settings) => $settings.theme_mode,
);

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

export async function loadSettings(): Promise<void> {
	try {
		const s = await Commands.getSettings();
		settings.set(s);
	} catch (err) {
		console.error('Failed to load settings:', err);
	}
}

export async function persistSettings(partial: Partial<AppSettings>): Promise<void> {
	try {
		const updated = await Commands.updateSettings(partial);
		settings.set(updated);
		hasUnsavedChanges.set(false);
	} catch (err) {
		console.error('Failed to save settings:', err);
		throw err;
	}
}

export function updateLocal(partial: Partial<AppSettings>): void {
	settings.update((s) => ({ ...s, ...partial }));
	hasUnsavedChanges.set(true);
}

export async function resetSettings(): Promise<void> {
	try {
		const s = await Commands.resetSettings();
		settings.set(s);
		hasUnsavedChanges.set(false);
	} catch (err) {
		console.error('Failed to reset settings:', err);
		throw err;
	}
}

export async function loadProviders(): Promise<void> {
	try {
		const list = await Commands.getProviders();
		providers.set(list);
	} catch (err) {
		console.error('Failed to load providers:', err);
	}
}

export async function saveProvider(provider: Partial<Provider>): Promise<Provider> {
	try {
		const saved = await Commands.saveProvider(provider);
		providers.update((list) => {
			const idx = list.findIndex((p) => p.id === saved.id);
			if (idx >= 0) {
				const next = [...list];
				next[idx] = saved;
				return next;
			}
			return [...list, saved];
		});
		return saved;
	} catch (err) {
		console.error('Failed to save provider:', err);
		throw err;
	}
}

export async function deleteProvider(providerId: UUID): Promise<void> {
	try {
		await Commands.deleteProvider(providerId);
		providers.update((list) => list.filter((p) => p.id !== providerId));
	} catch (err) {
		console.error('Failed to delete provider:', err);
		throw err;
	}
}

export function setActiveTab(tab: string): void {
	activeSettingsTab.set(tab);
}
