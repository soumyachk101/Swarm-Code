<script lang="ts">
	import { onMount } from 'svelte';
	import { appState } from '$lib/stores/appState.svelte';

	let settings = $derived(appState.settings);

	let autoSelectModel = $state(false);
	let rememberChoice = $state(true);
	let showCostIndicator = $state(true);
	let maxReasoningTokens = $state(0);
	let effortPicker = $state<'auto' | 'minimal' | 'low' | 'medium' | 'high' | 'maximal'>('auto');

	onMount(() => {
		if (settings) {
			autoSelectModel = settings.autoSelectModel ?? false;
			rememberChoice = settings.rememberChoice ?? true;
			showCostIndicator = settings.showCostIndicator ?? true;
			maxReasoningTokens = settings.maxReasoningTokens ?? 0;
			effortPicker = settings.effortPicker ?? 'auto';
		}
	});

	function handleSave() {
		if (!settings) return;
		appState.updateSettings({
			autoSelectModel,
			rememberChoice,
			showCostIndicator,
			maxReasoningTokens,
			effortPicker
		});
	}
</script>

<div class="settings-page">
	<h2 class="page-title">Models</h2>
	<p class="page-description">Configure model selection and reasoning effort defaults.</p>

	<div class="settings-section">
		<h3 class="section-title">Default Model</h3>
		<div class="settings-group">
			<div class="setting-item">
				<div class="setting-info">
					<label class="setting-label">Auto-select Model</label>
					<p class="setting-description">Automatically choose the best model for the task</p>
				</div>
				<button
					class="toggle {autoSelectModel ? 'active' : ''}"
					onclick={() => autoSelectModel = !autoSelectModel}
					aria-label="Toggle auto-select model"
				>
					<div class="toggle-thumb"></div>
				</button>
			</div>

			<div class="setting-item">
				<div class="setting-info">
					<label class="setting-label">Remember Choice</label>
					<p class="setting-description">Remember the last selected model</p>
				</div>
				<button
					class="toggle {rememberChoice ? 'active' : ''}"
					onclick={() => rememberChoice = !rememberChoice}
					aria-label="Toggle remember choice"
				>
					<div class="toggle-thumb"></div>
				</button>
			</div>

			<div class="setting-item">
				<div class="setting-info">
					<label class="setting-label">Show Cost Indicator</label>
					<p class="setting-description">Display token cost estimates next to models</p>
				</div>
				<button
					class="toggle {showCostIndicator ? 'active' : ''}"
					onclick={() => showCostIndicator = !showCostIndicator}
					aria-label="Toggle cost indicator"
				>
					<div class="toggle-thumb"></div>
				</button>
			</div>
		</div>
	</div>

	<div class="settings-section">
		<h3 class="section-title">Reasoning Effort</h3>
		<div class="settings-group">
			<div class="setting-item">
				<div class="setting-info">
					<label class="setting-label">Default Effort</label>
					<p class="setting-description">Default reasoning effort level</p>
				</div>
				<select class="settings-select" bind:value={effortPicker}>
					<option value="auto">Auto</option>
					<option value="minimal">Minimal</option>
					<option value="low">Low</option>
					<option value="medium">Medium</option>
					<option value="high">High</option>
					<option value="maximal">Maximal</option>
				</select>
			</div>

			<div class="setting-item">
				<div class="setting-info">
					<label class="setting-label">Max Reasoning Tokens</label>
					<p class="setting-description">Maximum tokens for reasoning (0 = unlimited)</p>
				</div>
				<input
					type="number"
					class="settings-input"
					bind:value={maxReasoningTokens}
					min="0"
					step="1000"
				/>
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
	.settings-select {
		padding: 0.375rem 0.625rem;
		border-radius: 6px;
		border: 1px solid var(--border);
		background: var(--surface-1);
		color: var(--text-primary);
		font-size: 0.8125rem;
		cursor: pointer;
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
