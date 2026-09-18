<script lang="ts">
	import { onMount } from 'svelte';
	import { appState } from '$lib/stores/appState.svelte';

	let settings = $derived(appState.settings);
	let retainDays = $state(90);
	let maxSizeMB = $state(100);
	let autoPrune = $state(false);
	let allowRestore = $state(true);

	onMount(() => {
		if (settings) {
			retainDays = settings.retainDays ?? 90;
			maxSizeMB = settings.maxSizeMB ?? 100;
			autoPrune = settings.autoPrune ?? false;
			allowRestore = settings.allowRestore ?? true;
		}
	});

	function handleSave() {
		if (!settings) return;
		appState.updateSettings({
			retainDays,
			maxSizeMB,
			autoPrune,
			allowRestore
		});
	}
</script>

<div class="settings-page">
	<h2 class="page-title">Archive</h2>
	<p class="page-description">Manage archived conversations and history.</p>

	<div class="settings-section">
		<h3 class="section-title">Retention</h3>
		<div class="settings-group">
			<div class="setting-item">
				<div class="setting-info">
					<label class="setting-label">Retain for (days)</label>
					<p class="setting-description">How long to keep archived conversations</p>
				</div>
				<input
					type="number"
					class="settings-input"
					bind:value={retainDays}
					min="1"
					step="1"
				/>
			</div>

			<div class="setting-item">
				<div class="setting-info">
					<label class="setting-label">Max Archive Size (MB)</label>
					<p class="setting-description">Maximum total size of archived data</p>
				</div>
				<input
					type="number"
					class="settings-input"
					bind:value={maxSizeMB}
					min="10"
					step="10"
				/>
			</div>
		</div>
	</div>

	<div class="settings-section">
		<h3 class="section-title">Options</h3>
		<div class="settings-group">
			<div class="setting-item">
				<div class="setting-info">
					<label class="setting-label">Auto-prune Old Archives</label>
					<p class="setting-description">Automatically remove archives exceeding retention</p>
				</div>
				<button
					class="toggle {autoPrune ? 'active' : ''}"
					onclick={() => autoPrune = !autoPrune}
					aria-label="Toggle auto-prune"
				>
					<div class="toggle-thumb"></div>
				</button>
			</div>

			<div class="setting-item">
				<div class="setting-info">
					<label class="setting-label">Allow Restore</label>
					<p class="setting-description">Allow restoring archived conversations</p>
				</div>
				<button
					class="toggle {allowRestore ? 'active' : ''}"
					onclick={() => allowRestore = !allowRestore}
					aria-label="Toggle allow restore"
				>
					<div class="toggle-thumb"></div>
				</button>
			</div>
		</div>
	</div>
</div>

<style>
	.settings-page {
		display: flex;
		flex-direction: column;
		gap: 1.5rem;
		padding: 2rem;
		max-width: 720px;
	}
	.page-title {
		font-size: 1.5rem;
		font-weight: 600;
		margin: 0;
	}
	.page-description {
		color: var(--text-secondary);
		margin: 0;
		font-size: 0.875rem;
	}
	.settings-section {
		display: flex;
		flex-direction: column;
		gap: 0.75rem;
	}
	.section-title {
		font-size: 0.75rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--text-secondary);
		margin: 0;
	}
	.settings-group {
		display: flex;
		flex-direction: column;
		gap: 1px;
		background: var(--border);
		border-radius: 8px;
		overflow: hidden;
		border: 1px solid var(--border);
	}
	.setting-item {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 0.875rem 1rem;
		background: var(--surface-2);
		gap: 1rem;
	}
	.setting-info {
		display: flex;
		flex-direction: column;
		gap: 0.125rem;
	}
	.setting-label {
		font-size: 0.8125rem;
		font-weight: 500;
	}
	.setting-description {
		font-size: 0.75rem;
		color: var(--text-secondary);
		margin: 0;
	}
	.toggle {
		position: relative;
		width: 36px;
		height: 20px;
		border-radius: 10px;
		border: none;
		cursor: pointer;
		background: var(--border);
		padding: 0;
		flex-shrink: 0;
		transition: background 0.2s;
	}
	.toggle.active {
		background: var(--accent, #007aff);
	}
	.toggle-thumb {
		position: absolute;
		top: 2px;
		left: 2px;
		width: 16px;
		height: 16px;
		border-radius: 50%;
		background: white;
		box-shadow: 0 1px 3px rgba(0,0,0,0.2);
		transition: transform 0.2s;
	}
	.toggle.active .toggle-thumb {
		transform: translateX(16px);
	}
	.settings-input {
		width: 120px;
		padding: 0.375rem 0.625rem;
		border-radius: 6px;
		border: 1px solid var(--border);
		background: var(--surface-1);
		color: var(--text-primary);
		font-size: 0.8125rem;
		text-align: right;
	}
</style>
