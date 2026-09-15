<script lang="ts">
	import { getHydraSettings, updateHydraSettings } from '$lib/api/commands';
	import type { HydraPair, HydraSettings } from '$lib/types';

	interface Props {
		projectId: string | null;
	}

	let { projectId = null }: Props = $props();

	let settings = $state<HydraSettings | null>(null);
	let isLoading = $state(true);
	let isSaving = $state(false);

	// Form state
	let maxHeads = $state(3);
	let autoMerge = $state(true);
	let reviewsHeads = $state(true);
	let isolatesHeads = $state(false);
	let requireApproval = $state(false);
	let defaultOrchestrator = $state('claude-3-opus');
	let defaultWorker = $state('claude-3-sonnet');
	let timeoutMinutes = $state(15);

	$effect(() => {
		loadSettings();
	});

	async function loadSettings() {
		try {
			settings = await getHydraSettings();
			if (settings) {
				maxHeads = settings.maxHeads ?? 3;
				autoMerge = settings.autoMerge ?? true;
				reviewsHeads = settings.reviewsHeads ?? true;
				isolatesHeads = settings.isolatesHeads ?? false;
				requireApproval = settings.requireApproval ?? false;
				defaultOrchestrator = settings.defaultOrchestrator ?? 'claude-3-opus';
				defaultWorker = settings.defaultWorker ?? 'claude-3-sonnet';
				timeoutMinutes = settings.timeoutMinutes ?? 15;
			}
		} catch (e) {
			console.error('Failed to load hydra settings:', e);
		} finally {
			isLoading = false;
		}
	}

	async function handleSave() {
		isSaving = true;
		try {
			await updateHydraSettings({
				maxHeads,
				autoMerge,
				reviewsHeads,
				isolatesHeads,
				requireApproval,
				defaultOrchestrator,
				defaultWorker,
				timeoutMinutes,
			});
		} catch (e) {
			console.error('Failed to save settings:', e);
		} finally {
			isSaving = false;
		}
	}
</script>

<div class="hydra-settings">
	<div class="settings-header">
		<div class="header-info">
			<h2 class="settings-title">Hydra Swarm</h2>
			<p class="header-desc">Configure how Hydra explores multiple approaches in parallel</p>
		</div>
		<button class="btn-primary" onclick={handleSave} disabled={isSaving}>
			{isSaving ? 'Saving…' : 'Save Changes'}
		</button>
	</div>

	{#if isLoading}
		<div class="loading">
			<div class="spinner"></div>
		</div>
	{:else}
		<div class="settings-content">
			<!-- Swarm Configuration -->
			<section class="settings-section">
				<h3 class="section-heading">Swarm Configuration</h3>

				<div class="setting-row">
					<div class="setting-info">
						<span class="setting-name">Maximum Heads</span>
						<span class="setting-desc">Maximum number of parallel agents per swarm</span>
					</div>
					<div class="number-control">
						<button class="size-btn" onclick={() => maxHeads = Math.max(2, maxHeads - 1)} disabled={maxHeads <= 2}>−</button>
						<span class="size-value">{maxHeads}</span>
						<button class="size-btn" onclick={() => maxHeads = Math.min(8, maxHeads + 1)} disabled={maxHeads >= 8}>+</button>
					</div>
				</div>

				<div class="setting-row">
					<div class="setting-info">
						<span class="setting-name">Default Orchestrator Model</span>
						<span class="setting-desc">Model used to coordinate the swarm</span>
					</div>
					<input
						type="text"
						class="form-input"
						value={defaultOrchestrator}
						oninput={(e) => defaultOrchestrator = e.currentTarget.value}
					/>
				</div>

				<div class="setting-row">
					<div class="setting-info">
						<span class="setting-name">Default Worker Model</span>
						<span class="setting-desc">Model used for individual head execution</span>
					</div>
					<input
						type="text"
						class="form-input"
						value={defaultWorker}
						oninput={(e) => defaultWorker = e.currentTarget.value}
					/>
				</div>

				<div class="setting-row">
					<div class="setting-info">
						<span class="setting-name">Timeout (minutes)</span>
						<span class="setting-desc">Maximum time before a head is auto-stopped</span>
					</div>
					<div class="number-control">
						<button class="size-btn" onclick={() => timeoutMinutes = Math.max(1, timeoutMinutes - 1)} disabled={timeoutMinutes <= 1}>−</button>
						<span class="size-value">{timeoutMinutes}</span>
						<button class="size-btn" onclick={() => timeoutMinutes = Math.min(60, timeoutMinutes + 1)} disabled={timeoutMinutes >= 60}>+</button>
					</div>
				</div>
			</section>

			<!-- Behavior -->
			<section class="settings-section">
				<h3 class="section-heading">Behavior</h3>

				<div class="setting-row">
					<div class="setting-info">
						<span class="setting-name">Auto-merge Results</span>
						<span class="setting-desc">Automatically merge head outputs when complete</span>
					</div>
					<button
						class="toggle"
						class:on={autoMerge}
						onclick={() => autoMerge = !autoMerge}
						role="switch"
						aria-checked={autoMerge}
					>
						<span class="toggle-track"><span class="toggle-thumb"></span></span>
					</button>
				</div>

				<div class="setting-row">
					<div class="setting-info">
						<span class="setting-name">Cross-Head Reviews</span>
						<span class="setting-desc">Have heads review each other's output</span>
					</div>
					<button
						class="toggle"
						class:on={reviewsHeads}
						onclick={() => reviewsHeads = !reviewsHeads}
						role="switch"
						aria-checked={reviewsHeads}
					>
						<span class="toggle-track"><span class="toggle-thumb"></span></span>
					</button>
				</div>

				<div class="setting-row">
					<div class="setting-info">
						<span class="setting-name">Isolate Heads</span>
						<span class="setting-desc">Run heads in isolated contexts (more tokens, safer)</span>
					</div>
					<button
						class="toggle"
						class:on={isolatesHeads}
						onclick={() => isolatesHeads = !isolatesHeads}
						role="switch"
						aria-checked={isolatesHeads}
					>
						<span class="toggle-track"><span class="toggle-thumb"></span></span>
					</button>
				</div>

				<div class="setting-row">
					<div class="setting-info">
						<span class="setting-name">Require Approval</span>
						<span class="setting-desc">Show landing preview before applying head outputs</span>
					</div>
					<button
						class="toggle"
						class:on={requireApproval}
						onclick={() => requireApproval = !requireApproval}
						role="switch"
						aria-checked={requireApproval}
					>
						<span class="toggle-track"><span class="toggle-thumb"></span></span>
					</button>
				</div>
			</section>

			<!-- Preview -->
			<section class="settings-section">
				<h3 class="section-heading">Preview</h3>
				<div class="preview-card">
					<div class="preview-icon">
						<svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
							<path d="M12 2l2 4 4 1-3 3 1 4-4-2-4 2 1-4-3-3 4-1z"/>
						</svg>
					</div>
					<h4 class="preview-title">When you launch a Hydra swarm:</h4>
					<ul class="preview-list">
						<li>{maxHeads} parallel heads will explore different approaches</li>
						<li>Coordinator: <code>{defaultOrchestrator}</code></li>
						<li>Workers: <code>{defaultWorker}</code></li>
						<li>{autoMerge ? '✓' : '✗'} Auto-merge when complete</li>
						<li>{reviewsHeads ? '✓' : '✗'} Heads review each other</li>
						<li>{isolatesHeads ? '✓' : '✗'} Isolated contexts</li>
						<li>{requireApproval ? '✓' : '✗'} Require approval before landing</li>
						<li>Timeout: {timeoutMinutes} minutes</li>
					</ul>
				</div>
			</section>
		</div>
	{/if}
</div>

<style>
	.hydra-settings {
		height: 100%;
		overflow-y: auto;
		padding: var(--space-6) var(--space-8);
		display: flex;
		flex-direction: column;
		gap: var(--space-5);
		max-width: 680px;
	}

	.settings-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding-bottom: var(--space-4);
		border-bottom: var(--border-1) var(--border-color-1);
	}

	.header-info {
		display: flex;
		flex-direction: column;
		gap: 2px;
	}

	.settings-title {
		font-size: var(--font-size-xl);
		font-weight: 700;
		color: var(--text-primary);
	}

	.header-desc {
		font-size: var(--font-size-sm);
		color: var(--text-tertiary);
	}

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

	.form-input {
		padding: 6px 10px;
		border: var(--border-1) var(--border-color-1);
		background: var(--surface-2);
		border-radius: var(--radius-sm);
		font-size: var(--font-size-sm);
		color: var(--text-primary);
		outline: none;
		font-family: var(--font-system);
		width: 200px;
	}

	.form-input:focus {
		border-color: var(--accent-1);
	}

	.preview-card {
		background: var(--surface-2);
		border: var(--border-1) var(--border-color-1);
		border-radius: var(--radius-md);
		padding: var(--space-4);
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}

	.preview-icon {
		color: var(--accent-1);
	}

	.preview-title {
		font-size: var(--font-size-sm);
		font-weight: 600;
		color: var(--text-primary);
	}

	.preview-list {
		list-style: none;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 4px;
	}

	.preview-list li {
		font-size: var(--font-size-xs);
		color: var(--text-secondary);
		padding: 2px 0;
	}

	.preview-list code {
		font-family: var(--font-mono);
		font-size: 11px;
		background: var(--surface-3);
		padding: 1px 5px;
		border-radius: 3px;
		color: var(--accent-1);
	}

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

	.btn-primary:hover:not(:disabled) {
		background: var(--accent-2);
	}

	.btn-primary:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}
</style>
