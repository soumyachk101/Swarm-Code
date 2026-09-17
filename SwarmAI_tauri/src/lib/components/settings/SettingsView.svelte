<script lang="ts">
	import { onMount } from 'svelte';
	import ProviderSettings from '$lib/components/settings/ProviderSettings.svelte';
	import HydraSettings from '$lib/components/settings/HydraSettings.svelte';
	import ShortcutsSettingsPage from '$lib/components/settings/ShortcutsSettingsPage.svelte';
	import AboutView from '$lib/components/settings/AboutView.svelte';
	import { getSettings, updateSettings, resetSettings } from '$lib/api/commands';
	import type { AppSettings, RuntimeMode } from '$lib/types';
	import { AppTheme, RUNTIME_MODE_TITLES } from '$lib/types';

	// ---------------------------------------------------------------------------
	// Tab definitions
	// ---------------------------------------------------------------------------

	type TabId = 'general' | 'providers' | 'hydra' | 'shortcuts' | 'about';

	interface TabDef {
		id: TabId;
		label: string;
	}

	const tabs: TabDef[] = [
		{ id: 'general', label: 'General' },
		{ id: 'providers', label: 'Providers' },
		{ id: 'hydra', label: 'Hydra' },
		{ id: 'shortcuts', label: 'Shortcuts' },
		{ id: 'about', label: 'About' },
	];

	// ---------------------------------------------------------------------------
	// State
	// ---------------------------------------------------------------------------

	let activeTab = $state<TabId>('general');
	let settings = $state<AppSettings | null>(null);
	let isLoading = $state(true);
	let isSaving = $state(false);
	let showConfirmReset = $state(false);

	// Local form state
	let theme = $state(AppTheme.System);
	let font_size = $state(13);
	let auto_scroll = $state(true);
	let streaming = $state(true);
	let sound_enabled = $state(false);
	let notification_enabled = $state(true);
	let show_timeline = $state(true);
	let show_usage = $state(true);
	let default_provider = $state<string | null>(null);
	let default_runtime_mode = $state(RuntimeMode.Supervised);
	let terminal_shell = $state('/bin/zsh');
	let sidebar_width = $state(260);

	// ---------------------------------------------------------------------------
	// Load
	// ---------------------------------------------------------------------------

	$effect(() => {
		loadSettings();
	});

	async function loadSettings() {
		try {
			settings = await getSettings();
			if (settings) {
				theme = settings.theme ?? AppTheme.System;
				font_size = settings.font_size ?? 13;
				auto_scroll = settings.auto_scroll ?? true;
				streaming = settings.streaming ?? true;
				sound_enabled = settings.sound_enabled ?? false;
				notification_enabled = settings.notification_enabled ?? true;
				show_timeline = settings.show_timeline ?? true;
				show_usage = settings.show_usage ?? true;
				default_provider = settings.default_provider ?? null;
				default_runtime_mode = settings.default_runtime_mode ?? RuntimeMode.Supervised;
				terminal_shell = settings.terminal_shell ?? '/bin/zsh';
				sidebar_width = settings.sidebar_width ?? 260;
			}
		} catch (e) {
			console.error('Failed to load settings:', e);
		} finally {
			isLoading = false;
		}
	}

	// ---------------------------------------------------------------------------
	// Save / Reset
	// ---------------------------------------------------------------------------

	async function handleSave() {
		isSaving = true;
		try {
			const safeShell = isValidShell(terminal_shell) ? terminal_shell : '/bin/bash';
			if (safeShell !== terminal_shell) {
				terminal_shell = safeShell;
			}
			await updateSettings({
				theme,
				font_size,
				auto_scroll,
				streaming,
				sound_enabled,
				notification_enabled,
				show_timeline,
				show_usage,
				default_provider: default_provider as any,
				default_runtime_mode,
				terminal_shell,
				sidebar_width,
			});
		} catch (e) {
			console.error('Failed to save settings:', e);
		} finally {
			isSaving = false;
		}
	}

	async function handleReset() {
		try {
			settings = await resetSettings();
			if (settings) {
				theme = settings.theme;
				font_size = settings.font_size;
				auto_scroll = settings.auto_scroll;
				streaming = settings.streaming;
				sound_enabled = settings.sound_enabled;
				notification_enabled = settings.notification_enabled;
				show_timeline = settings.show_timeline;
				show_usage = settings.show_usage;
				default_provider = settings.default_provider;
				default_runtime_mode = settings.default_runtime_mode;
				terminal_shell = settings.terminal_shell;
				sidebar_width = settings.sidebar_width;
			}
			showConfirmReset = false;
		} catch (e) {
			console.error('Failed to reset settings:', e);
		}
	}

	$effect(() => {
		const root = document.documentElement;
		root.setAttribute('data-theme', theme);
	});

	// ---------------------------------------------------------------------------
	// Navigation
	// ---------------------------------------------------------------------------

	function selectTab(tab: TabId) {
		activeTab = tab;
	}

	// ---------------------------------------------------------------------------
	// Helpers
	// ---------------------------------------------------------------------------

	const ALLOWED_SHELLS = ['/bin/bash', '/bin/zsh', '/bin/sh', '/usr/bin/fish', '/usr/bin/xonsh'] as const;

	function isValidShell(path: string): boolean {
		return ALLOWED_SHELLS.includes(path);
	}

	function runtimeModeOptions(): { value: RuntimeMode; label: string }[] {
		return Object.values(RuntimeMode).map((val) => ({
			value: val,
			label: RUNTIME_MODE_TITLES[val] ?? val,
		}));
	}
</script>

<div class="settings-container">
	<!-- Sidebar Navigation -->
	<nav class="settings-nav">
		<div class="settings-nav-header">
			<h2 class="settings-nav-title">Settings</h2>
		</div>

		<div class="settings-nav-list">
			{#each tabs as tab (tab.id)}
				<button
					class="settings-nav-item"
					class:active={activeTab === tab.id}
					onclick={() => selectTab(tab.id)}
				>
					{tab.label}
				</button>
			{/each}
		</div>
	</nav>

	<!-- Content Area -->
	<div class="settings-content">
		{#if isLoading}
			<div class="loading-state">
				<div class="spinner"></div>
				<p>Loading settings…</p>
			</div>
		{:else if activeTab === 'general'}
			<div class="settings-page">
				<div class="settings-page-header">
					<h2 class="settings-page-title">General</h2>
					<p class="settings-page-desc">Configure your app appearance and behavior</p>
				</div>

				<!-- Appearance -->
				<section class="settings-section">
					<h3 class="settings-section-title">Appearance</h3>

					<div class="settings-field">
						<div class="settings-field-info">
							<span class="settings-field-label">Theme</span>
							<span class="settings-field-desc">Choose the application color scheme</span>
						</div>
						<div class="settings-field-control">
							<select
								class="settings-select"
								value={theme}
								onchange={(e) => { theme = e.currentTarget.value as AppTheme; }}
							>
								<option value={AppTheme.Light}>Light</option>
								<option value={AppTheme.Dark}>Dark</option>
								<option value={AppTheme.System}>System</option>
							</select>
						</div>
					</div>

					<div class="settings-field">
						<div class="settings-field-info">
							<span class="settings-field-label">Font Size</span>
							<span class="settings-field-desc">Base text size in pixels</span>
						</div>
						<div class="settings-field-control">
							<div class="number-control">
								<button class="size-btn" onclick={() => font_size = Math.max(11, font_size - 1)} disabled={font_size <= 11}>−</button>
								<span class="size-value">{font_size}px</span>
								<button class="size-btn" onclick={() => font_size = Math.min(20, font_size + 1)} disabled={font_size >= 20}>+</button>
							</div>
						</div>
					</div>

					<div class="settings-field">
						<div class="settings-field-info">
							<span class="settings-field-label">Sidebar Width</span>
							<span class="settings-field-desc">Width of the sidebar panel</span>
						</div>
						<div class="settings-field-control">
							<div class="number-control">
								<button class="size-btn" onclick={() => sidebar_width = Math.max(200, sidebar_width - 10)} disabled={sidebar_width <= 200}>−</button>
								<span class="size-value">{sidebar_width}px</span>
								<button class="size-btn" onclick={() => sidebar_width = Math.min(400, sidebar_width + 10)} disabled={sidebar_width >= 400}>+</button>
							</div>
						</div>
					</div>
				</section>

				<!-- Chat -->
				<section class="settings-section">
					<h3 class="settings-section-title">Chat</h3>

					<div class="settings-field">
						<div class="settings-field-info">
							<span class="settings-field-label">Streaming Responses</span>
							<span class="settings-field-desc">Show responses as they are generated</span>
						</div>
						<label class="toggle-switch">
							<input type="checkbox" bind:checked={streaming} />
							<span class="toggle-track"></span>
							<span class="toggle-thumb"></span>
						</label>
					</div>

					<div class="settings-field">
						<div class="settings-field-info">
							<span class="settings-field-label">Auto-scroll</span>
							<span class="settings-field-desc">Automatically scroll to new messages</span>
						</div>
						<label class="toggle-switch">
							<input type="checkbox" bind:checked={auto_scroll} />
							<span class="toggle-track"></span>
							<span class="toggle-thumb"></span>
						</label>
					</div>

					<div class="settings-field">
						<div class="settings-field-info">
							<span class="settings-field-label">Default Runtime Mode</span>
							<span class="settings-field-desc">How freely the agent can act</span>
						</div>
						<div class="settings-field-control">
							<select
								class="settings-select"
								value={default_runtime_mode}
								onchange={(e) => { default_runtime_mode = e.currentTarget.value as RuntimeMode; }}
							>
								{#each runtimeModeOptions() as opt}
									<option value={opt.value}>{opt.label}</option>
								{/each}
							</select>
						</div>
					</div>
				</section>

				<!-- Display -->
				<section class="settings-section">
					<h3 class="settings-section-title">Display</h3>

					<div class="settings-field">
						<div class="settings-field-info">
							<span class="settings-field-label">Show Timeline</span>
							<span class="settings-field-desc">Display the thread timeline panel</span>
						</div>
						<label class="toggle-switch">
							<input type="checkbox" bind:checked={show_timeline} />
							<span class="toggle-track"></span>
							<span class="toggle-thumb"></span>
						</label>
					</div>

					<div class="settings-field">
						<div class="settings-field-info">
							<span class="settings-field-label">Show Token Usage</span>
							<span class="settings-field-desc">Display context usage in chat</span>
						</div>
						<label class="toggle-switch">
							<input type="checkbox" bind:checked={show_usage} />
							<span class="toggle-track"></span>
							<span class="toggle-thumb"></span>
						</label>
					</div>
				</section>

				<!-- Notifications -->
				<section class="settings-section">
					<h3 class="settings-section-title">Notifications</h3>

					<div class="settings-field">
						<div class="settings-field-info">
							<span class="settings-field-label">Sound Effects</span>
							<span class="settings-field-desc">Play sounds on message events</span>
						</div>
						<label class="toggle-switch">
							<input type="checkbox" bind:checked={sound_enabled} />
							<span class="toggle-track"></span>
							<span class="toggle-thumb"></span>
						</label>
					</div>

					<div class="settings-field">
						<div class="settings-field-info">
							<span class="settings-field-label">Notifications</span>
							<span class="settings-field-desc">Show system notifications</span>
						</div>
						<label class="toggle-switch">
							<input type="checkbox" bind:checked={notification_enabled} />
							<span class="toggle-track"></span>
							<span class="toggle-thumb"></span>
						</label>
					</div>
				</section>

				<!-- Advanced -->
				<section class="settings-section">
					<h3 class="settings-section-title">Advanced</h3>

					<div class="settings-field">
						<div class="settings-field-info">
							<span class="settings-field-label">Terminal Shell</span>
							<span class="settings-field-desc">Default shell for terminal sessions</span>
						</div>
						<div class="settings-field-control">
							<input
								type="text"
								class="settings-input mono"
								list="allowed-shells"
								value={terminal_shell}
								oninput={(e) => { terminal_shell = e.currentTarget.value; }}
							/>
							<datalist id="allowed-shells">
								{#each ALLOWED_SHELLS as shell}
									<option value={shell}></option>
								{/each}
							</datalist>
							{#if !isValidShell(terminal_shell)}
								<small class="settings-hint error">Must be one of: {ALLOWED_SHELLS.join(', ')}</small>
							{/if}
						</div>
					</div>
				</section>

				<!-- Actions -->
				<div class="settings-actions-bar">
					{#if showConfirmReset}
						<div class="confirm-reset">
							<button class="btn btn-danger" onclick={handleReset}>Confirm Reset</button>
							<button class="btn btn-secondary" onclick={() => showConfirmReset = false}>Cancel</button>
						</div>
					{:else}
						<div class="settings-actions-group">
							<button class="btn btn-primary" onclick={handleSave} disabled={isSaving}>
								{isSaving ? 'Saving…' : 'Save Changes'}
							</button>
							<button class="btn btn-secondary" onclick={() => showConfirmReset = true}>Reset All</button>
						</div>
					{/if}
				</div>
			</div>
		{:else if activeTab === 'providers'}
			<ProviderSettings />
		{:else if activeTab === 'hydra'}
			<HydraSettings />
		{:else if activeTab === 'shortcuts'}
			<ShortcutsSettingsPage />
		{:else if activeTab === 'about'}
			<AboutView />
		{/if}
	</div>
</div>

<style>
	.settings-container {
		flex: 1;
		display: flex;
		overflow: hidden;
		background: var(--surface-1);
	}

	/* ── Sidebar ── */

	.settings-nav {
		width: 200px;
		flex-shrink: 0;
		border-right: var(--border-1) var(--border-color-1);
		padding: var(--space-4) var(--space-2);
		overflow-y: auto;
		background: var(--surface-2);
	}

	.settings-nav-header {
		padding: var(--space-2) var(--space-3);
		margin-bottom: var(--space-3);
	}

	.settings-nav-title {
		font-size: var(--font-size-lg);
		font-weight: 700;
		color: var(--text-primary);
	}

	.settings-nav-list {
		display: flex;
		flex-direction: column;
		gap: 1px;
	}

	.settings-nav-item {
		display: flex;
		align-items: center;
		padding: 8px var(--space-3);
		border-radius: var(--radius-md);
		font-size: var(--font-size-sm);
		font-weight: 400;
		color: var(--text-secondary);
		cursor: pointer;
		transition: all var(--transition-fast);
		border: none;
		background: transparent;
		width: 100%;
		text-align: left;
		font-family: var(--font-system);
	}

	.settings-nav-item:hover {
		background: var(--surface-3);
		color: var(--text-primary);
	}

	.settings-nav-item.active {
		background: var(--accent-3);
		color: var(--accent-1);
		font-weight: 500;
	}

	/* ── Content ── */

	.settings-content {
		flex: 1;
		overflow-y: auto;
		padding: var(--space-6) var(--space-8);
		max-width: 680px;
	}

	.settings-page {
		display: flex;
		flex-direction: column;
		gap: var(--space-6);
	}

	.settings-page-header {
		margin-bottom: var(--space-2);
	}

	.settings-page-title {
		font-size: var(--font-size-xl);
		font-weight: 700;
		color: var(--text-primary);
	}

	.settings-page-desc {
		font-size: var(--font-size-sm);
		color: var(--text-tertiary);
		margin-top: var(--space-1);
	}

	/* ── Sections ── */

	.settings-section {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		padding-bottom: var(--space-4);
		border-bottom: var(--border-1) var(--border-color-2);
	}

	.settings-section:last-of-type {
		border-bottom: none;
	}

	.settings-section-title {
		font-size: var(--font-size-sm);
		font-weight: 600;
		color: var(--text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.5px;
		padding-bottom: var(--space-2);
		border-bottom: var(--border-1) var(--border-color-2);
	}

	.settings-field {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-4);
		padding: var(--space-3) 0;
	}

	.settings-field-info {
		display: flex;
		flex-direction: column;
		gap: 2px;
		flex: 1;
		min-width: 0;
	}

	.settings-field-label {
		font-size: var(--font-size-sm);
		color: var(--text-primary);
		font-weight: 400;
	}

	.settings-field-desc {
		font-size: 11px;
		color: var(--text-tertiary);
		margin-top: 1px;
	}

	.settings-field-control {
		flex-shrink: 0;
	}

	/* ── Toggle ── */

	.toggle-switch {
		position: relative;
		width: 42px;
		height: 24px;
		cursor: pointer;
	}

	.toggle-switch input {
		opacity: 0;
		width: 0;
		height: 0;
	}

	.toggle-track {
		position: absolute;
		inset: 0;
		background: var(--surface-4);
		border-radius: 12px;
		transition: background var(--transition-fast);
	}

	.toggle-switch input:checked + .toggle-track {
		background: var(--accent-1);
	}

	.toggle-thumb {
		position: absolute;
		top: 2px;
		left: 2px;
		width: 20px;
		height: 20px;
		background: white;
		border-radius: 50%;
		box-shadow: var(--shadow-sm);
		transition: transform var(--transition-fast);
		pointer-events: none;
	}

	.toggle-switch input:checked ~ .toggle-thumb {
		transform: translateX(18px);
	}

	/* ── Select ── */

	.settings-select {
		padding: 6px 28px 6px 10px;
		border: var(--border-1) var(--border-color-1);
		background: var(--surface-1);
		border-radius: var(--radius-sm);
		font-size: var(--font-size-sm);
		color: var(--text-primary);
		font-family: var(--font-system);
		cursor: pointer;
		outline: none;
		appearance: none;
		-webkit-appearance: none;
		background-image: url("data:image/svg+xml,%3Csvg width='8' height='5' viewBox='0 0 8 5' fill='none' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath d='M1 1l3 3 3-3' stroke='%2398989d' stroke-width='1.5' stroke-linecap='round'/%3E%3C/svg%3E");
		background-repeat: no-repeat;
		background-position: right 8px center;
		min-width: 180px;
	}

	.settings-select:focus {
		border-color: var(--accent-1);
	}

	/* ── Input ── */

	.settings-input {
		padding: 6px 10px;
		border: var(--border-1) var(--border-color-1);
		background: var(--surface-1);
		border-radius: var(--radius-sm);
		font-size: var(--font-size-sm);
		color: var(--text-primary);
		font-family: var(--font-system);
		outline: none;
		transition: border-color var(--transition-fast);
	}

	.settings-input.mono {
		font-family: var(--font-mono);
		font-size: 11px;
		width: 200px;
	}

	.settings-input:focus {
		border-color: var(--accent-1);
	}

	/* ── Number Control ── */

	.number-control {
		display: flex;
		align-items: center;
		gap: 2px;
		background: var(--surface-3);
		border-radius: var(--radius-md);
		padding: 2px;
	}

	.size-btn {
		width: 28px;
		height: 28px;
		border: none;
		background: transparent;
		border-radius: var(--radius-sm);
		font-size: var(--font-size-md);
		color: var(--text-secondary);
		cursor: pointer;
		display: flex;
		align-items: center;
		justify-content: center;
		transition: all var(--transition-fast);
	}

	.size-btn:hover:not(:disabled) {
		background: var(--surface-1);
		color: var(--text-primary);
	}

	.size-btn:disabled {
		opacity: 0.3;
		cursor: not-allowed;
	}

	.size-value {
		width: 40px;
		text-align: center;
		font-size: var(--font-size-sm);
		font-weight: 500;
		color: var(--text-primary);
		font-family: var(--font-mono);
	}

	/* ── Buttons ── */

	.btn {
		padding: 6px 16px;
		border: none;
		border-radius: var(--radius-md);
		font-size: var(--font-size-sm);
		font-weight: 500;
		cursor: pointer;
		transition: all var(--transition-fast);
		font-family: var(--font-system);
	}

	.btn-primary {
		background: var(--accent-1);
		color: white;
	}

	.btn-primary:hover:not(:disabled) {
		background: var(--accent-2);
	}

	.btn-primary:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}

	.btn-secondary {
		background: var(--surface-3);
		color: var(--text-primary);
	}

	.btn-secondary:hover {
		background: var(--surface-4);
	}

	.btn-danger {
		background: rgba(255, 59, 48, 0.1);
		color: var(--danger);
	}

	.btn-danger:hover {
		background: rgba(255, 59, 48, 0.2);
	}

	.settings-actions-bar {
		margin-top: var(--space-4);
		padding-top: var(--space-4);
		border-top: var(--border-1) var(--border-color-1);
	}

	.confirm-reset {
		display: flex;
		gap: var(--space-2);
	}

	.settings-actions-group {
		display: flex;
		gap: var(--space-2);
	}

	/* ── Loading ── */

	.loading-state {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		height: 100%;
		gap: var(--space-4);
		color: var(--text-tertiary);
	}

	.spinner {
		width: 28px;
		height: 28px;
		border: 2px solid var(--surface-3);
		border-top-color: var(--accent-1);
		border-radius: 50%;
		animation: spin 0.7s linear infinite;
	}

	@keyframes spin {
		to { transform: rotate(360deg); }
	}

	/* ── Scrollbar ── */

	.settings-nav::-webkit-scrollbar,
	.settings-content::-webkit-scrollbar {
		width: var(--scrollbar-width);
	}

	.settings-nav::-webkit-scrollbar-track,
	.settings-content::-webkit-scrollbar-track {
		background: transparent;
	}

	.settings-nav::-webkit-scrollbar-thumb,
	.settings-content::-webkit-scrollbar-thumb {
		background: var(--surface-4);
		border-radius: var(--radius-full);
	}

	.settings-content::-webkit-scrollbar-thumb:hover {
		background: var(--surface-5);
	}
</style>
