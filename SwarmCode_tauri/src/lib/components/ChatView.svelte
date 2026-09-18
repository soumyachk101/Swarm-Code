<script lang="ts">
	import { onMount } from 'svelte';
	import type { ChatThread, ThreadDocument, TimelineItem } from '$lib/types';

	interface Props {
		thread: ChatThread;
		terminalVisible?: boolean;
		onToggleTerminal?: () => void;
	}

	let {
		thread,
		terminalVisible = $bindable(false),
		onToggleTerminal
	}: Props = $props();

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
		const val = content.value ?? content;
		return val.text ?? '';
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
	<!-- Slim chrome header -->
	<div class="chat-chrome">
		<div class="chrome-left">
			<span class="chrome-title">{thread.title || 'Conversation'}</span>
			<div class="chrome-meta">
				{#if thread.provider}
					<span class="chrome-badge">{thread.provider}</span>
				{/if}
				{#if thread.model}
					<span class="chrome-sep">·</span>
					<span class="chrome-model">{thread.model}</span>
				{/if}
				{#if thread.effort}
					<span class="chrome-sep">·</span>
					<span class="chrome-effort">effort: {thread.effort}</span>
				{/if}
				{#if thread.branch}
					<span class="chrome-sep">·</span>
					<span class="chrome-git">&#x2387; {thread.branch}</span>
				{/if}
				{#if thread.hydra}
					<span class="chrome-sep">·</span>
					<span class="chrome-hydra"><span class="hydra-dot"></span>hydra</span>
				{/if}
				{#if thread.fast_mode}
					<span class="chrome-sep">·</span>
					<span class="chrome-fast">fast</span>
				{/if}
			</div>
		</div>
		<div class="chrome-right">
			{#if isGenerating}
				<span class="chrome-generating">
					<span class="gen-dot"></span>
					<span class="gen-dot"></span>
					<span class="gen-dot"></span>
				</span>
			{/if}
			{#if doc?.items?.some(i => i.content.type === 'reasoning')}
				<button
					class="chrome-btn"
					class:active={reasoningVisible}
					onclick={toggleReasoning}
					title="Toggle reasoning"
				>
					<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
						<path d="M12 2a7 7 0 0 1 7 7c0 2.38-1.19 4.47-3 5.74V17a1 1 0 0 1-1 1H9a1 1 0 0 1-1-1v-2.26C6.19 13.47 5 11.38 5 9a7 7 0 0 1 7-7z"/>
						<path d="M9 21h6"/>
					</svg>
				</button>
			{/if}
			{#if onToggleTerminal}
				<button
					class="chrome-btn"
					class:active={terminalVisible}
					onclick={onToggleTerminal}
					title="Toggle terminal"
				>
					<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
						<rect x="2" y="3" width="20" height="14" rx="2" ry="2"/>
						<line x1="8" y1="21" x2="16" y2="21"/>
						<line x1="12" y1="17" x2="12" y2="21"/>
					</svg>
				</button>
			{/if}
		</div>
	</div>

	<div class="chat-timeline" bind:this={scrollContainer} onscroll={handleScroll}>
		{#if doc && doc.items.length > 0}
			<div class="timeline">
				{#each doc.items as item (item.id)}
					{#if isReasoning(item)}
						{#if reasoningVisible}
							<div class="timeline-item reasoning">
								<details open>
									<summary class="reasoning-toggle">Reasoning</summary>
									<div class="reasoning-body">{getMessageText(item)}</div>
								</details>
							</div>
						{/if}
					{:else if isUserMessage(item)}
						<div class="timeline-item user-row">
							<div class="bubble user-bubble">
								<div class="bubble-text">{getMessageText(item)}</div>
								<span class="bubble-time">{timeFormatter.format(new Date(item.date))}</span>
							</div>
						</div>
					{:else if isAssistantMessage(item)}
						<div class="timeline-item assistant-row">
							<div class="avatar assistant-avatar">
								<img src="/icons/swarmai-logo.svg" alt="Swarm Code" width="14" height="14" />
							</div>
							<div class="bubble assistant-bubble">
								<div class="bubble-text">{getMessageText(item)}</div>
								<span class="bubble-time">{timeFormatter.format(new Date(item.date))}</span>
							</div>
						</div>
					{:else if isToolCall(item)}
						<div class="timeline-item tool-row">
							<div class="tool-call">
								<div class="tool-header">
									<span class="tool-icon">
										<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
											<path d="M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z"/>
										</svg>
									</span>
									<span class="tool-name">{(item.content as any).value?.title || 'Tool Call'}</span>
									<span class="tool-status">{(item.content as any).value?.status === 'running' ? 'Running' : 'Done'}</span>
								</div>
								{#if (item.content as any).value?.detail}
									<details class="tool-details">
										<summary class="tool-summary">details</summary>
										<pre class="tool-body">{(item.content as any).value.detail}</pre>
									</details>
								{/if}
							</div>
						</div>
					{:else if isNotice(item)}
						{@const level = (item.content as any).value?.level || 'info'}
						<div class="timeline-item notice-row">
							<div class="notice-pill {level}">
								<span class="notice-dot"></span>
								<span class="notice-text">{(item.content as any).value?.message || ''}</span>
							</div>
						</div>
					{:else if isSystem(item)}
						<div class="timeline-item system-row">
							<span class="system-label">{getMessageText(item)}</span>
						</div>
					{/if}
				{/each}
			</div>
		{:else}
			<div class="empty-state">
				<div class="empty-logo">
					<img src="/icons/swarmai-logo.svg" alt="Swarm Code" width="48" height="48" />
				</div>
				<h3>No messages yet</h3>
				<p>Type a message below to start the conversation.</p>
			</div>
		{/if}
	</div>
</div>

<style>
	/* ===== Layout ===== */
	.chat-view {
		flex: 1;
		display: flex;
		flex-direction: column;
		overflow: hidden;
		background: var(--surface-1);
	}

	/* ===== Slim Chrome Header (subtle, 40px) ===== */
	.chat-chrome {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 6px 16px;
		border-bottom: 1px solid var(--border-color-2, rgba(255, 255, 255, 0.06));
		background: var(--surface-2);
		flex-shrink: 0;
		min-height: 40px;
		gap: var(--space-3, 12px);
	}

	.chrome-left {
		display: flex;
		align-items: center;
		gap: 8px;
		min-width: 0;
		flex: 1;
	}

	.chrome-title {
		font-size: var(--font-size-sm, 12px);
		font-weight: 600;
		color: var(--text-primary);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
		flex-shrink: 1;
		min-width: 0;
	}

	.chrome-meta {
		display: flex;
		align-items: center;
		gap: 6px;
		flex-shrink: 0;
		flex-wrap: nowrap;
		overflow: hidden;
	}

	.chrome-badge {
		font-size: 10px;
		font-family: var(--font-mono, monospace);
		text-transform: uppercase;
		font-weight: 500;
		letter-spacing: 0.3px;
		color: var(--text-tertiary);
		background: var(--surface-3);
		padding: 1px 6px;
		border-radius: 4px;
	}

	.chrome-sep {
		color: var(--text-tertiary);
		font-size: 11px;
	}

	.chrome-model {
		font-size: 11px;
		color: var(--text-tertiary);
		white-space: nowrap;
	}

	.chrome-effort {
		font-size: 11px;
		color: var(--text-tertiary);
		white-space: nowrap;
	}

	.chrome-git {
		font-size: 11px;
		color: var(--text-tertiary);
		white-space: nowrap;
		font-family: var(--font-mono, monospace);
	}

	.chrome-hydra {
		font-size: 11px;
		color: var(--text-tertiary);
		display: inline-flex;
		align-items: center;
		gap: 4px;
		white-space: nowrap;
	}

	.hydra-dot {
		width: 6px;
		height: 6px;
		border-radius: 50%;
		background: var(--accent-1);
		display: inline-block;
	}

	.chrome-fast {
		font-size: 11px;
		color: var(--warning);
		font-weight: 500;
		white-space: nowrap;
	}

	.chrome-right {
		display: flex;
		align-items: center;
		gap: 4px;
		flex-shrink: 0;
	}

	.chrome-btn {
		width: 26px;
		height: 26px;
		border: none;
		background: transparent;
		border-radius: 6px;
		color: var(--text-secondary);
		cursor: pointer;
		display: flex;
		align-items: center;
		justify-content: center;
		transition: all 0.15s ease;
	}

	.chrome-btn:hover {
		background: var(--surface-3);
		color: var(--text-primary);
	}

	.chrome-btn.active {
		background: var(--accent-3);
		color: var(--accent-1);
	}

	/* ===== Generating indicator (inline dots) ===== */
	.chrome-generating {
		display: inline-flex;
		align-items: center;
		gap: 3px;
		padding: 2px 8px;
	}

	.gen-dot {
		width: 5px;
		height: 5px;
		border-radius: 50%;
		background: var(--accent-1);
		animation: gen-pulse 1.2s ease-in-out infinite;
	}

	.gen-dot:nth-child(2) {
		animation-delay: 0.2s;
	}

	.gen-dot:nth-child(3) {
		animation-delay: 0.4s;
	}

	@keyframes gen-pulse {
		0%, 80%, 100% { opacity: 0.3; transform: scale(0.8); }
		40% { opacity: 1; transform: scale(1); }
	}

	/* ===== Timeline ===== */
	.chat-timeline {
		flex: 1;
		overflow-y: auto;
		overflow-x: hidden;
		padding: 0;
		scroll-behavior: smooth;
	}

	.timeline {
		padding: 16px 0;
	}

	.timeline-item {
		margin-bottom: 20px;
		padding: 0 20px;
	}

	/* ===== Message Bubbles ===== */
	.bubble {
		position: relative;
		padding: 10px 14px;
		font-size: var(--font-size-md, 14px);
		line-height: var(--line-height-normal);
	}

	.bubble-text {
		white-space: pre-wrap;
		word-wrap: break-word;
	}

	.bubble-time {
		display: block;
		font-size: 10px;
		margin-top: 4px;
		user-select: none;
	}

	/* ---- User: right-aligned, accent bubble, tail on bottom-right ---- */
	.user-row {
		display: flex;
		justify-content: flex-end;
	}

	.user-bubble {
		background: var(--accent-1);
		color: var(--text-inverse);
		border-radius: 16px 16px 2px 16px;
		max-width: 75%;
	}

	.user-bubble .bubble-time {
		text-align: right;
		opacity: 0.7;
	}

	/* ---- Assistant: left-aligned, surface bubble, tail on bottom-left, with avatar ---- */
	.assistant-row {
		display: flex;
		align-items: flex-start;
		gap: 10px;
	}

	.avatar {
		width: 28px;
		height: 28px;
		border-radius: 50%;
		display: flex;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
		overflow: hidden;
	}

	.assistant-avatar {
		background: var(--accent-1);
		color: var(--text-inverse);
	}

	.assistant-bubble {
		background: var(--surface-2);
		border: 1px solid var(--border-color-2);
		color: var(--text-primary);
		border-radius: 16px 16px 16px 2px;
		max-width: 85%;
	}

	.assistant-bubble .bubble-time {
		color: var(--text-tertiary);
	}

	/* ===== Tool Calls (compact row + collapsible details) ===== */
	.tool-row {
		padding-left: 38px;
	}

	.tool-call {
		display: flex;
		flex-direction: column;
		gap: 4px;
	}

	.tool-header {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 6px 10px;
		background: var(--surface-2);
		border: 1px solid var(--border-color-2);
		border-radius: 6px;
		font-size: 12px;
		color: var(--text-secondary);
	}

	.tool-icon {
		color: var(--warning);
		display: flex;
		align-items: center;
		flex-shrink: 0;
	}

	.tool-name {
		flex: 1;
		font-family: var(--font-mono, monospace);
		font-size: 12px;
		font-weight: 500;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.tool-status {
		font-size: 10px;
		padding: 1px 8px;
		border-radius: 9999px;
		background: var(--surface-3);
		color: var(--text-secondary);
		font-family: var(--font-system);
		flex-shrink: 0;
	}

	.tool-details {
		margin-top: 2px;
	}

	.tool-summary {
		font-size: 11px;
		color: var(--text-tertiary);
		cursor: pointer;
		list-style: none;
		padding: 2px 10px;
		user-select: none;
	}

	.tool-summary::-webkit-details-marker {
		display: none;
	}

	.tool-summary::before {
		content: '\25B8 ';
	}

	.tool-body {
		font-size: var(--font-size-xs, 11px);
		color: var(--text-secondary);
		white-space: pre-wrap;
		overflow-x: auto;
		margin: 4px 0 0 0;
		padding: 8px 10px;
		background: var(--surface-2);
		border-radius: 6px;
		font-family: var(--font-mono, monospace);
		line-height: var(--line-height-normal);
	}

	/* ===== Notices (subtle background, small colored dot) ===== */
	.notice-row {
		display: flex;
		justify-content: center;
	}

	.notice-pill {
		display: inline-flex;
		align-items: center;
		gap: 8px;
		font-size: 12px;
		color: var(--text-secondary);
		background: var(--surface-2);
		padding: 6px 14px;
		border-radius: 6px;
		max-width: 80%;
	}

	.notice-dot {
		width: 6px;
		height: 6px;
		border-radius: 50%;
		flex-shrink: 0;
	}

	.notice-pill .notice-dot {
		background: var(--info);
	}

	.notice-pill.warning {
		color: var(--warning);
		background: rgba(255, 149, 0, 0.08);
	}

	.notice-pill.warning .notice-dot {
		background: var(--warning);
	}

	.notice-pill.error {
		color: var(--danger);
		background: rgba(255, 59, 48, 0.08);
	}

	.notice-pill.error .notice-dot {
		background: var(--danger);
	}

	.notice-text {
		white-space: pre-wrap;
		word-wrap: break-word;
	}

	/* ===== Reasoning (collapsible, subtle) ===== */
	.reasoning {
		max-width: 85%;
	}

	.reasoning-toggle {
		font-size: 11px;
		color: var(--text-tertiary);
		cursor: pointer;
		user-select: none;
		list-style: none;
		padding: 2px 0;
	}

	.reasoning-toggle::-webkit-details-marker {
		display: none;
	}

	.reasoning-toggle::before {
		content: '\25B8 ';
	}

	.reasoning-body {
		font-size: 11px;
		color: var(--text-tertiary);
		font-style: italic;
		white-space: pre-wrap;
		padding: 4px 0 4px 14px;
		border-left: 2px solid var(--surface-3);
		margin-top: 4px;
	}

	/* ===== System messages ===== */
	.system-row {
		text-align: center;
	}

	.system-label {
		font-size: 11px;
		color: var(--text-tertiary);
		font-style: italic;
	}

	/* ===== Empty State ===== */
	.empty-state {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		height: 100%;
		padding: 48px 24px;
		text-align: center;
	}

	.empty-logo {
		margin-bottom: 16px;
		opacity: 0.4;
	}

	.empty-state h3 {
		color: var(--text-secondary);
		margin-bottom: 8px;
		font-size: var(--font-size-md, 14px);
		font-weight: 500;
	}

	.empty-state p {
		font-size: var(--font-size-sm, 12px);
		color: var(--text-tertiary);
		max-width: 280px;
		line-height: 1.5;
	}

	/* ===== Slim Scrollbar (5px, rounded thumb, transparent track) ===== */
	.chat-timeline::-webkit-scrollbar {
		width: 5px;
	}

	.chat-timeline::-webkit-scrollbar-track {
		background: transparent;
	}

	.chat-timeline::-webkit-scrollbar-thumb {
		background: var(--surface-4);
		border-radius: var(--radius-full, 9999px);
	}

	.chat-timeline::-webkit-scrollbar-thumb:hover {
		background: var(--surface-5);
	}
</style>
