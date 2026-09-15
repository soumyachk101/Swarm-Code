<script lang="ts">
	import { getHydra, getHydras, launchHydraRun, stopHydraHead, landHydraHead, deleteHydra } from '$lib/api/commands';
	import { appStore } from '$lib/stores/appStore';
	import type { HydraHeadInfo, HydraPair } from '$lib/types';
	import HydraGlyph from './HydraGlyph.svelte';

	interface Props {
		projectId: string | null;
		onClose?: () => void;
	}

	let { projectId = null, onClose }: Props = $props();

	let hydras = $state<HydraPair[]>([]);
	let selectedHydra = $state<HydraPair | null>(null);
	let showCreateForm = $state(false);
	let newHydraName = $state('');
	let newHydraHeads = $state(2);
	let isExpanded = $state(true);

	$effect(() => {
		loadHydras();
	});

	async function loadHydras() {
		try {
			hydras = await getHydras(projectId);
		} catch (e) {
			console.error('Failed to load hydras:', e);
		}
	}

	async function handleCreateHydra() {
		if (!newHydraName.trim()) return;
		try {
			await launchHydraRun(projectId, newHydraName.trim(), newHydraHeads);
			newHydraName = '';
			newHydraHeads = 2;
			showCreateForm = false;
			await loadHydras();
		} catch (e) {
			console.error('Failed to create hydra:', e);
		}
	}

	async function handleStopHead(headId: string) {
		try {
			await stopHydraHead(headId as any);
			await loadHydras();
		} catch (e) {
			console.error('Failed to stop head:', e);
		}
	}

	async function handleLandHead(headId: string) {
		try {
			await landHydraHead(headId as any);
			await loadHydras();
		} catch (e) {
			console.error('Failed to land head:', e);
		}
	}

	async function handleDeleteHydra(hydraId: string) {
		try {
			await deleteHydra(hydraId as any);
			if (selectedHydra?.id === hydraId) {
				selectedHydra = null;
			}
			await loadHydras();
		} catch (e) {
			console.error('Failed to delete hydra:', e);
		}
	}

	function getHeadStatusColor(status: string): string {
		switch (status) {
			case 'running': return 'var(--success)';
			case 'thinking': return 'var(--accent-1)';
			case 'speaking': return 'var(--warning)';
			case 'done': return 'var(--text-tertiary)';
			case 'error': return 'var(--danger)';
			default: return 'var(--text-tertiary)';
		}
	}

	function formatTime(dateStr: string | undefined): string {
		if (!dateStr) return '—';
		const date = new Date(dateStr);
		return date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
	}
</script>

<div class="hydra-panel" class:expanded={isExpanded}>
	<div class="panel-header">
		<div class="panel-title" onclick={() => isExpanded = !isExpanded}>
			<HydraGlyph size={16} state="idle" />
			<span>Hydra Swarms</span>
			<span class="count-badge">{hydras.length}</span>
		</div>
		<div class="panel-actions">
			{#if !showCreateForm}
				<button class="icon-btn" onclick={() => showCreateForm = true} title="Create Hydra">
					<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
						<path d="M12 5v14M5 12h14"/>
					</svg>
				</button>
			{/if}
			{#if onClose}
				<button class="icon-btn" onclick={onClose} title="Close">
					<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
						<path d="M18 6L6 18M6 6l12 12"/>
					</svg>
				</button>
			{/if}
		</div>
	</div>

	{#if isExpanded}
		<div class="panel-content">
			<!-- Create Form -->
			{#if showCreateForm}
				<div class="create-form">
					<input
						type="text"
						class="form-input"
						placeholder="Hydra name (e.g., Explore Options…)"
						value={newHydraName}
						oninput={(e) => newHydraName = e.currentTarget.value}
					/>
					<div class="head-count-row">
						<span class="label">Heads:</span>
						<div class="head-count-options">
							{#each [2, 3, 4, 5] as n}
								<button
									class="count-btn"
									class:active={newHydraHeads === n}
									onclick={() => newHydraHeads = n}
								>
									{n}
								</button>
							{/each}
						</div>
					</div>
					<div class="form-actions">
						<button class="create-btn" onclick={handleCreateHydra} disabled={!newHydraName.trim()}>
							Launch
						</button>
						<button class="cancel-btn" onclick={() => { showCreateForm = false; newHydraName = ''; }}>
							Cancel
						</button>
					</div>
				</div>
			{/if}

			<!-- Hydra List -->
			{#if hydras.length === 0 && !showCreateForm}
				<div class="empty-hydras">
					<HydraGlyph size={32} color="var(--text-tertiary)" />
					<p>No active hydras.</p>
					<span>Create one to explore multiple approaches simultaneously.</span>
				</div>
			{:else}
				{#each hydras as hydra (hydra.id)}
					<div class="hydra-card" class:selected={selectedHydra?.id === hydra.id}>
						<div
							class="hydra-card-header"
							onclick={() => selectedHydra = selectedHydra?.id === hydra.id ? null : hydra}
						>
							<div class="hydra-card-title">
								<HydraGlyph size={14} state={hydra.status === 'running' ? 'thinking' : 'idle'} />
								<span>{hydra.name || hydra.id.slice(0, 8)}</span>
							</div>
							<div class="hydra-card-meta">
								<span class="hydra-status" style="color: {getHeadStatusColor(hydra.status)}">
									{hydra.status}
								</span>
								<span class="hydra-time">{formatTime(hydra.updatedAt)}</span>
							</div>
						</div>

						{#if selectedHydra?.id === hydra.id}
							<div class="hydra-card-detail">
								<!-- Head list would go here -->
								<div class="head-list">
									{#if hydra.heads}
										{#each hydra.heads as head}
											<div class="head-item">
												<span class="head-status-dot" style="background: {getHeadStatusColor(head.status)}"></span>
												<span class="head-name">{head.persona || 'Head'}</span>
												<span class="head-kind">{head.kind}</span>
												<span class="head-origin">{head.origin}</span>
												{#if head.status === 'running'}
													<button class="head-action" onclick={() => handleStopHead(head.id)} title="Stop">
														<svg width="10" height="10" viewBox="0 0 24 24" fill="currentColor">
															<rect x="6" y="6" width="12" height="12" rx="2"/>
														</svg>
													</button>
												{/if}
												{#if head.status === 'done'}
													<button class="head-action" onclick={() => handleLandHead(head.id)} title="Land">
														<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
															<path d="M20 6L9 17l-5-5"/>
														</svg>
													</button>
												{/if}
											</div>
										{/each}
									{:else}
										<span class="no-heads">No heads spawned</span>
									{/if}
								</div>
								<div class="hydra-actions">
									<button class="danger-btn" onclick={() => handleDeleteHydra(hydra.id)}>
										<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
											<path d="M3 6h18M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/>
										</svg>
										Delete
									</button>
								</div>
							</div>
						{/if}
					</div>
				{/each}
			{/if}
		</div>
	{/if}
</div>

<style>
	.hydra-panel {
		background: var(--surface-2);
		border-left: var(--border-1) var(--border-color-1);
		display: flex;
		flex-direction: column;
		width: 320px;
		flex-shrink: 0;
		overflow: hidden;
	}

	.panel-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: var(--space-3) var(--space-4);
		border-bottom: var(--border-1) var(--border-color-2);
		flex-shrink: 0;
	}

	.panel-title {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		font-size: var(--font-size-sm);
		font-weight: 600;
		color: var(--text-primary);
		cursor: pointer;
		user-select: none;
	}

	.panel-title svg {
		transition: transform var(--transition-fast);
	}

	.expanded .panel-title svg {
		transform: rotate(0);
	}

	.count-badge {
		font-size: 10px;
		font-weight: 600;
		background: var(--surface-3);
		color: var(--text-secondary);
		padding: 1px 7px;
		border-radius: var(--radius-full);
	}

	.panel-actions {
		display: flex;
		align-items: center;
		gap: var(--space-1);
	}

	.icon-btn {
		width: 24px;
		height: 24px;
		border: none;
		background: transparent;
		border-radius: var(--radius-md);
		color: var(--text-tertiary);
		cursor: pointer;
		display: flex;
		align-items: center;
		justify-content: center;
		transition: all var(--transition-fast);
	}

	.icon-btn:hover {
		background: var(--surface-3);
		color: var(--text-primary);
	}

	.panel-content {
		flex: 1;
		overflow-y: auto;
		padding: var(--space-3);
	}

	.create-form {
		padding: var(--space-3);
		background: var(--surface-3);
		border-radius: var(--radius-md);
		margin-bottom: var(--space-3);
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}

	.form-input {
		width: 100%;
		padding: 6px 10px;
		border: var(--border-1) var(--border-color-1);
		background: var(--surface-1);
		border-radius: var(--radius-sm);
		font-size: var(--font-size-xs);
		color: var(--text-primary);
		outline: none;
		font-family: var(--font-system);
	}

	.form-input:focus {
		border-color: var(--accent-1);
	}

	.head-count-row {
		display: flex;
		align-items: center;
		gap: var(--space-2);
	}

	.head-count-row .label {
		font-size: var(--font-size-xs);
		color: var(--text-secondary);
		flex-shrink: 0;
	}

	.head-count-options {
		display: flex;
		gap: 3px;
	}

	.count-btn {
		padding: 3px 10px;
		border: var(--border-1) var(--border-color-1);
		background: var(--surface-1);
		border-radius: var(--radius-sm);
		font-size: var(--font-size-xs);
		color: var(--text-secondary);
		cursor: pointer;
		transition: all var(--transition-fast);
	}

	.count-btn.active {
		background: var(--accent-1);
		color: var(--text-inverse);
		border-color: var(--accent-1);
	}

	.form-actions {
		display: flex;
		gap: var(--space-2);
	}

	.create-btn {
		flex: 1;
		padding: 6px;
		border: none;
		background: var(--accent-1);
		color: var(--text-inverse);
		border-radius: var(--radius-sm);
		font-size: var(--font-size-xs);
		font-weight: 500;
		cursor: pointer;
		transition: background var(--transition-fast);
	}

	.create-btn:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}

	.cancel-btn {
		flex: 1;
		padding: 6px;
		border: var(--border-1) var(--border-color-1);
		background: none;
		border-radius: var(--radius-sm);
		font-size: var(--font-size-xs);
		color: var(--text-secondary);
		cursor: pointer;
	}

	.empty-hydras {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		padding: var(--space-8) var(--space-4);
		text-align: center;
		color: var(--text-tertiary);
		gap: var(--space-2);
	}

	.empty-hydras p {
		font-size: var(--font-size-sm);
		font-weight: 500;
		color: var(--text-secondary);
	}

	.empty-hydras span {
		font-size: var(--font-size-xs);
	}

	.hydra-card {
		border: var(--border-1) var(--border-color-1);
		border-radius: var(--radius-md);
		margin-bottom: var(--space-2);
		overflow: hidden;
		transition: border-color var(--transition-fast);
	}

	.hydra-card.selected {
		border-color: var(--accent-1);
	}

	.hydra-card-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: var(--space-3);
		cursor: pointer;
		background: var(--surface-3);
		transition: background var(--transition-fast);
	}

	.hydra-card:hover .hydra-card-header {
		background: var(--surface-4);
	}

	.hydra-card-title {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		font-size: var(--font-size-xs);
		font-weight: 500;
		color: var(--text-primary);
	}

	.hydra-card-meta {
		display: flex;
		align-items: center;
		gap: var(--space-2);
	}

	.hydra-status {
		font-size: 10px;
		font-weight: 500;
		text-transform: capitalize;
	}

	.hydra-time {
		font-size: 10px;
		color: var(--text-tertiary);
	}

	.hydra-card-detail {
		padding: var(--space-3);
		border-top: var(--border-1) var(--border-color-2);
		background: var(--surface-1);
	}

	.head-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}

	.head-item {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		padding: 4px var(--space-2);
		font-size: var(--font-size-xs);
		color: var(--text-secondary);
	}

	.head-status-dot {
		width: 6px;
		height: 6px;
		border-radius: 50%;
		flex-shrink: 0;
	}

	.head-name {
		flex: 1;
		font-weight: 500;
		color: var(--text-primary);
	}

	.head-kind {
		font-size: 10px;
		color: var(--text-tertiary);
		font-family: var(--font-mono);
		text-transform: uppercase;
	}

	.head-origin {
		font-size: 10px;
		color: var(--text-tertiary);
	}

	.no-heads {
		font-size: var(--font-size-xs);
		color: var(--text-tertiary);
		padding: var(--space-2);
	}

	.head-action {
		width: 18px;
		height: 18px;
		border: none;
		background: transparent;
		border-radius: var(--radius-sm);
		color: var(--text-tertiary);
		cursor: pointer;
		display: flex;
		align-items: center;
		justify-content: center;
		transition: all var(--transition-fast);
	}

	.head-action:hover {
		background: var(--surface-3);
		color: var(--text-primary);
	}

	.hydra-actions {
		display: flex;
		justify-content: flex-end;
		padding-top: var(--space-2);
		margin-top: var(--space-2);
		border-top: var(--border-1) var(--border-color-2);
	}

	.danger-btn {
		display: flex;
		align-items: center;
		gap: var(--space-1);
		padding: 4px 10px;
		border: var(--border-1) rgba(255, 59, 48, 0.2);
		background: rgba(255, 59, 48, 0.08);
		border-radius: var(--radius-sm);
		font-size: var(--font-size-xs);
		color: var(--danger);
		cursor: pointer;
		transition: all var(--transition-fast);
	}

	.danger-btn:hover {
		background: rgba(255, 59, 48, 0.15);
	}

	/* Scrollbar */
	.panel-content::-webkit-scrollbar {
		width: 5px;
	}

	.panel-content::-webkit-scrollbar-track {
		background: transparent;
	}

	.panel-content::-webkit-scrollbar-thumb {
		background: var(--surface-4);
		border-radius: var(--radius-full);
	}
</style>
