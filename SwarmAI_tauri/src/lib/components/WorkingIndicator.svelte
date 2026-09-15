<script lang="ts">
	import { onMount } from 'svelte';
	import type { WorkingIndicatorState } from '$lib/types';

	interface Props {
		headId?: string;
		persona?: string;
		state: WorkingIndicatorState;
		task?: string;
		progress?: number;
		onCancel?: () => void;
	}

	let { headId = '', persona = 'Agent', state, task = 'Working…', progress = 0, onCancel }: Props = $props();

	let elapsed = $state(0);
	let timerInterval: number | null = null;

	$effect(() => {
		if (state === 'running') {
			elapsed = 0;
			timerInterval = window.setInterval(() => {
				elapsed += 1;
			}, 1000);
		} else {
			if (timerInterval) {
				clearInterval(timerInterval);
				timerInterval = null;
			}
		}

		return () => {
			if (timerInterval) clearInterval(timerInterval);
		};
	});

	function formatElapsed(seconds: number): string {
		const m = Math.floor(seconds / 60);
		const s = seconds % 60;
		return `${m}:${s.toString().padStart(2, '0')}`;
	}

	let displayTask = $derived(task.length > 60 ? task.slice(0, 57) + '…' : task);

	function getStateLabel(s: WorkingIndicatorState): string {
		switch (s) {
			case 'thinking': return 'Thinking';
			case 'searching': return 'Searching';
			case 'planning': return 'Planning';
			case 'working': return 'Working';
			case 'spawning': return 'Spawning';
			case 'reviewing': return 'Reviewing';
			case 'writing': return 'Writing';
			case 'running': return 'Running';
			case 'done': return 'Complete';
			case 'error': return 'Error';
			default: return s;
		}
	}

	let stateColor = $derived(() => {
		switch (state) {
			case 'thinking': return 'var(--accent-1)';
			case 'searching': return 'var(--info)';
			case 'planning': return 'var(--accent-1)';
			case 'working': return 'var(--warning)';
			case 'spawning': return 'var(--info)';
			case 'reviewing': return 'var(--warning)';
			case 'writing': return 'var(--success)';
			case 'running': return 'var(--accent-1)';
			case 'done': return 'var(--success)';
			case 'error': return 'var(--danger)';
			default: return 'var(--text-tertiary)';
		}
	});
</script>

<div class="working-indicator state-{state}">
	<div class="indicator-main">
		<div class="indicator-glyph">
			{#if state === 'done'}
				<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
					<path d="M20 6L9 17l-5-5"/>
				</svg>
			{:else if state === 'error'}
				<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
					<path d="M18 6L6 18M6 6l12 12"/>
				</svg>
			{:else}
				<div class="spinner-ring"></div>
			{/if}
		</div>
		<div class="indicator-body">
			<div class="indicator-top">
				<span class="persona-name">{persona}</span>
				<span class="state-label" style="color: {stateColor()};">{getStateLabel(state)}</span>
				<span class="elapsed">({formatElapsed(elapsed)})</span>
			</div>
			<div class="indicator-task">{displayTask}</div>
			{#if progress > 0 && progress < 100}
				<div class="progress-bar">
					<div class="progress-fill" style="width: {progress}%"></div>
				</div>
			{/if}
		</div>
	</div>
	{#if onCancel && state !== 'done' && state !== 'error'}
		<button class="cancel-btn" onclick={onCancel} title="Cancel">
			<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
				<path d="M18 6L6 18M6 6l12 12"/>
			</svg>
		</button>
	{/if}
</div>

<style>
	.working-indicator {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 10px 14px;
		background: var(--surface-2);
		border: var(--border-1) var(--border-color-1);
		border-radius: var(--radius-md);
		gap: var(--space-3);
		max-width: 400px;
	}

	.indicator-main {
		display: flex;
		align-items: flex-start;
		gap: var(--space-3);
		flex: 1;
		min-width: 0;
	}

	.indicator-glyph {
		width: 20px;
		height: 20px;
		display: flex;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
		margin-top: 2px;
	}

	.spinner-ring {
		width: 14px;
		height: 14px;
		border: 2px solid var(--accent-3);
		border-top-color: var(--accent-1);
		border-radius: 50%;
		animation: spin 0.7s linear infinite;
	}

	.indicator-body {
		flex: 1;
		min-width: 0;
	}

	.indicator-top {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		margin-bottom: 2px;
	}

	.persona-name {
		font-size: var(--font-size-xs);
		font-weight: 600;
		color: var(--text-primary);
	}

	.state-label {
		font-size: var(--font-size-xs);
		font-weight: 500;
		text-transform: capitalize;
	}

	.elapsed {
		font-size: 10px;
		font-family: var(--font-mono);
		color: var(--text-tertiary);
	}

	.indicator-task {
		font-size: var(--font-size-xs);
		color: var(--text-secondary);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.progress-bar {
		height: 2px;
		background: var(--surface-3);
		border-radius: var(--radius-full);
		margin-top: var(--space-2);
		overflow: hidden;
	}

	.progress-fill {
		height: 100%;
		background: var(--accent-1);
		border-radius: var(--radius-full);
		transition: width var(--transition-base);
	}

	.cancel-btn {
		width: 22px;
		height: 22px;
		border: none;
		background: transparent;
		border-radius: var(--radius-sm);
		color: var(--text-tertiary);
		cursor: pointer;
		display: flex;
		align-items: center;
		justify-content: center;
		transition: all var(--transition-fast);
		flex-shrink: 0;
	}

	.cancel-btn:hover {
		background: rgba(255, 59, 48, 0.15);
		color: var(--danger);
	}

	@keyframes spin {
		to { transform: rotate(360deg); }
	}
</style>
