<script lang="ts">
	// ---------------------------------------------------------------------------
	// RequestCards – shows different request types (text, image, file)
	// with context indicators and action buttons.
	// Matches RequestCards.swift
	// ---------------------------------------------------------------------------

	export interface RequestCard {
		id: string;
		kind: 'text' | 'image' | 'file' | 'command';
		headline: string;
		title: string;
		detail?: string;
		reason?: string;
		options: Array<{
			id: string;
			role: 'approve' | 'reject' | 'modify';
			title: string;
		}>;
		status: 'pending' | 'approved' | 'rejected' | 'running';
		created_at: string;
	}

	// ---------------------------------------------------------------------------
	// Props
	// ---------------------------------------------------------------------------

	interface Props {
		requests: RequestCard[];
		readonly?: boolean;
		onResolve: (request: RequestCard, optionId: string) => void;
		onReveal: (request: RequestCard) => void;
	}

	let { requests = [], readonly = false, onResolve, onReveal }: Props = $props();

	// ---------------------------------------------------------------------------
	// Derived
	// ---------------------------------------------------------------------------

	let pendingCount = $derived(requests.filter((r) => r.status === 'pending').length);

	// ---------------------------------------------------------------------------
	// Helpers
	// ---------------------------------------------------------------------------

	const kindIcon: Record<string, string> = {
		text: '✎',
		image: '🖼',
		file: '📎',
		command: '⌨',
	};

	const kindColor: Record<string, string> = {
		text: '#6366f1',
		image: '#ec4899',
		file: '#f59e0b',
		command: '#10b981',
	};

	const kindLabel: Record<string, string> = {
		text: 'Text',
		image: 'Image',
		file: 'File',
		command: 'Command',
	};

	const optionLabel: Record<string, string> = {
		approve: 'Approve',
		reject: 'Reject',
		modify: 'Modify',
	};

	const optionColor: Record<string, string> = {
		approve: '#10b981',
		reject: '#ef4444',
		modify: '#f59e0b',
	};

	function resolve(request: RequestCard, optionId: string) {
		if (readonly) return;
		onResolve(request, optionId);
	}

	function handleReveal(request: RequestCard) {
		onReveal(request);
	}

	function kindTint(kind: string): string {
		const hex = kindColor[kind] ?? '#6366f1';
		return `${hex}15`;
	}

	function kindBorder(kind: string): string {
		const hex = kindColor[kind] ?? '#6366f1';
		return `${hex}30`;
	}
</script>

<div class="request-cards-root">
	{#if requests.length === 0}
		<div class="empty">
			<span class="empty-icon">📭</span>
			<p class="empty-text">No pending requests.</p>
		</div>
	{:else}
		{#if pendingCount > 0}
			<div class="pending-indicator">
				<span class="pending-dot" aria-hidden="true"></span>
				<span class="pending-text">{pendingCount} pending approval{pendingCount === 1 ? '' : 's'}</span>
			</div>
		{/if}

		<div class="card-stack">
			{#each requests as request (request.id)}
				{@const tint = kindTint(request.kind)}
				{@const border = kindBorder(request.kind)}
				{@const accent = kindColor[request.kind] ?? '#6366f1'}

				<div
					class="request-card"
					style="background: {tint}; border-color: {border};"
					class:readonly-card={readonly}
					class:pending={request.status === 'pending'}
				>
					<!-- Header -->
					<header class="card-header">
						<div class="kind-badge" style="background: {accent}20; color: {accent}; border-color: {accent}40;">
							<span class="kind-icon">{kindIcon[request.kind] ?? '◈'}</span>
							<span class="kind-label">{kindLabel[request.kind] ?? request.kind}</span>
						</div>

						{#if !readonly}
							<button
								class="reveal-btn"
								onclick={() => handleReveal(request)}
								type="button"
								title="Show in thread"
							>↑</button>
						{/if}
					</header>

					<!-- Body -->
					<h3 class="headline">{request.headline}</h3>

					<!-- Content by kind -->
					<div class="card-body">
						{#if request.kind === 'command'}
							<pre class="command-pre">{request.title}</pre>
						{:else if request.kind === 'plan'}
							<p class="plan-text">{request.title}</p>
							<p class="plan-detail">
								Approve the plan above to let the agent start building.
							</p>
						{:else}
							<p class="plain-text" style="white-space: pre-wrap;">{request.title}</p>
						{/if}

						{#if request.detail}
							<p class="detail">{request.detail}</p>
						{/if}

						{#if request.reason}
							<p class="reason">{request.reason}</p>
						{/if}
					</div>

					<!-- Options -->
					{#if request.status === 'pending' && request.options.length > 0}
						<div class="options-row">
							{#each request.options as option (option.id)}
								<button
									class="option-btn"
									class:approve={option.role === 'approve'}
									class:reject={option.role === 'reject'}
									class:modify={option.role === 'modify'}
									onclick={() => resolve(request, option.id)}
									disabled={readonly}
									type="button"
								>
									{option.title}
								</button>
							{/each}
						</div>
					{:else if request.status === 'approved'}
						<div class="status-bar approved">
							<span class="status-dot"></span>
							Approved
						</div>
					{:else if request.status === 'rejected'}
						<div class="status-bar rejected">
							<span class="status-dot"></span>
							Rejected
						</div>
					{:else if request.status === 'running'}
						<div class="status-bar running">
							<span class="status-dot pulse"></span>
							Running…
						</div>
					{/if}
				</div>
			{/each}
		</div>
	{/if}
</div>

<style>
	.request-cards-root {
		display: flex;
		flex-direction: column;
		gap: 12px;
		padding: 12px;
		font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', sans-serif;
	}

	.pending-indicator {
		display: flex;
		align-items: center;
		gap: 6px;
		padding: 0 4px;
	}

	.pending-dot {
		width: 7px;
		height: 7px;
		border-radius: 50%;
		background: #f59e0b;
		animation: pulse 2s ease infinite;
	}

	.pending-text {
		font-size: 11px;
		color: #f59e0b;
		font-weight: 500;
	}

	@keyframes pulse {
		0%, 100% { opacity: 1; }
		50% { opacity: 0.35; }
	}

	.card-stack {
		display: flex;
		flex-direction: column;
		gap: 10px;
	}

	.request-card {
		border: 1px solid;
		border-radius: 14px;
		padding: 16px;
		transition: all 160ms ease;
	}

	.request-card.readonly-card {
		opacity: 0.85;
	}

	.request-card.pending {
		box-shadow: 0 2px 12px rgba(245, 158, 11, 0.08);
	}

	.card-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		margin-bottom: 10px;
	}

	.kind-badge {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		padding: 3px 8px;
		border-radius: 6px;
		border: 1px solid;
		font-size: 10px;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}

	.kind-icon {
		font-size: 11px;
	}

	.kind-label {
		font-size: 10px;
	}

	.reveal-btn {
		appearance: none;
		border: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.08));
		background: transparent;
		color: var(--chrome-secondary, #6b7280);
		width: 24px;
		height: 24px;
		border-radius: 6px;
		cursor: pointer;
		font-size: 14px;
		display: flex;
		align-items: center;
		justify-content: center;
		transition: all 120ms;
		font-family: inherit;
	}

	.reveal-btn:hover {
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.08));
	}

	.headline {
		font-size: 14px;
		font-weight: 600;
		color: var(--chrome-primary, #111827);
		margin: 0 0 8px;
		line-height: 1.4;
	}

	.card-body {
		margin-bottom: 12px;
	}

	.command-pre {
		font-family: 'SF Mono', 'Menlo', 'Consolas', monospace;
		font-size: 12px;
		line-height: 1.5;
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.05));
		padding: 10px 12px;
		border-radius: 8px;
		margin: 0;
		overflow-x: auto;
		white-space: pre-wrap;
		word-break: break-word;
		color: var(--chrome-primary, #111827);
	}

	.plan-text {
		font-size: 12px;
		line-height: 1.5;
		color: var(--chrome-primary, #111827);
		margin: 0 0 4px;
	}

	.plan-detail {
		font-size: 12px;
		line-height: 1.5;
		color: var(--chrome-secondary, #6b7280);
		margin: 0;
	}

	.plain-text {
		font-size: 12px;
		line-height: 1.5;
		color: var(--chrome-primary, #111827);
		margin: 0;
	}

	.detail {
		font-size: 11px;
		color: var(--chrome-secondary, #6b7280);
		margin: 6px 0 0;
		line-height: 1.4;
	}

	.reason {
		font-size: 12px;
		color: var(--chrome-secondary, #6b7280);
		margin: 6px 0 0;
		padding: 6px 10px;
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.03));
		border-radius: 6px;
		line-height: 1.4;
	}

	.options-row {
		display: flex;
		gap: 6px;
		justify-content: flex-end;
	}

	.option-btn {
		appearance: none;
		border: 1px solid;
		font-size: 11px;
		font-weight: 600;
		padding: 6px 14px;
		border-radius: 8px;
		cursor: pointer;
		transition: all 140ms ease;
		font-family: inherit;
		background: transparent;
	}

	.option-btn.approve {
		color: #10b981;
		border-color: #10b98140;
	}

	.option-btn.approve:hover:not(:disabled) {
		background: #10b98115;
		border-color: #10b98160;
	}

	.option-btn.reject {
		color: #ef4444;
		border-color: #ef444440;
	}

	.option-btn.reject:hover:not(:disabled) {
		background: #ef444415;
		border-color: #ef444460;
	}

	.option-btn.modify {
		color: #f59e0b;
		border-color: #f59e0b40;
	}

	.option-btn.modify:hover:not(:disabled) {
		background: #f59e0b15;
		border-color: #f59e0b60;
	}

	.option-btn:disabled {
		opacity: 0.35;
		cursor: not-allowed;
	}

	.status-bar {
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: 11px;
		font-weight: 600;
		padding: 4px 0;
	}

	.status-bar.approved {
		color: #10b981;
	}

	.status-bar.rejected {
		color: #ef4444;
	}

	.status-bar.running {
		color: #3b82f6;
	}

	.status-dot {
		width: 7px;
		height: 7px;
		border-radius: 50%;
		background: currentColor;
	}

	.status-dot.pulse {
		animation: pulse 1.5s ease infinite;
	}

	.empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 8px;
		padding: 40px 16px;
		color: var(--chrome-secondary, #6b7280);
	}

	.empty-icon {
		font-size: 32px;
		opacity: 0.5;
	}

	.empty-text {
		font-size: 12px;
		margin: 0;
	}
</style>
