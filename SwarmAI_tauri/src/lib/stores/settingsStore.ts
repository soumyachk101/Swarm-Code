// =============================================================================
// SwarmAI Tauri Frontend — Settings Store
// =============================================================================

import { writable, derived, type Readable, type Writable } from 'svelte/store';
import type {
	AppSettings,
	Provider,
	ProviderKind,
	ThemeMode,
	ColorPalette,
	UUID,
} from '$lib/types';
import * as Commands from '$lib/api/commands';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

export const settings: Writable<AppSettings> = writable({
	id: 'default',
	theme_mode: 'system',
	color_palette: 'blue',
	font_size: 13,
	font_family: 'system',
	show_timestamps: true,
	show_token_usage: true,
	auto_continue: true,
	max_concurrent_hydras: 2,
	default_provider: null,
	default_effort: 'medium',
	auto_save_conversations: true,
	enable_animations: true,
	terminal_shell: '/bin/zsh',
	editor_command: 'code',
	shortcut_new_thread: 'cmd+t',
	shortcut_toggle_sidebar: 'cmd+shift+s',
	shortcut_send_message: 'cmd+enter',
	shortcut_open_settings: 'cmd+,',
	shortcut_open_palette: 'cmd+shift+p',
};);

export const providers: Writable<Provider[]> = writable([]);
export const activeSettingsTab: Writable<string> = writable('general');
export const hasUnsavedChanges: Writable<boolean> = writable(false);

// ---------------------------------------------------------------------------
// Derived
// ---------------------------------------------------------------------------

export const activeProvider: Readable<Provider | null> = derived(
	[providers, settings],
	([$providers, $settings]) =>
		$providers.find((p) => p.id === $settings.default_provider) ?? null,
);

export const providersByKind: Readable<Record<ProviderKind, Provider[]>> = derived(
	providers,
	($providers) => {
		const result: Record<string, Provider[]> = {
			openai: [],
			anthropic: [],
			ollama: [],
			openrouter: [],
			azure: [],
			gemini: [],
			custom: [],
		};
		for (const p of $providers) {
			if (!result[p.kind]) result[p.kind] = [];
			result[p.kind].push(p);
		}
		return result as Record<ProviderKind, Provider[]>;
	},
);

export const themeMode: Readable<ThemeMode> = derived(
	settings,
	($settings) => $settings.theme_mode,
);

export const colorPalette: Readable<ColorPalette> = derived(
	settings,
	($settings) => $settings.color_palette,
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
