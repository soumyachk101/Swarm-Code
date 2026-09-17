<script lang="ts">
	import { getSettings, updateSettings } from '$lib/api/commands';
	import HydraGlyph from '$lib/components/HydraGlyph.svelte';

	// ---------------------------------------------------------------------------
	// Hydra settings live inside AppSettings — use updateSettings to persist
	// ---------------------------------------------------------------------------

	let settings = $state<{
		hydra_max_heads: number;
		hydra_auto_merge: boolean;
		hydra_reviews_heads: boolean;
		hydra_isolates_heads: boolean;
	} | null>(null);

	let isLoading = $state(true);
	let isSaving = $state(false);
	let hasChanges = $state(false);

	// Local form state
	let maxHeads = $state(3);
	let autoMerge = $state(false);
	let reviewsHeads = $state(false);
	let isolatesHeads = $state(true);

	$effect(() => {
		loadSettings();
	});

	async function loadSettings() {
		try {
			const s = await getSettings();
			if (s) {
				maxHeads = s.hydra_max_heads ?? 3;
				autoMerge = s.hydra_auto_merge ?? false;
				reviewsHeads = s.hydra_reviews_heads ?? false;
				isolatesHeads = s.hydra_isolates_heads ?? true;
				settings = {
					hydra_max_heads: s.hydra_max_heads,
					hydra_auto_merge: s.hydra_auto_merge,
					hydra_reviews_heads: s.hydra_reviews_heads,
					hydra_isolates_heads: s.hydra_isolates_heads,
				};
			}
		} catch (e) {
			console.error('Failed to load settings:', e);
		} finally {
			isLoading = false;
		}
	}

	async function handleSave() {
		isSaving = true;
		try {
			await updateSettings({
				hydra_max_heads: maxHeads,
				hydra_auto_merge: autoMerge,
				hydra_reviews_heads: reviewsHeads,
				hydra_isolates_heads: isolatesHeads,
			});
			hasChanges = false;
		} catch (e) {
			console.error('Failed to save hydra settings:', e);
		} finally {
			isSaving = false;
		}
	}

	function trackChange() {
		if (!settings) return;
		hasChanges =
			settings.hydra_max_heads !== maxHeads ||
			settings.hydra_auto_merge !== autoMerge ||
			settings.hydra_reviews_heads !== reviewsHeads ||
			settings.hydra_isolates_heads !== isolatesHeads;
	}

	$effect(() => {
		trackChange();
	});
</script>

<div class="hydra-settings">
	<div class="settings-page-header">
		<div class="header-info">
			<div class="hydra-glyph-row">
				<HydraGlyph size={24} state="idle" />
				<h2 class="settings-page-title">Hydra Swarm</h2>
			</div>
			<p class="settings-page-desc">Configure multi-agent swarm behavior and parallel execution</p>
		</div>
		{#if hasChanges}
			<button class="btn btn-primary" onclick={handleSave} disabled={isSaving}>
				{isSaving ? 'Saving…' : 'Save Changes'}
			</button>
		{/if}
	</div>

	{#if isLoading}
		<div class="loading">
			<div class="spinner"></div>
		</div>
	{:else}
		<div class="settings-page">
			<!-- Swarm Configuration -->
			<section class="settings-section">
				<h3 class="settings-section-title">Swarm Configuration</h3>

				<div class="settings-field">
					<div class="settings-field-info">
						<span class="settings-field-label">Max Heads</span>
						<span class="settings-field-desc">Maximum number of parallel agent heads per swarm</span>
					</div>
					<div class="settings-field-control">
						<div class="slider-control">
							<input
								type="range"
								class="slider-input"
								min="2"
								max="8"
								bind:value={maxHeads}
							/>
							<span class="slider-value">{maxHeads}</span>
						</div>
					</div>
				</div>
			</section>

			<!-- Behavior -->
			<section class="settings-section">
				<h3 class="settings-section-title">Behavior</h3>

				<div class="settings-field">
					<div class="settings-field-info">
						<span class="settings-field-label">Auto-merge Results</span>
						<span class="settings-field-desc">Automatically merge head outputs when all complete</span>
					</div>
					<label class="toggle-switch">
						<input type="checkbox" bind:checked={autoMerge} />
						<span class="toggle-track"></span>
						<span class="toggle-thumb"></span>
					</label>
				</div>

				<div class="settings-field">
					<div class="settings-field-info">
						<span class="settings-field-label">Cross-Head Reviews</span>
						<span class="settings-field-desc">Have heads review each other's outputs before merging</span>
					</div>
					<label class="toggle-switch">
						<input type="checkbox" bind:checked={reviewsHeads} />
						<span class="toggle-track"></span>
						<span class="toggle-thumb"></span>
					</label>
				</div>

				<div class="settings-field">
					<div class="settings-field-info">
						<span class="settings-field-label">Isolate Heads</span>
						<span class="settings-field-desc">Run each head in an isolated context (more tokens, safer)</span>
					</div>
					<label class="toggle-switch">
						<input type="checkbox" bind:checked={isolatesHeads} />
						<span class="toggle-track"></span>
						<span class="toggle-thumb"></span>
					</label>
				</div>
			</section>

			<!-- Preview -->
			<section class="settings-section">
				<h3 class="settings-section-title">What This Does</h3>
				<div class="info-card">
					<div class="info-row">
						<span class="info-icon">🐙</span>
						<span class="info-text">
							Launching a Hydra swarm spawns <strong>{maxHeads}</strong> parallel agent heads
							that explore different approaches to your task simultaneously.
						</span>
					</div>
					<div class="info-row">
						<span class="info-icon">{autoMerge ? '✅' : '⏸️'}</span>
						<span class="info-text">
							{autoMerge ? 'Results are auto-merged when all heads finish.' : 'You must manually merge head results.'}
						</span>
					</div>
					<div class="info-row">
						<span class="info-icon">{isolatesHeads ? '🔒' : '🔓'}</span>
						<span class="info-text">
							{isolatesHeads ? 'Each head runs in an isolated context with its own file system view.' : 'Heads share the same working directory and can see each other\'s files.'}
						</span>
					</div>
					<div class="info-row">
						<span class="info-icon">{reviewsHeads ? '👁️' : '🚫'}</span>
						<span class="info-text">
							{reviewsHeads ? 'Heads will review each other\'s outputs before merging.' : 'No cross-head review — heads work independently.'}
						</span>
					</div>
				</div>
			</section>
		</div>
	{/if}
</div>

<style>
	.hydra-settings {
		display: flex;
		flex-direction: column;
		gap: var(--space-6);
		width: 100%;
	}

	.settings-page-header {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--space-4);
	}

	.header-info {
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
		flex: 1;
	}

	.hydra-glyph-row {
		display: flex;
		align-items: center;
		gap: var(--space-3);
	}

	.settings-page-title {
		font-size: var(--font-size-xl);
		font-weight: 700;
		color: var(--text-primary);
	}

	.settings-page-desc {
		font-size: var(--font-size-sm);
		color: var(--text-tertiary);
	}

	/* ── Loading ── */

	.loading {
		display: flex;
		justify-content: center;
		padding: var(--space-8);
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

	/* ── Sections ── */

	.settings-page {
		display: flex;
		flex-direction: column;
		gap: var(--space-6);
	}

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

	/* ── Slider ── */

	.slider-control {
		display: flex;
		align-items: center;
		gap: var(--space-3);
	}

	.slider-input {
		width: 140px;
		height: 6px;
		-webkit-appearance: none;
		appearance: none;
		border-radius: 3px;
		background: var(--surface-3);
		outline: none;
		cursor: pointer;
	}

	.slider-input::-webkit-slider-thumb {
		-webkit-appearance: none;
		appearance: none;
		width: 18px;
		height: 18px;
		border-radius: 50%;
		background: var(--accent-1);
		cursor: pointer;
		border: 2px solid white;
		box-shadow: var(--shadow-sm);
	}

	.slider-input::-moz-range-thumb {
		width: 18px;
		height: 18px;
		border-radius: 50%;
		background: var(--accent-1);
		cursor: pointer;
		border: 2px solid white;
		box-shadow: var(--shadow-sm);
	}

	.slider-value {
		width: 30px;
		text-align: center;
		font-size: var(--font-size-sm);
		font-weight: 600;
		color: var(--text-primary);
		font-family: var(--font-mono);
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

	/* ── Info Card ── */

	.info-card {
		background: var(--surface-2);
		border: var(--border-1) var(--border-color-1);
		border-radius: var(--radius-md);
		padding: var(--space-4);
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}

	.info-row {
		display: flex;
		align-items: flex-start;
		gap: var(--space-3);
	}

	.info-icon {
		flex-shrink: 0;
		font-size: 16px;
		line-height: 1.4;
	}

	.info-text {
		font-size: var(--font-size-sm);
		color: var(--text-secondary);
		line-height: var(--line-height-normal);
	}

	.info-text strong {
		color: var(--text-primary);
		font-weight: 600;
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

	.btn:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}
</style>
