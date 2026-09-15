<script lang="ts">
	import { onMount } from 'svelte';
	import HydraGlyph from './HydraGlyph.svelte';
	import { appStore } from '$lib/stores/appStore';
	import type { HydraHeadInfo } from '$lib/types';

	interface Props {
		threadId: string;
		isExpanded?: boolean;
	}

	let { threadId, isExpanded = false }: Props = $props();

	let heads = $state<HydraHeadInfo[]>([]);
	let selectedHead = $state<HydraHeadInfo | null>(null);
	let showDetail = $state(false);

	let thread = $derived($appStore.threads.find((t) => t.id === threadId) ?? null);

	let hydra = $derived(thread?.hydra ?? null);
	let isHydraRunning = $derived(
		thread?.hydra_enabled && thread?.last_status === 'running'
	);

	let statusColor = (status: string): string => {
		switch (status) {
			case 'running':
			case 'thinking':
			case 'spawning':
				return 'var(--accent-1)';
			case 'completed':
			case 'done':
				return 'var(--success)';
			case 'failed':
			case 'error':
				return 'var(--danger)';
			case 'stopped':
			case 'cancelled':
				return 'var(--text-tertiary)';
			default:
				return 'var(--text-tertiary)';
		}
	};

	function getHeadStatusLabel(status: string): string {
		switch (status) {
			case 'running':
				return 'Running';
			case 'thinking':
				return 'Thinking';
			case 'spawning':
				return 'Spawning';
			case 'completed':
			case 'done':
				return 'Done';
			case 'failed':
			case 'error':
				return 'Error';
			case 'stopped':
				return 'Stopped';
			default:
				return status;
		}
	}

	function getHeadPersona(index: number): string {
		const names = [
			'Hank', 'Walter', 'Ada', 'Otto', 'Nova', 'Remy',
			'Iris', 'Milo', 'Juno', 'Ezra', 'Lena', 'Bo',
			'Kai', 'Vera', 'Finn', 'Mira', 'Odin', 'Suki',
			'Rex', 'Zola'
		];
		return names[index % names.length];
	}

	function getHeadColor(index: number): string {
		const colors = [
			'#FF8A3D', '#3D8BFF', '#34C46A', '#A35BE0', '#F25C9A',
			'#2BB5B0', '#E8B430', '#E84F4F', '#6A5CFF', '#4FD1A1',
			'#2FB8E6', '#B0784A', '#8FD14F', '#D946EF', '#F97316',
			'#C084FC', '#B45309', '#F472B6', '#2563EB', '#65A30D'
		];
		return colors[index % colors.length];
	}

	function formatDuration(ms: number | null | undefined): string {
		if (!ms) return '—';
		const s = Math.floor(ms / 1000);
		const m = Math.floor(s / 60);
		if (m > 0) return `${m}m ${s % 60}s`;
		return `${s}s`;
	}

	$effect(() => {
		if (hydra && Array.isArray(hydra)) {
			heads = hydra as HydraHeadInfo[];
		} else if (hydra && !Array.isArray(hydra)) {
			heads = [hydra as HydraHeadInfo];
		}
	});

	$effect(() => {
		if (!isExpanded) {
			selectedHead = null;
			showDetail = false;
		}
	});
</script>

<div class="subagent-panel" class:expanded={isExpanded} class:running={isHydraRunning}>
	{#if !isExpanded}
		<button
			class="collapse-bar"
			onclick={() => {}}
			type="button"
		>
			<HydraGlyph size={14} state={isHydraRunning ? 'running' : 'idle'} />
			<span class="collapse-label">
				{#if isHydraRunning}
					<span class="pulse-dot"></span>
					Hydra Active — {heads.length} heads
				{:else}
					Subagents
				{/if}
			</span>
		</button>
	{:else}
		<div class="panel-body">
			<!-- Header -->
			<div class="panel-header">
				<div class="header-left">
					<HydraGlyph
						size={16}
						state={isHydraRunning ? 'running' : 'idle'}
					/>
					<span class="panel-title">Subagents</span>
					{#if isHydraRunning}
						<span class="live-badge">LIVE</span>
					{/if}
				</div>
				<span class="head-count-badge">{heads.length}</span>
			</div>

			<!-- Heads list -->
			<div class="heads-list">
				{#if heads.length === 0}
					<div class="empty-hydra">
						<HydraGlyph size={28} color="var(--text-tertiary)" />
						<p class="empty-text">No active subagents</p>
						<span class="empty-hint">Launch a Hydra swarm to see heads here</span>
					</div>
				{:else}
					{#each heads as head, idx (head.native_id || head.index || idx)}
						{@const persona = getHeadPersona(head.index ?? idx)}
						{@const hColor = getHeadColor(head.index ?? idx)}
						<button
							class="head-card"
							class:selected={selectedHead?.index === head.index && selectedHead?.native_id === head.native_id}
							class:completed={head.status === 'completed'}
							class:error={head.status === 'failed' || head.status === 'error'}
							onclick={() => {
								selectedHead = selectedHead?.index === head.index && selectedHead?.native_id === head.native_id ? null : head;
								showDetail = selectedHead !== null;
							}}
							type="button"
						>
							<div class="head-indicator" style="background: {hColor}20; color: {hColor}">
								<span class="persona-letter">{persona[0]}</span>
							</div>

							<div class="head-info">
								<div class="head-top-row">
									<span class="persona-name">{persona}</span>
									<span class="status-dot" style="background: {statusColor(head.status)}"></span>
									<span class="status-label" style="color: {statusColor(head.status)}">
										{getHeadStatusLabel(head.status)}
									</span>
								</div>

								{#if head.activity}
									<p class="head-activity">{head.activity}</p>
								{/if}

								{#if head.summary}
									<p class="head-summary">{head.summary}</p>
								{/if}
							</div>

							<div class="head-meta">
								<span class="head-tokens">{head.tokens ?? 0} tok</span>
								<span class="head-tools">{head.tool_calls ?? 0} tools</span>
							</div>
						</button>

						<!-- Expanded detail -->
						{#if showDetail && selectedHead?.index === head.index && selectedHead?.native_id === head.native_id}
							<div class="head-detail">
								{#if head.landing}
									<div class="detail-section">
										<h4 class="detail-label">Landing</h4>
										{#if head.landing.error}
											<p class="detail-error">{head.landing.error}</p>
										{:else if head.landing.files?.length}
											<div class="landing-files">
												{#each head.landing.files as file (file.path)}
													<div class="landing-file">
														<span class="file-path">{file.path}</span>
														<span class="file-changes">+{file.additions} -{file.deletions}</span>
													</div>
												{/each}
											</div>
										{:else}
											<span class="detail-none">No files modified</span>
										{/if}
									</div>
								{/if}

								{#if head.summary}
									<div class="detail-section">
										<h4 class="detail-label">Summary</h4>
										<p class="detail-summary">{head.summary}</p>
									</div>
								{/if}
							</div>
						{/if}
					{/each}
				{/if}
			</div>
		</div>
	{/if}
</div>

<style>
	.subagent-panel {
		background: var(--surface-2);
		border-left: var(--border-1) var(--border-color-1);
		width: 300px;
		flex-shrink: 0;
		overflow: hidden;
		display: flex;
		flex-direction: column;
	}

	/* Collapsed bar */
	.collapse-bar {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		padding: var(--space-3) var(--space-4);
		border: none;
		background: var(--surface-3);
		border-bottom: var(--border-1) var(--border-color-2);
		cursor: pointer;
		transition: background var(--transition-fast);
	}

	.collapse-bar:hover {
		background: var(--surface-4);
	}

	.collapse-label {
		font-size: var(--font-size-xs);
		font-weight: 600;
		color: var(--text-secondary);
		display: flex;
		align-items: center;
		gap: var(--space-1);
	}

	.pulse-dot {
		width: 6px;
		height: 6px;
		border-radius: 50%;
		background: var(--success);
		animation: pulse-dot 1.2s ease-in-out infinite;
	}

	@keyframes pulse-dot {
		0%, 100% { opacity: 1; transform: scale(1); }
		50% { opacity: 0.4; transform: scale(0.7); }
	}

	/* Expanded panel */
	.panel-body {
		display: flex;
		flex-direction: column;
		flex: 1;
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

	.header-left {
		display: flex;
		align-items: center;
		gap: var(--space-2);
	}

	.panel-title {
		font-size: var(--font-size-sm);
		font-weight: 600;
		color: var(--text-primary);
	}

	.live-badge {
		font-size: 9px;
		font-weight: 700;
		padding: 1px 6px;
		border-radius: var(--radius-full);
		background: rgba(48, 209, 88, 0.15);
		color: var(--success);
		letter-spacing: 0.5px;
		animation: pulse-badge 1.5s ease-in-out infinite;
	}

	@keyframes pulse-badge {
		0%, 100% { opacity: 1; }
		50% { opacity: 0.7; }
	}

	.head-count-badge {
		font-size: 10px;
		font-weight: 600;
		background: var(--surface-3);
		color: var(--text-secondary);
		padding: 1px 7px;
		border-radius: var(--radius-full);
	}

	/* Heads list */
	.heads-list {
		flex: 1;
		overflow-y: auto;
		padding: var(--space-3);
	}

	.empty-hydra {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		padding: var(--space-8) var(--space-4);
		text-align: center;
		gap: var(--space-2);
		color: var(--text-tertiary);
	}

	.empty-text {
		font-size: var(--font-size-sm);
		color: var(--text-secondary);
		margin-top: var(--space-2);
	}

	.empty-hint {
		font-size: var(--font-size-xs);
	}

	/* Head cards */
	.head-card {
		display: flex;
		align-items: flex-start;
		gap: var(--space-3);
		width: 100%;
		padding: var(--space-3);
		margin-bottom: var(--space-2);
		border: var(--border-1) var(--border-color-1);
		background: var(--surface-3);
		border-radius: var(--radius-md);
		cursor: pointer;
		transition: all var(--transition-fast);
		text-align: left;
	}

	.head-card:hover {
		background: var(--surface-4);
		border-color: var(--accent-1);
	}

	.head-card.selected {
		background: var(--accent-3);
		border-color: var(--accent-1);
	}

	.head-card.completed {
		border-color: rgba(48, 209, 88, 0.2);
	}

	.head-card.error {
		border-color: rgba(255, 59, 48, 0.2);
	}

	.head-indicator {
		width: 28px;
		height: 28px;
		border-radius: var(--radius-sm);
		display: flex;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
	}

	.persona-letter {
		font-size: 12px;
		font-weight: 700;
	}

	.head-info {
		flex: 1;
		min-width: 0;
	}

	.head-top-row {
		display: flex;
		align-items: center;
		gap: var(--space-1);
		margin-bottom: 2px;
	}

	.persona-name {
		font-size: var(--font-size-xs);
		font-weight: 600;
		color: var(--text-primary);
	}

	.status-dot {
		width: 6px;
		height: 6px;
		border-radius: 50%;
		flex-shrink: 0;
	}

	.status-dot.running,
	.status-dot.thinking,
	.status-dot.spawning {
		animation: pulse-dot 1.2s ease-in-out infinite;
	}

	.status-label {
		font-size: 10px;
		font-weight: 500;
		text-transform: capitalize;
	}

	.head-activity {
		font-size: 11px;
		color: var(--text-secondary);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.head-summary {
		font-size: 11px;
		color: var(--text-tertiary);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.head-meta {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 2px;
		flex-shrink: 0;
	}

	.head-tokens,
	.head-tools {
		font-size: 10px;
		font-family: var(--font-mono);
		color: var(--text-tertiary);
	}

	/* Detail panel */
	.head-detail {
		margin-top: var(--space-1);
		padding: var(--space-3);
		background: var(--surface-2);
		border-radius: var(--radius-sm);
		border: var(--border-1) var(--border-color-2);
		margin-bottom: var(--space-2);
	}

	.detail-section {
		margin-bottom: var(--space-3);
	}

	.detail-section:last-child {
		margin-bottom: 0;
	}

	.detail-label {
		font-size: 10px;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.3px;
		color: var(--text-tertiary);
		margin-bottom: var(--space-2);
	}

	.detail-error {
		font-size: var(--font-size-xs);
		color: var(--danger);
		font-style: italic;
	}

	.detail-summary {
		font-size: var(--font-size-xs);
		color: var(--text-secondary);
		line-height: 1.5;
	}

	.detail-none {
		font-size: var(--font-size-xs);
		color: var(--text-tertiary);
		font-style: italic;
	}

	.landing-files {
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}

	.landing-file {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 3px 6px;
		background: var(--surface-1);
		border-radius: var(--radius-sm);
	}

	.file-path {
		font-size: 11px;
		font-family: var(--font-mono);
		color: var(--text-primary);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.file-changes {
		font-size: 10px;
		font-family: var(--font-mono);
		color: var(--text-tertiary);
		flex-shrink: 0;
		margin-left: var(--space-2);
	}

	/* Scrollbar */
	.heads-list::-webkit-scrollbar {
		width: 5px;
	}

	.heads-list::-webkit-scrollbar-track {
		background: transparent;
	}

	.heads-list::-webkit-scrollbar-thumb {
		background: var(--surface-4);
		border-radius: var(--radius-full);
	}
</style>
