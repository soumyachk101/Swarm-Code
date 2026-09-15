<script lang="ts">
	import type { TimelineItem } from '$lib/types';
	import HydraGlyph from './HydraGlyph.svelte';

	interface Props {
		item: TimelineItem;
		isStreaming?: boolean;
		showTimestamp?: boolean;
	}

	let { item, isStreaming = false, showTimestamp = true }: Props = $props();

	let roleClass = $derived(item.content.type);
	let content = $derived(item.content as any);
	let timeFormatter = new Intl.DateTimeFormat('en-US', {
		hour: 'numeric',
		minute: '2-digit',
		hour12: true
	});

	function getRoleLabel(type: string): string {
		switch (type) {
			case 'user': return 'You';
			case 'assistant': return 'Assistant';
			case 'tool': return 'Tool';
			case 'reasoning': return 'Reasoning';
			case 'notice': return 'Notice';
			case 'system': return 'System';
			default: return type;
		}
	}

	function formatTime(dateStr: string): string {
		return timeFormatter.format(new Date(dateStr));
	}
</script>

<div class="message-bubble {roleClass}" class:streaming={isStreaming}>
	<div class="bubble-header">
		<div class="role-info">
			{#if roleClass === 'assistant'}
				<div class="role-avatar assistant-avatar">
					<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
						<path d="M12 2l2 4 4 1-3 3 1 4-4-2-4 2 1-4-3-3 4-1z"/>
					</svg>
				</div>
			{:else if roleClass === 'user'}
				<div class="role-avatar user-avatar">U</div>
			{:else if roleClass === 'tool'}
				<div class="role-avatar tool-avatar">
					<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
						<path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/>
					</svg>
				</div>
			{:else if roleClass === 'error'}
				<div class="role-avatar error-avatar">
					<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
						<path d="M12 2v10m0 0v6m0-6h.01M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20z"/>
					</svg>
				</div>
			{:else if roleClass === 'notice'}
				<div class="role-avatar notice-avatar">
					<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
						<circle cx="12" cy="12" r="10"/>
						<path d="M12 16v-4M12 8h.01"/>
					</svg>
				</div>
			{/if}
			<span class="role-label">{getRoleLabel(roleClass)}</span>
			{#if roleClass === 'assistant' && item.headId}
				<HydraGlyph size={12} color="var(--accent-1)" />
			{/if}
		</div>
		{#if showTimestamp}
			<span class="timestamp">{formatTime(item.date)}</span>
		{/if}
	</div>

	<div class="bubble-content">
		{#if roleClass === 'assistant'}
			<div class="message-text assistant-content">{content.data?.text ?? ''}</div>
		{:else if roleClass === 'user'}
			<div class="message-text user-content">{content.data?.text ?? ''}</div>
		{:else if roleClass === 'tool'}
			<div class="tool-content">
				<div class="tool-label">{content.data?.title ?? 'Tool'}</div>
				{#if content.data?.detail}
					<pre class="tool-detail">{content.data.detail}</pre>
				{:else if content.data?.text}
					<div class="message-text">{content.data.text}</div>
				{/if}
			</div>
		{:else if roleClass === 'reasoning'}
			<div class="message-text reasoning-content">{content.data?.text ?? ''}</div>
		{:else if roleClass === 'notice'}
			<div class="notice-content" class:warning={content.data?.level === 'warning'} class:error={content.data?.level === 'error'}>
				<span class="notice-emoji">
					{#if content.data?.level === 'error'}⚠️{:else if content.data?.level === 'warning'}⚡{:else}ℹ️{/if}
				</span>
				<span>{content.data?.message ?? ''}</span>
			</div>
		{:else if roleClass === 'system'}
			<div class="message-text system-content">{content.data?.text ?? ''}</div>
		{/if}
	</div>

	{#if isStreaming}
		<div class="streaming-indicator">
			<span class="stream-cursor">▌</span>
		</div>
	{/if}
</div>

<style>
	.message-bubble {
		display: flex;
		flex-direction: column;
		gap: 4px;
		padding: 4px 0;
	}

	.bubble-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-3);
	}

	.role-info {
		display: flex;
		align-items: center;
		gap: var(--space-2);
	}

	.role-avatar {
		width: 22px;
		height: 22px;
		border-radius: 50%;
		display: flex;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
	}

	.user-avatar {
		background: var(--surface-3);
		color: var(--text-secondary);
		font-size: 10px;
		font-weight: 600;
	}

	.assistant-avatar {
		background: var(--accent-1);
		color: var(--text-inverse);
	}

	.tool-avatar {
		background: rgba(255, 149, 0, 0.15);
		color: var(--warning);
	}

	.error-avatar {
		background: rgba(255, 59, 48, 0.15);
		color: var(--danger);
	}

	.notice-avatar {
		background: var(--surface-3);
		color: var(--text-secondary);
	}

	.role-label {
		font-size: var(--font-size-xs);
		font-weight: 600;
		color: var(--text-secondary);
	}

	.timestamp {
		font-size: 10px;
		color: var(--text-tertiary);
		flex-shrink: 0;
	}

	.bubble-content {
		padding-left: 30px;
	}

	.message-text {
		font-size: var(--font-size-md);
		line-height: var(--line-height-relaxed);
		color: var(--text-primary);
		white-space: pre-wrap;
		word-wrap: break-word;
	}

	.assistant-content {
		max-width: 720px;
	}

	.user-content {
		color: var(--text-inverse);
	}

	.reasoning-content {
		color: var(--text-tertiary);
		font-style: italic;
		font-size: var(--font-size-sm);
	}

	.system-content {
		color: var(--text-tertiary);
		font-size: var(--font-size-sm);
	}

	.tool-content {
		max-width: 600px;
	}

	.tool-label {
		font-size: var(--font-size-xs);
		font-weight: 600;
		color: var(--warning);
		margin-bottom: 4px;
	}

	.tool-detail {
		font-size: var(--font-size-xs);
		color: var(--text-tertiary);
		white-space: pre-wrap;
		overflow-x: auto;
		margin-top: 4px;
	}

	.notice-content {
		display: inline-flex;
		align-items: flex-start;
		gap: var(--space-2);
		padding: 6px 12px;
		border-radius: var(--radius-md);
		font-size: var(--font-size-sm);
	}

	.notice-content:not(.warning):not(.error) {
		background: var(--surface-2);
		color: var(--text-secondary);
	}

	.notice-content.warning {
		background: rgba(255, 149, 0, 0.1);
		color: var(--warning);
	}

	.notice-content.error {
		background: rgba(255, 59, 48, 0.1);
		color: var(--danger);
	}

	.notice-emoji {
		flex-shrink: 0;
	}

	.streaming-indicator {
		padding-left: 30px;
		margin-top: var(--space-1);
	}

	.stream-cursor {
		color: var(--accent-1);
		font-weight: 700;
		animation: cursor-blink 0.8s step-end infinite;
	}

	@keyframes cursor-blink {
		0%, 100% { opacity: 1; }
		50% { opacity: 0; }
	}
</style>
