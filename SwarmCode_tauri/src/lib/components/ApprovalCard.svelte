<script lang="ts">
	// ---------------------------------------------------------------------------
	// ApprovalCard – a permission/approval request shown above the composer.
	// Uses project types: ApprovalRequest, ApprovalOption, ApprovalRole.
	// ---------------------------------------------------------------------------

	import type { ApprovalRequest, ApprovalRole } from '$lib/types';

	interface Props {
		request: ApprovalRequest;
		onResolve: (requestId: string, role: ApprovalRole) => void;
	}

	let { request, onResolve }: Props = $props();

	const ICONS: Record<string, string> = {
		command: 'M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z',
		file_change: 'M13 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z',
		tool: 'M12 2l2 4 4 1-3 3 1 4-4-2-4 2 1-4-3-3 4-1z',
		plan: 'M12 2a2 2 0 0 1 2 2c0 .74-.4 1.39-1 1.73V7h1a7 7 0 0 1 7 7h1a1 1 0 0 1 1 1v3a1 1 0 0 1-1 1h-1v1a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-1H2a1 1 0 0 1-1-1v-3a1 1 0 0 1 1-1h1a7 7 0 0 1 7-7h1V5.73c-.6-.34-1-.99-1-1.73a2 2 0 0 1 2-2z',
		permissions: 'M12 2a2 2 0 0 1 2 2c0 .74-.4 1.39-1 1.73V7h1a7 7 0 0 1 7 7h1a1 1 0 0 1 1 1v3a1 1 0 0 1-1 1h-1v1a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-1H2a1 1 0 0 1-1-1v-3a1 1 0 0 1 1-1h1a7 7 0 0 1 7-7h1V5.73c-.6-.34-1-.99-1-1.73a2 2 0 0 1 2-2zM8 13a2 2 0 1 0 0 4 2 2 0 0 0 0-4zm8 0a2 2 0 1 0 0 4 2 2 0 0 0 0-4z',
	};

	const iconPath = $derived(ICONS[request.kind] ?? ICONS.tool);
</script>

<div class="approval-card" role="region" aria-label="Approval request">
	<header class="ac-header">
		<span class="ac-icon" aria-hidden="true">
			<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
				<path d={iconPath}/>
			</svg>
		</span>
		<span class="ac-headline">{request.title}</span>
	</header>

	{#if request.detail}
		<div class="ac-detail-text">{request.detail}</div>
	{/if}

	{#if request.reason}
		<div class="ac-reason">{request.reason}</div>
	{/if}

	<div class="ac-actions">
		{#each request.options as option}
			<button
				type="button"
				class="ac-btn"
				class:primary={option.role === 'Approve' || option.role === 'ApproveAlways'}
				onclick={() => onResolve(request.id, option.role)}
			>
				{option.title}
			</button>
		{/each}
	</div>
</div>

<style>
	.approval-card {
		display: flex;
		flex-direction: column;
		gap: 10px;
		padding: 14px 16px;
		max-width: 640px;
		margin: 0 auto 4px;
		background: var(--surface-2, #1f1f24);
		border: 1px solid var(--border-color-1, #2a2a30);
		border-radius: 20px;
		animation: ac-pop 0.2s ease;
	}

	@keyframes ac-pop {
		from { opacity: 0; transform: translateY(-4px); }
		to   { opacity: 1; transform: translateY(0); }
	}

	.ac-header {
		display: flex;
		align-items: center;
		gap: 8px;
	}

	.ac-icon {
		display: inline-flex;
		color: var(--warning, #f5a623);
	}

	.ac-headline {
		font-size: 15px;
		font-weight: 600;
		color: var(--text-primary, #eee);
	}

	.ac-command-block {
		padding: 10px 12px;
		background: var(--surface-3, #25252b);
		border-radius: 10px;
		width: 100%;
		max-height: 8em;
		overflow: hidden;
	}

	.ac-command-text {
		font-family: var(--font-mono, 'SF Mono', Menlo, monospace);
		font-size: 13px;
		color: var(--text-secondary, #bbb);
		white-space: pre-wrap;
		word-break: break-all;
	}

	.ac-detail-body {
		font-size: 13px;
		color: var(--text-secondary, #bbb);
		line-height: 1.5;
	}

	.ac-detail-text {
		font-size: 12px;
		color: var(--text-tertiary, #999);
		line-height: 1.4;
	}

	.ac-reason {
		font-size: 13px;
		color: var(--text-tertiary, #999);
		font-style: italic;
	}

	.ac-actions {
		display: flex;
		justify-content: flex-end;
		gap: 8px;
	}

	.ac-btn {
		appearance: none;
		border: none;
		padding: 5px 14px;
		border-radius: 8px;
		font: inherit;
		font-size: 12px;
		font-weight: 500;
		cursor: pointer;
		transition: all 120ms ease;
	}

	.ac-btn {
		background: var(--surface-3, #25252b);
		border: 1px solid var(--border-color-1, #2a2a30);
		color: var(--text-primary, #eee);
	}

	.ac-btn:hover:not(:disabled) {
		background: var(--surface-4, #2c2c34);
	}

	.ac-btn.primary {
		background: var(--accent-1, #6366f1);
		border-color: var(--accent-1, #6366f1);
		color: #fff;
	}

	.ac-btn.primary:hover:not(:disabled) {
		background: var(--accent-2, #5158d8);
		border-color: var(--accent-2, #5158d8);
	}

	@media (prefers-reduced-motion: reduce) {
		.approval-card { animation: none; }
	}
</style>
