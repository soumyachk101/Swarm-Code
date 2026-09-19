<script lang="ts">
	import type { ChatThread } from '$lib/types';

	interface Props {
		thread: ChatThread;
	}

	let { thread }: Props = $props();

	let statusClass = $derived.by(() => {
		if (thread.last_status === 'running') return 'status-running';
		return 'status-idle';
	});

	function formatDate(dateStr: string): string {
		const d = new Date(dateStr);
		return d.toLocaleDateString('en-US', {
			month: 'short',
			day: 'numeric',
			year: 'numeric',
			hour: '2-digit',
			minute: '2-digit'
		});
	}
</script>

<div class="thread-detail-bar">
	<div class="detail-left">
		{#if thread.provider}
			<span class="detail-badge provider-badge">{thread.provider}</span>
		{/if}
		{#if thread.model}
			<span class="detail-badge model-badge">{thread.model}</span>
		{/if}
		{#if thread.branch}
			<span class="detail-badge branch-badge">
				<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
					<path d="M6 3v12"/>
					<circle cx="18" cy="6" r="3"/>
					<circle cx="6" cy="18" r="3"/>
					<path d="M18 9a9 9 0 0 1-9 9"/>
				</svg>
				{thread.branch}
			</span>
		{/if}
		{#if thread.effort}
			<span class="detail-badge effort-badge">effort: {thread.effort}</span>
		{/if}
		<span class="detail-separator">•</span>
		<span class="detail-date">{formatDate(thread.created_at)}</span>
	</div>

	<div class="detail-right">
		<span class="detail-status {statusClass}">
			{#if thread.last_status === 'running'}
				<span class="status-dot"></span>
				Running
			{:else}
				Idle
			{/if}
		</span>
		{#if thread.hydra_enabled}
			<span class="detail-badge hydra-badge">
				<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
					<path d="M12 2l2 4 4 1-3 3 1 4-4-2-4 2 1-4-3-3 4-1z"/>
				</svg>
				hydra
			</span>
		{/if}
		{#if thread.runtime_mode}
			<span class="detail-badge mode-badge">{thread.runtime_mode}</span>
		{/if}
	</div>
</div>

<style>
	.thread-detail-bar {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 6px var(--space-3);
		border-bottom: var(--border-1) var(--border-color-2);
		background: var(--surface-2);
		flex-shrink: 0;
		min-height: 32px;
		gap: var(--space-2);
	}

	.detail-left,
	.detail-right {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		min-width: 0;
	}

	.detail-right {
		flex-shrink: 0;
	}

	.detail-badge {
		display: inline-flex;
		align-items: center;
		gap: 3px;
		padding: 2px 8px;
		border-radius: var(--radius-full);
		font-size: 10px;
		font-weight: 500;
		white-space: nowrap;
		font-family: var(--font-system);
		letter-spacing: 0.2px;
	}

	.provider-badge {
		background: var(--surface-3);
		color: var(--text-primary);
		text-transform: capitalize;
	}

	.model-badge {
		background: rgba(99, 102, 241, 0.1);
		color: var(--accent-1);
	}

	.branch-badge {
		background: rgba(52, 199, 89, 0.1);
		color: var(--success);
	}

	.effort-badge {
		background: rgba(255, 149, 0, 0.1);
		color: var(--warning);
	}

	.hydra-badge {
		background: rgba(255, 149, 0, 0.1);
		color: #f59e0b;
	}

	.mode-badge {
		background: var(--surface-3);
		color: var(--text-tertiary);
		text-transform: capitalize;
		font-size: 9px;
	}

	.detail-separator {
		color: var(--text-tertiary);
		font-size: 10px;
		opacity: 0.5;
	}

	.detail-date {
		font-size: 10px;
		color: var(--text-tertiary);
		white-space: nowrap;
	}

	.detail-status {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		font-size: 10px;
		font-weight: 500;
		padding: 2px 8px;
		border-radius: var(--radius-full);
		font-family: var(--font-system);
		white-space: nowrap;
	}

	.status-idle {
		background: var(--surface-3);
		color: var(--text-tertiary);
	}

	.status-running {
		background: rgba(52, 199, 89, 0.1);
		color: var(--success);
	}

	.status-dot {
		width: 5px;
		height: 5px;
		border-radius: 50%;
		background: currentColor;
		animation: blink 1s ease-in-out infinite;
	}

	@keyframes blink {
		0%, 100% { opacity: 1; }
		50% { opacity: 0.3; }
	}
</style>
