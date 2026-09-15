<script lang="ts">
	import { invoke } from '@tauri-apps/api/core';
	import { getSettings, updateSettings, resetSettings } from '$lib/api/commands';
	import type { AppSettings, ThemeMode, ColorPalette } from '$lib/types';

	let settings = $state<AppSettings | null>(null);
	let isLoading = $state(true);
	let showConfirmReset = $state(false);

	// Local form state
	let themeMode = $state<ThemeMode>('system');
	let accentPalette = $state<ColorPalette>('blue');
	let fontSize = $state(14);
	let enableAnimations = $state(true);
	let enableSounds = $state(false);
	let sendOnEnter = $state(true);
	let showTimestamps = $state(true);
	let showWorkingIndicators = $state(true);
	let maxThreads = $state(100);
	let autoArchive = $state(true);

	$effect(() => {
		loadSettings();
	});

	async function loadSettings() {
		try {
			settings = await getSettings();
			if (settings) {
				themeMode = settings.theme ?? 'system';
				accentPalette = settings.accentPalette ?? 'blue';
				fontSize = settings.fontSize ?? 14;
				enableAnimations = settings.enableAnimations ?? true;
				enableSounds = settings.enableSounds ?? false;
				sendOnEnter = settings.sendOnEnter ?? true;
				showTimestamps = settings.showTimestamps ?? true;
				showWorkingIndicators = settings.showWorkingIndicators ?? true;
				maxThreads = settings.maxThreads ?? 100;
				autoArchive = settings.autoArchive ?? true;
			}
		} catch (e) {
			console.error('Failed to load settings:', e);
		} finally {
			isLoading = false;
		}
	}

	async function handleSave() {
		try {
			await updateSettings({
				theme: themeMode,
				accentPalette,
				fontSize,
				enableAnimations,
				enableSounds,
				sendOnEnter,
				showTimestamps,
				showWorkingIndicators,
				maxThreads,
				autoArchive,
			});
			applyTheme();
		} catch (e) {
			console.error('Failed to save settings:', e);
		}
	}

	async function handleReset() {
		try {
			await resetSettings();
			await loadSettings();
			applyTheme();
			showConfirmReset = false;
		} catch (e) {
			console.error('Failed to reset settings:', e);
		}
	}

	function applyTheme() {
		const root = document.documentElement;
		root.setAttribute('data-theme', themeMode === 'system'
			? (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light')
			: themeMode
		);
		root.setAttribute('data-palette', accentPalette);
		root.style.setProperty('--font-size-base', fontSize + 'px');
		if (!enableAnimations) {
			root.style.setProperty('--transition-fast', '0s');
			root.style.setProperty('--transition-base', '0s');
		} else {
			root.style.setProperty('--transition-fast', '0.15s');
			root.style.setProperty('--transition-base', '0.25s');
		}
	}

	$effect(() => {
		applyTheme();
		const media = window.matchMedia('(prefers-color-scheme: dark)');
		const handler = () => {
			if (themeMode === 'system') applyTheme();
		};
		media.addEventListener('change', handler);
		return () => media.removeEventListener('change', handler);
	});

	let themeOptions: { value: ThemeMode; label: string }[] = [
		{ value: 'light', label: 'Light' },
		{ value: 'dark', label: 'Dark' },
		{ value: 'system', label: 'System' },
	];

	let paletteOptions: { value: ColorPalette; label: string; color: string }[] = [
		{ value: 'blue', label: 'Blue', color: '#007aff' },
		{ value: 'purple', label: 'Purple', color: '#af52de' },
		{ value: 'green', label: 'Green', color: '#30d158' },
		{ value: 'orange', label: 'Orange', color: '#ff9500' },
		{ value: 'red', label: 'Red', color: '#ff3b30' },
		{ value: 'teal', label: 'Teal', color: '#64d2ff' },
	];
</script>

{#if isLoading}
	<div class="loading-state">
		<div class="spinner"></div>
		<p>Loading settings…</p>
	</div>
{:else}
	<div class="settings-view">
		<div class="settings-header">
			<h2 class="settings-title">Settings</h2>
			<div class="settings-actions">
				<button class="btn-primary" onclick={handleSave}>Save Changes</button>
			</div>
		</div>

		<div class="settings-content">
			<!-- Appearance -->
			<section class="settings-section">
				<h3 class="section-heading">
					<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
						<circle cx="12" cy="12" r="5"/>
						<path d="M12 1v2m0 18v2M4.22 4.22l1.42 1.42m12.72 12.72 1.42 1.42M1 12h2m18 0h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"/>
					</svg>
					Appearance
				</h3>

				<div class="setting-row">
					<div class="setting-info">
						<span class="setting-name">Theme</span>
						<span class="setting-desc">Choose the application color scheme</span>
					</div>
					<div class="theme-options">
						{#each themeOptions as opt (opt.value)}
							<button
								class="theme-btn"
								class:active={themeMode === opt.value}
								onclick={() => themeMode = opt.value}
							>
								{opt.label}
							</button>
						{/each}
					</div>
				</div>

				<div class="setting-row">
					<div class="setting-info">
						<span class="setting-name">Accent Color</span>
						<span class="setting-desc">Choose your accent color palette</span>
					</div>
					<div class="palette-options">
						{#each paletteOptions as opt (opt.value)}
							<button
								class="palette-btn"
								class:active={accentPalette === opt.value}
								onclick={() => accentPalette = opt.value}
								title={opt.label}
							>
								<span class="palette-swatch" style="background: {opt.color}"></span>
							</button>
						{/each}
					</div>
				</div>

				<div class="setting-row">
					<div class="setting-info">
						<span class="setting-name">Font Size</span>
						<span class="setting-desc">Base text size in pixels</span>
					</div>
					<div class="font-size-control">
						<button
							class="size-btn"
							onclick={() => fontSize = Math.max(11, fontSize - 1)}
							disabled={fontSize <= 11}
						>−</button>
						<span class="size-value">{fontSize}px</span>
						<button
							class="size-btn"
							onclick={() => fontSize = Math.min(20, fontSize + 1)}
							disabled={fontSize >= 20}
						>+</button>
					</div>
				</div>

				<div class="setting-row">
					<div class="setting-info">
						<span class="setting-name">Animations</span>
						<span class="setting-desc">Enable interface animations</span>
					</div>
					<button
						class="toggle"
						class:on={enableAnimations}
						onclick={() => enableAnimations = !enableAnimations}
						role="switch"
						aria-checked={enableAnimations}
					>
						<span class="toggle-track">
							<span class="toggle-thumb"></span>
						</span>
					</button>
				</div>
			</section>

			<!-- Chat Behavior -->
			<section class="settings-section">
				<h3 class="section-heading">
					<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
						<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
					</svg>
					Chat
				</h3>

				<div class="setting-row">
					<div class="setting-info">
						<span class="setting-name">Send on Enter</span>
						<span class="setting-desc">Send messages with Enter instead of ⌘+Enter</span>
					</div>
					<button
						class="toggle"
						class:on={sendOnEnter}
						onclick={() => sendOnEnter = !sendOnEnter}
						role="switch"
						aria-checked={sendOnEnter}
					>
						<span class="toggle-track">
							<span class="toggle-thumb"></span>
						</span>
					</button>
				</div>

				<div class="setting-row">
					<div class="setting-info">
						<span class="setting-name">Show Timestamps</span>
						<span class="setting-desc">Display timestamps on messages</span>
					</div>
					<button
						class="toggle"
						class:on={showTimestamps}
						onclick={() => showTimestamps = !showTimestamps}
						role="switch"
						aria-checked={showTimestamps}
					>
						<span class="toggle-track">
							<span class="toggle-thumb"></span>
						</span>
					</button>
				</div>

				<div class="setting-row">
					<div class="setting-info">
						<span class="setting-name">Working Indicators</span>
						<span class="setting-desc">Show real-time progress in chat</span>
					</div>
					<button
						class="toggle"
						class:on={showWorkingIndicators}
						onclick={() => showWorkingIndicators = !showWorkingIndicators}
						role="switch"
						aria-checked={showWorkingIndicators}
					>
						<span class="toggle-track">
							<span class="toggle-thumb"></span>
						</span>
					</button>
				</div>

				<div class="setting-row">
					<div class="setting-info">
						<span class="setting-name">Sound Effects</span>
						<span class="setting-desc">Play sounds on message events</span>
					</div>
					<button
						class="toggle"
						class:on={enableSounds}
						onclick={() => enableSounds = !enableSounds}
						role="switch"
						aria-checked={enableSounds}
					>
						<span class="toggle-track">
							<span class="toggle-thumb"></span>
						</span>
					</button>
				</div>
			</section>

			<!-- Threads & Data -->
			<section class="settings-section">
				<h3 class="section-heading">
					<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
						<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
					</svg>
					Threads & Data
				</h3>

				<div class="setting-row">
					<div class="setting-info">
						<span class="setting-name">Auto-archive</span>
						<span class="setting-desc">Archives threads when creating new ones</span>
					</div>
					<button
						class="toggle"
						class:on={autoArchive}
						onclick={() => autoArchive = !autoArchive}
						role="switch"
						aria-checked={autoArchive}
					>
						<span class="toggle-track">
							<span class="toggle-thumb"></span>
						</span>
					</button>
				</div>

				<div class="setting-row">
					<div class="setting-info">
						<span class="setting-name">Max Threads</span>
						<span class="setting-desc">Maximum threads per project before archiving</span>
					</div>
					<div class="number-control">
						<button
							class="size-btn"
							onclick={() => maxThreads = Math.max(10, maxThreads - 10)}
						>−</button>
						<span class="size-value">{maxThreads}</span>
						<button
							class="size-btn"
							onclick={() => maxThreads = Math.min(500, maxThreads + 10)}
						>+</button>
					</div>
				</div>
			</section>

			<!-- Danger Zone -->
			<section class="settings-section danger-zone">
				<h3 class="section-heading">
					<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
						<path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/>
						<line x1="12" y1="9" x2="12" y2="13"/>
						<line x1="12" y1="17" x2="12.01" y2="17"/>
					</svg>
					Danger Zone
				</h3>

				<div class="setting-row">
					<div class="setting-info">
						<span class="setting-name">Reset All Settings</span>
						<span class="setting-desc">Restore all settings to their default values</span>
					</div>
					{#if showConfirmReset}
						<div class="confirm-reset">
							<button class="btn-danger small" onclick={handleReset}>Confirm Reset</button>
							<button class="btn-secondary small" onclick={() => showConfirmReset = false}>Cancel</button>
						</div>
					{:else}
						<button class="btn-danger" onclick={() => showConfirmReset = true}>
							Reset All
						</button>
					{/if}
				</div>
			</section>
		</div>
	</div>
{/if}

<style>
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

	.settings-view {
		height: 100%;
		overflow-y: auto;
		padding: var(--space-6) var(--space-8);
		display: flex;
		flex-direction: column;
		gap: var(--space-6);
		max-width: 680px;
	}

	.settings-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding-bottom: var(--space-4);
		border-bottom: var(--border-1) var(--border-color-1);
	}

	.settings-title {
		font-size: var(--font-size-xl);
		font-weight: 700;
		color: var(--text-primary);
	}

	.settings-actions {
		display: flex;
		gap: var(--space-2);
	}

	.settings-content {
		display: flex;
		flex-direction: column;
		gap: var(--space-6);
	}

	.settings-section {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}

	.section-heading {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		font-size: var(--font-size-sm);
		font-weight: 600;
		color: var(--text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.5px;
		padding-bottom: var(--space-2);
		border-bottom: var(--border-1) var(--border-color-2);
	}

	.setting-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: var(--space-3) 0;
		gap: var(--space-4);
	}

	.setting-info {
		display: flex;
		flex-direction: column;
		gap: 2px;
		flex: 1;
	}

	.setting-name {
		font-size: var(--font-size-sm);
		font-weight: 500;
		color: var(--text-primary);
	}

	.setting-desc {
		font-size: var(--font-size-xs);
		color: var(--text-tertiary);
	}

	/* Toggle Switch */
	.toggle {
		display: flex;
		align-items: center;
		background: none;
		border: none;
		cursor: pointer;
		padding: 2px;
	}

	.toggle-track {
		width: 40px;
		height: 22px;
		border-radius: 11px;
		background: var(--surface-4);
		position: relative;
		transition: background var(--transition-fast);
	}

	.toggle.on .toggle-track {
		background: var(--accent-1);
	}

	.toggle-thumb {
		position: absolute;
		top: 2px;
		left: 2px;
		width: 18px;
		height: 18px;
		border-radius: 50%;
		background: white;
		box-shadow: 0 1px 3px rgba(0, 0, 0, 0.3);
		transition: transform var(--transition-fast);
	}

	.toggle.on .toggle-thumb {
		transform: translateX(18px);
	}

	/* Theme Options */
	.theme-options {
		display: flex;
		gap: 2px;
		padding: 2px;
		background: var(--surface-3);
		border-radius: var(--radius-md);
	}

	.theme-btn {
		padding: 5px 12px;
		border: none;
		background: transparent;
		border-radius: var(--radius-sm);
		font-size: var(--font-size-xs);
		color: var(--text-secondary);
		cursor: pointer;
		transition: all var(--transition-fast);
		font-weight: 500;
	}

	.theme-btn.active {
		background: var(--surface-1);
		color: var(--text-primary);
		box-shadow: var(--shadow-sm);
	}

	.theme-btn:hover:not(.active) {
		color: var(--text-primary);
	}

	/* Palette Options */
	.palette-options {
		display: flex;
		gap: 6px;
	}

	.palette-btn {
		width: 28px;
		height: 28px;
		border: 2px solid transparent;
		background: transparent;
		border-radius: var(--radius-full);
		cursor: pointer;
		transition: all var(--transition-fast);
		display: flex;
		align-items: center;
		justify-content: center;
	}

	.palette-btn:hover {
		background: var(--surface-3);
	}

	.palette-btn.active {
		border-color: var(--text-primary);
		background: var(--surface-3);
	}

	.palette-swatch {
		width: 16px;
		height: 16px;
		border-radius: 50%;
	}

	/* Font Size */
	.font-size-control {
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

	/* Number control (same pattern) */
	.number-control {
		display: flex;
		align-items: center;
		gap: 2px;
		background: var(--surface-3);
		border-radius: var(--radius-md);
		padding: 2px;
	}

	/* Buttons */
	.btn-primary {
		padding: 6px 16px;
		border: none;
		background: var(--accent-1);
		color: var(--text-inverse);
		border-radius: var(--radius-sm);
		font-size: var(--font-size-sm);
		font-weight: 500;
		cursor: pointer;
		transition: background var(--transition-fast);
	}

	.btn-primary:hover {
		background: var(--accent-2);
	}

	.btn-secondary {
		padding: 5px 12px;
		border: var(--border-1) var(--border-color-1);
		background: transparent;
		border-radius: var(--radius-sm);
		font-size: var(--font-size-xs);
		color: var(--text-secondary);
		cursor: pointer;
	}

	.btn-secondary:hover {
		background: var(--surface-3);
	}

	.btn-secondary.small {
		padding: 4px 10px;
		font-size: 11px;
	}

	.btn-danger {
		padding: 5px 12px;
		border: var(--border-1) rgba(255, 59, 48, 0.2);
		background: rgba(255, 59, 48, 0.08);
		border-radius: var(--radius-sm);
		font-size: var(--font-size-xs);
		font-weight: 500;
		color: var(--danger);
		cursor: pointer;
		transition: all var(--transition-fast);
	}

	.btn-danger:hover {
		background: rgba(255, 59, 48, 0.15);
	}

	.btn-danger.small {
		padding: 3px 8px;
		font-size: 11px;
	}

	.danger-zone {
		padding-top: var(--space-4);
		border-top: var(--border-1) var(--border-color-1);
	}

	.danger-zone .section-heading {
		color: var(--danger);
	}

	.confirm-reset {
		display: flex;
		gap: var(--space-2);
	}

	/* Scrollbar */
	.settings-view::-webkit-scrollbar {
		width: 6px;
	}

	.settings-view::-webkit-scrollbar-track {
		background: transparent;
	}

	.settings-view::-webkit-scrollbar-thumb {
		background: var(--surface-4);
		border-radius: var(--radius-full);
	}
</style>
