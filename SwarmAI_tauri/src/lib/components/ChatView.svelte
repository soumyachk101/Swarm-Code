<script lang="ts">
	import { onMount } from 'svelte';
	import type { ChatThread, ThreadDocument, TimelineItem, TimelineContent } from '$lib/types';

	interface Props {
		thread: ChatThread;
	}

	let { thread }: Props = $props();

	let doc = $state<ThreadDocument | null>(null);
	let scrollContainer = $state<HTMLDivElement | null>(null);
	let autoScroll = $state(true);
	let isGenerating = $state(false);
	let reasoningVisible = $state(false);

	$effect(() => {
		if (thread?.id) loadDocument();
	});

	async function loadDocument() {
		try {
			doc = null;
			const { getThreadDocument } = await import('$lib/api/commands');
			doc = await getThreadDocument(thread.id);
		} catch (e) {
			console.error('Failed to load thread document:', e);
		}
	}

	$effect(() => {
		if (doc?.items && scrollContainer) {
			if (autoScroll) {
				scrollContainer.scrollTop = scrollContainer.scrollHeight;
			}
		}
	});

	function isUserMessage(item: TimelineItem): boolean {
		return item.content.type === 'user';
	}
	function isAssistantMessage(item: TimelineItem): boolean {
		return item.content.type === 'assistant';
	}
	function isToolCall(item: TimelineItem): boolean {
		return item.content.type === 'tool';
	}
	function isNotice(item: TimelineItem): boolean {
		return item.content.type === 'notice';
	}
	function isReasoning(item: TimelineItem): boolean {
		return item.content.type === 'reasoning';
	}
	function isSystem(item: TimelineItem): boolean {
		return item.content.type === 'system';
	}
	function getMessageText(item: TimelineItem): string {
		const content = item.content as any;
		return content.data?.text ?? content.text ?? '';
	}
	function handleScroll() {
		if (!scrollContainer) return;
		const { scrollTop, scrollHeight, clientHeight } = scrollContainer;
		autoScroll = scrollHeight - scrollTop - clientHeight < 80;
	}
	function toggleReasoning() {
		reasoningVisible = !reasoningVisible;
	}

	let timeFormatter = new Intl.DateTimeFormat('en-US', {
		hour: 'numeric',
		minute: '2-digit',
		hour12: true
	});
</script>

<div class="chat-view">
	<div class="chat-header">
		<div class="chat-title-section">
			<h2 class="chat-title">{thread.title || 'New Conversation'}</h2>
			<div class="chat-meta">
				{#if thread.provider}
					<span class="meta-item provider-badge">
						{thread.provider}
					</span>
				{/if}
				{#if thread.model}
					<span class="meta-item">{thread.model}</span>
				{/if}
				{#if thread.effort}
					<span class="meta-item">effort: {thread.effort}</span>
				{/if}
				{#if thread.hydra}
					<span class="meta-item hydra-badge">
						<span class="hydra-dot"></span>
						hydra
					</span>
				{/if}
				{#if thread.fastMode}
					<span class="meta-item fast">⚡ fast</span>
				{/if}
				<span class="meta-item status-indicator" class:running={isGenerating}>
					{#if isGenerating}
						<span class="spinner"></span>
						Generating…
					{/if}
				</span>
			</div>
		</div>
		<div class="chat-header-actions">
			{#if doc?.items?.some(i => i.content.type === 'reasoning')}
				<button
					class="header-btn"
					class:active={reasoningVisible}
					onclick={toggleReasoning}
					title="Toggle reasoning"
				>
					<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
						<path d="M12 2a7 7 0 0 1 7 7c0 2.38-1.19 4.47-3 5.74V17a1 1 0 0 1-1 1H9a1 1 0 0 1-1-1v-2.26C6.19 13.47 5 11.38 5 9a7 7 0 0 1 7-7z"/>
						<path d="M9 21h6"/>
					</svg>
				</button>
			{/if}
		</div>
	</div>

	<div class="chat-timeline" bind:this={scrollContainer} onscroll={handleScroll}>
		{#if doc && doc.items.length > 0}
			{#each doc.items as item (item.id)}
				{#if isReasoning(item)}
					{#if reasoningVisible}
						<div class="timeline-item reasoning-block">
							<details open>
								<summary class="reasoning-summary">Reasoning</summary>
								<div class="reasoning-content">{getMessageText(item)}</div>
							</details>
						</div>
					{/if}
				{:else if isUserMessage(item)}
					<div class="timeline-item user">
						<div class="message-user">
							<div class="message-avatar user-avatar">U</div>
							<div class="message-body user-body">
								<div class="message-text">{getMessageText(item)}</div>
								<span class="message-time">{timeFormatter.format(new Date(item.date))}</span>
							</div>
						</div>
					</div>
				{:else if isAssistantMessage(item)}
					<div class="timeline-item assistant">
						<div class="message-assistant">
							<div class="message-avatar assistant-avatar">
								<img src="/icons/swarmai-logo.svg" alt="SwarmAI" width="14" height="14" />
							</div>
							<div class="message-body assistant-body">
								<div class="message-text">{getMessageText(item)}</div>
								<span class="message-time">{timeFormatter.format(new Date(item.date))}</span>
							</div>
						</div>
					</div>
				{:else if isToolCall(item)}
					<div class="timeline-item tool">
						<div class="tool-header">
							<span class="tool-icon">
								<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
									<path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/>
								</svg>
							</span>
							<span class="tool-title">
								{(item.content as any).data?.title || 'Tool Call'}
							</span>
							<span class="tool-status">
								{(item.content as any).data?.status === 'running' ? 'Running' : 'Done'}
							</span>
						</div>
						{#if (item.content as any).data?.detail}
							<pre class="tool-detail">{(item.content as any).data.detail}</pre>
						{/if}
					</div>
				{:else if isNotice(item)}
					{@const level = (item.content as any).data?.level || 'info'}
					<div class="timeline-item notice" class:warning={level === 'warning'} class:error={level === 'error'}>
						<div class="notice-content">
							<span class="notice-icon">
								{#if level === 'error'}⚠️{:else if level === 'warning'}⚡{:else}ℹ️{/if}
							</span>
							{(item.content as any).data?.message || ''}
						</div>
					</div>
				{:else if isSystem(item)}
					<div class="timeline-item system">
						<span class="system-text">{getMessageText(item)}</span>
					</div>
				{/if}
			{/each}
		{:else}
			<div class="empty-timeline">
				<div class="empty-glyph">
					<img src="/icons/swarmai-logo.svg" alt="SwarmAI" width="48" height="48" class="empty-glyph-img" />
				</div>
				<h3>No messages yet</h3>
				<p>Type a message below to start the conversation.</p>
			</div>
		{/if}
		{#if isGenerating}
			<div class="generating-indicator">
				<div class="thinking-dots">
					<span class="dot"></span>
					<span class="dot"></span>
					<span class="dot"></span>
				</div>
			</div>
		{/if}
	</div>
</div>

<style>
	.chat-view {
		flex: 1;
		display: flex;
		flex-direction: column;
		overflow: hidden;
		background: var(--surface-1);
	}

	.chat-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 10px 20px;
		border-bottom: var(--border-1) var(--border-color-1);
		background: var(--surface-2);
		flex-shrink: 0;
		min-height: 56px;
		gap: var(--space-4);
	}

	.chat-title-section {
		flex: 1;
		min-width: 0;
	}

	.chat-title {
		font-size: var(--font-size-md);
		font-weight: 600;
		color: var(--text-primary);
		margin: 0;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.chat-meta {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		margin-top: 3px;
		flex-wrap: wrap;
	}

	.meta-item {
		font-size: var(--font-size-xs);
		color: var(--text-tertiary);
	}

	.provider-badge {
		background: var(--surface-3);
		padding: 1px 8px;
		border-radius: var(--radius-full);
		font-family: var(--font-mono);
		text-transform: uppercase;
		font-size: 10px;
		font-weight: 500;
		letter-spacing: 0.3px;
		color: var(--text-secondary);
	}

	.hydra-badge {
		display: inline-flex;
		align-items: center;
		gap: 4px;
	}

	.hydra-dot {
		width: 6px;
		height: 6px;
		border-radius: 50%;
		background: var(--accent-1);
		display: inline-block;
	}

	.meta-item.fast {
		color: var(--warning);
		font-weight: 500;
	}

	.status-indicator {
		display: inline-flex;
		align-items: center;
		gap: 4px;
	}

	.status-indicator.running {
		color: var(--accent-1);
	}

	.spinner {
		width: 10px;
		height: 10px;
		border: 1.5px solid var(--accent-3);
		border-top-color: var(--accent-1);
		border-radius: 50%;
		animation: spin 0.6s linear infinite;
		display: inline-block;
	}

	@keyframes spin {
		to { transform: rotate(360deg); }
	}

	.chat-header-actions {
		display: flex;
		align-items: center;
		gap: var(--space-2);
	}

	.header-btn {
		width: 28px;
		height: 28px;
		border: none;
		background: transparent;
		border-radius: var(--radius-md);
		color: var(--text-secondary);
		cursor: pointer;
		display: flex;
		align-items: center;
		justify-content: center;
		transition: all var(--transition-fast);
	}

	.header-btn:hover {
		background: var(--surface-3);
		color: var(--text-primary);
	}

	.header-btn.active {
		background: var(--accent-3);
		color: var(--accent-1);
	}

	.chat-timeline {
		flex: 1;
		overflow-y: auto;
		overflow-x: hidden;
		padding: 16px 0;
		scroll-behavior: smooth;
	}

	.timeline-item {
		padding: 8px 20px;
		margin-bottom: 4px;
	}

	/* ---- User Messages ---- */
	.message-user {
		display: flex;
		flex-direction: row-reverse;
		align-items: flex-start;
		gap: var(--space-3);
		max-width: 75%;
		margin-left: auto;
	}

	.user-body {
		background: var(--accent-1);
		color: var(--text-inverse);
		border-radius: var(--radius-lg);
		padding: 8px 14px;
		border-bottom-right-radius: var(--space-1);
	}

	.user-body .message-text {
		white-space: pre-wrap;
		word-wrap: break-word;
		line-height: var(--line-height-normal);
		font-size: var(--font-size-md);
	}

	.user-body .message-time {
		display: block;
		font-size: 10px;
		opacity: 0.7;
		margin-top: 4px;
		text-align: right;
	}

	/* ---- Assistant Messages ---- */
	.message-assistant {
		display: flex;
		align-items: flex-start;
		gap: var(--space-3);
		max-width: 85%;
	}

	.assistant-body {
		background: var(--surface-2);
		border-radius: var(--radius-lg);
		padding: 8px 14px;
		border-bottom-left-radius: var(--space-1);
		border: var(--border-1) var(--border-subtle);
	}

	.assistant-body .message-text {
		white-space: pre-wrap;
		word-wrap: break-word;
		line-height: var(--line-height-normal);
		font-size: var(--font-size-md);
		color: var(--text-primary);
	}

	.assistant-body .message-time {
		display: block;
		font-size: 10px;
		color: var(--text-tertiary);
		margin-top: 4px;
	}

	/* ---- Avatars ---- */
	.message-avatar {
		width: 28px;
		height: 28px;
		border-radius: 50%;
		display: flex;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
		font-size: 12px;
		font-weight: 600;
	}

	.user-avatar {
		background: var(--surface-3);
		color: var(--text-secondary);
	}

	.assistant-avatar {
		background: var(--accent-1);
		color: var(--text-inverse);
	}

	/* ---- Tool Calls ---- */
	.tool-block {
		max-width: 80%;
		background: var(--surface-2);
		border: var(--border-1) var(--border-color-1);
		border-left: 3px solid var(--warning);
		border-radius: var(--radius-md);
		padding: 10px 14px;
		font-family: var(--font-mono);
		font-size: var(--font-size-sm);
	}

	.tool-header {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		margin-bottom: 6px;
		color: var(--text-secondary);
		font-size: var(--font-size-sm);
		font-weight: 600;
	}

	.tool-icon {
		color: var(--warning);
	}

	.tool-title {
		flex: 1;
		font-family: var(--font-mono);
		font-size: var(--font-size-sm);
	}

	.tool-status {
		font-size: 10px;
		padding: 1px 8px;
		border-radius: var(--radius-full);
		background: var(--surface-3);
		color: var(--text-secondary);
	}

	.tool-status.running {
		background: var(--accent-3);
		color: var(--accent-1);
	}

	.tool-detail {
		font-size: var(--font-size-xs);
		color: var(--text-tertiary);
		white-space: pre-wrap;
		overflow-x: auto;
		margin-top: 4px;
	}

	/* ---- Notices ---- */
	.notice-block {
		max-width: 80%;
	}

	.notice-content {
		display: flex;
		align-items: flex-start;
		gap: var(--space-2);
		font-size: var(--font-size-sm);
		padding: 8px 14px;
		border-radius: var(--radius-md);
	}

	.notice-block:not(.warning):not(.error) .notice-content {
		background: var(--surface-2);
		color: var(--text-secondary);
	}

	.notice-block.warning .notice-content {
		background: rgba(255, 149, 0, 0.1);
		color: var(--warning);
	}

	.notice-block.error .notice-content {
		background: rgba(255, 59, 48, 0.1);
		color: var(--danger);
	}

	.notice-icon {
		flex-shrink: 0;
	}

	/* ---- Reasoning ---- */
	.reasoning-block {
		background: transparent;
	}

	.reasoning-summary {
		cursor: pointer;
		font-size: var(--font-size-xs);
		color: var(--text-tertiary);
		user-select: none;
		list-style: none;
		padding: 2px 0;
	}

	.reasoning-summary::-webkit-details-marker {
		display: none;
	}

	.reasoning-summary::before {
		content: '▸ ';
	}

	.reasoning-content {
		font-size: var(--font-size-xs);
		color: var(--text-tertiary);
		font-style: italic;
		white-space: pre-wrap;
		padding: 4px 0 4px 12px;
		border-left: 2px solid var(--surface-4);
		margin-top: 4px;
	}

	/* ---- System ---- */
	.system-block {
		text-align: center;
	}

	.system-text {
		font-size: var(--font-size-xs);
		color: var(--text-tertiary);
		font-style: italic;
	}

	/* ---- Empty State ---- */
	.empty-timeline {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		height: 100%;
		color: var(--text-tertiary);
		padding: 40px 20px;
		text-align: center;
	}

	.empty-glyph {
		margin-bottom: var(--space-6);
		opacity: 0.4;
	}

	.empty-timeline h3 {
		color: var(--text-secondary);
		margin-bottom: var(--space-2);
		font-size: var(--font-size-md);
		font-weight: 500;
	}

	.empty-timeline p {
		font-size: var(--font-size-sm);
	}

	/* ---- Generating Indicator ---- */
	.generating-indicator {
		padding: 8px 20px;
		display: flex;
		align-items: center;
	}

	.thinking-dots {
		display: flex;
		gap: 4px;
	}

	.dot {
		width: 6px;
		height: 6px;
		border-radius: 50%;
		background: var(--accent-1);
		animation: dot-bounce 1.4s ease-in-out infinite;
	}

	.dot:nth-child(2) {
		animation-delay: 0.16s;
	}

	.dot:nth-child(3) {
		animation-delay: 0.32s;
	}

	@keyframes dot-bounce {
		0%, 80%, 100% { transform: scale(0.6); opacity: 0.4; }
		40% { transform: scale(1); opacity: 1; }
	}

	/* ---- Scrollbar ---- */
	.chat-timeline::-webkit-scrollbar {
		width: 6px;
	}

	.chat-timeline::-webkit-scrollbar-track {
		background: transparent;
	}

	.chat-timeline::-webkit-scrollbar-thumb {
		background: var(--surface-4);
		border-radius: var(--radius-full);
	}

	.chat-timeline::-webkit-scrollbar-thumb:hover {
		background: var(--surface-5);
	}
</style>
