<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import type { ChatThread, ThreadDocument, TimelineItem, Attachment, ToolCall, AssistantMessage, ReasoningBlock, UserMessage, Notice, ProposedPlan, TodoStep, TurnSummary } from '$lib/types';
	import MarkdownRenderer from './MarkdownRenderer.svelte';
	import WorkingIndicator from './WorkingIndicator.svelte';
	import AttachmentPreview from './AttachmentPreview.svelte';
	import ChromeRow from './ChromeRow.svelte';
	import Composer from './Composer.svelte';
	import TerminalPanel from './TerminalPanel.svelte';

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
	let reasoningVisible = $state(true);
	let previewAttachment = $state<Attachment | null>(null);
	let planStates = $state<Map<string, 'drafting' | 'proposed' | 'accepted' | 'dismissed'>>(new Map());

	// ---- Data loading ----

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

	// ---- Auto-scroll ----

	$effect(() => {
		if (doc?.items && scrollContainer && autoScroll) {
			scrollContainer.scrollTop = scrollContainer.scrollHeight;
		}
	});

	function handleScroll() {
		if (!scrollContainer) return;
		const { scrollTop, scrollHeight, clientHeight } = scrollContainer;
		autoScroll = scrollHeight - scrollTop - clientHeight < 80;
		isAtBottom = scrollHeight - scrollTop - clientHeight < 30;
		showJumpToLatest = !isAtBottom;
	}

	function scrollToBottom() {
		if (!scrollContainer) return;
		scrollContainer.scrollTop = scrollContainer.scrollHeight;
		showJumpToLatest = false;
		isAtBottom = true;
	}

	// ---- Item type guards ----

	function isUserMessage(item: TimelineItem): item is { content: { type: 'user'; value: UserMessage } } {
		return item.content.type === 'user';
	}
	function isAssistantMessage(item: TimelineItem): item is { content: { type: 'assistant'; value: AssistantMessage } } {
		return item.content.type === 'assistant';
	}
	function isToolCall(item: TimelineItem): item is { content: { type: 'tool'; value: ToolCall } } {
		return item.content.type === 'tool';
	}
	function isReasoning(item: TimelineItem): item is { content: { type: 'reasoning'; value: ReasoningBlock } } {
		return item.content.type === 'reasoning';
	}
	function isNotice(item: TimelineItem): item is { content: { type: 'notice'; value: Notice } } {
		return item.content.type === 'notice';
	}
	function isPlan(item: TimelineItem): item is { content: { type: 'plan'; value: ProposedPlan } } {
		return item.content.type === 'plan';
	}
	function isTodo(item: TimelineItem): item is { content: { type: 'todos'; value: TodoStep[] } } {
		return item.content.type === 'todos';
	}
	function isTurnEnd(item: TimelineItem): item is { content: { type: 'turn_end'; value: TurnSummary } } {
		return item.content.type === 'turn_end';
	}

	// ---- Plan state helpers ----

	function getPlanState(item: TimelineItem): 'drafting' | 'proposed' | 'accepted' | 'dismissed' {
		const existing = planStates.get(item.id);
		if (existing) return existing;
		if (isPlan(item)) return item.content.value.state;
		return 'drafting';
	}

	function cyclePlanState(item: TimelineItem) {
		const current = getPlanState(item);
		const cycle: ('drafting' | 'proposed' | 'accepted' | 'dismissed')[] = ['drafting', 'proposed', 'accepted', 'dismissed'];
		const idx = cycle.indexOf(current);
		const next = cycle[(idx + 1) % cycle.length];
		planStates.update(m => { m.set(item.id, next); return m; });
	}

	// ---- Tool helpers ----

	function getToolIcon(kind: string): string {
		switch (kind) {
			case 'command': return 'M14.7 6.3a1 1 0 0 0 0 1.4l1.6 1.6a1 1 0 0 0 1.4 0l3.77-3.77a6 6 0 0 1-7.94 7.94l-6.91 6.91a2.12 2.12 0 0 1-3-3l6.91-6.91a6 6 0 0 1 7.94-7.94l-3.76 3.76z';
			case 'read': return 'M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z M14 2v6h6';
			case 'edit': return 'M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7 M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z';
			case 'search': return 'M21 21l-6-6m2-5a7 7 0 1 1-14 0 7 7 0 0 1 14 0z';
			case 'web': return 'M12 2a10 10 0 0 1 10 10c0 5.52-4.48 10-10 10S2 17.52 7 12m0-2C3.67 10 1 13.33 1 17.33h2C3 14.28 5.67 12 9 12c.18 0 .36 0 .54.02A9.996 9.996 0 0 0 12 2z';
			case 'mcp': return 'M13 2L3 14h9l-1 8 10-12h-9l1-8z';
			case 'agent': return 'M12 2a2 2 0 0 1 2 2c0 .74-.4 1.39-1 1.73V7h1a7 7 0 0 1 7 7h1a1 1 0 0 1 1 1v3a1 1 0 0 1-1 1h-1v1a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-1H2a1 1 0 0 1-1-1v-3a1 1 0 0 1 1-1h1a7 7 0 0 1 7-7h1V5.73c-.6-.34-1-.99-1-1.73a2 2 0 0 1 2-2z M8 13a2 2 0 1 0 0 4 2 2 0 0 0 0-4zm8 0a2 2 0 1 0 0 4 2 2 0 0 0 0-4z';
			default: return 'M12 2l2 4 4 1-3 3 1 4-4-2-4 2 1-4-3-3 4-1z';
		}
	}

	function getToolStatusClass(status: string): string {
		switch (status) {
			case 'running': return 'tool-running';
			case 'completed': return 'tool-completed';
			case 'failed': return 'tool-failed';
			case 'declined': return 'tool-declined';
			default: return 'tool-unknown';
		}
	}

	function hasFileEdits(tool: ToolCall): boolean {
		return tool.edits && tool.edits.length > 0;
	}

	// ---- Formatting ----

	let timeFormatter = $derived(new Intl.DateTimeFormat('en-US', {
		hour: 'numeric',
		minute: '2-digit',
		hour12: true
	}));

	function formatTime(dateStr: string): string {
		return timeFormatter.format(new Date(dateStr));
	}

	function formatDuration(startedAt: string, finishedAt: string | null): string {
		const start = new Date(startedAt).getTime();
		const end = finishedAt ? new Date(finishedAt).getTime() : Date.now();
		const sec = Math.max(0, Math.floor((end - start) / 1000));
		if (sec < 60) return `${sec}s`;
		const min = Math.floor(sec / 60);
		const s = sec % 60;
		return `${min}m ${s}s`;
	}

	function formatToolOutput(output: string, maxLines: number = 20): string {
		const lines = output.split('\n');
		if (lines.length <= maxLines) return output;
		return lines.slice(0, maxLines).join('\n') + `\n... (${lines.length - maxLines} more lines)`;
	}

	// ---- Keyboard ----

	function handleKeyDown(e: KeyboardEvent) {
		// Toggle reasoning with Cmd/Ctrl+Shift+R
		if ((e.metaKey || e.ctrlKey) && e.shiftKey && e.key === 'R') {
			e.preventDefault();
			reasoningVisible = !reasoningVisible;
		}
	}

	onDestroy(() => {
		// Cleanup handled by Svelte reactivity
	});

	// ---- Computed ----

	let hasReasoning = $derived(doc?.items?.some(i => i.content.type === 'reasoning') ?? false);
	let isGenerating = $derived(thread.last_status === 'running' || thread.hydra?.status === 'running');
	let threadMessages = $derived(doc?.items ?? []);
	let isRepository = $derived(false);
	let branches = $derived<string[]>(thread.branch ? [thread.branch] : []);
	let hydraEnabled = $derived(thread.hydra_enabled ?? false);
	let directory = $derived('');
	let showJumpToLatest = $state(false);
	let isAtBottom = $state(true);
	let showHydraPanel = $state(false);
	let showSubagentPanel = $state(false);
</script>

<svelte:window onkeydown={handleKeyDown} />

<div class="chat-view" class:generating={isGenerating}>
	<div class="chat-column">
		<!-- Chrome row -->
		<ChromeRow
			{thread}
			projectName={null}
			{directory}
			{isRepository}
			{branches}
			{hydraEnabled}
			{isGenerating}
			onToggleTerminal={() => onToggleTerminal?.()}
			onToggleHydra={() => showHydraPanel = !showHydraPanel}
			onToggleSubagent={() => showSubagentPanel = !showSubagentPanel}
		/>

		<!-- Scrollable timeline -->
		<div class="chat-pane">

		<!-- Timeline -->
		<div class="chat-timeline" bind:this={scrollContainer} onscroll={handleScroll} role="log" aria-label="Conversation">
		{#if doc && threadMessages.length > 0}
			<div class="timeline">
				{#each threadMessages as item (item.id)}
					{#if isReasoning(item)}
						{#if reasoningVisible}
							<div class="timeline-item reasoning-block">
								<details open class="reasoning-details">
									<summary class="reasoning-toggle">
										<span class="reasoning-icon">&#x2728;</span> Reasoning
									</summary>
									<div class="reasoning-body">
										<MarkdownRenderer content={item.content.value.text} class="reasoning-markdown" />
									</div>
								</details>
							</div>
						{/if}

					{:else if isUserMessage(item)}
						{@const userMsg = item.content.value}
						<div class="timeline-item user-row">
							<div class="bubble user-bubble">
								{#if userMsg.text}
									<div class="bubble-text">{userMsg.text}</div>
								{/if}
								{#if userMsg.attachments && userMsg.attachments.length > 0}
									<div class="attachments-row">
										{#each userMsg.attachments as att (att.id)}
											<button class="attachment-thumb" onclick={() => previewAttachment = att} title={att.name}>
												<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
													<path d="M13 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/>
													<polyline points="13 2 13 9 20 9"/>
												</svg>
												<span class="att-thumb-name">{att.name}</span>
											</button>
										{/each}
									</div>
								{/if}
								<span class="bubble-time">{formatTime(item.date)}</span>
							</div>
						</div>

					{:else if isAssistantMessage(item)}
						{@const asstMsg = item.content.value}
						<div class="timeline-item assistant-row">
							<div class="avatar assistant-avatar">
								<img src="/icons/swarmcode-logo.svg" alt="Swarm Code" width="14" height="14" />
							</div>
							<div class="bubble assistant-bubble" class:streaming={asstMsg.is_streaming}>
								{#if asstMsg.text}
									<MarkdownRenderer content={asstMsg.text} class="message-markdown" />
								{:else if asstMsg.is_streaming}
									<div class="streaming-placeholder">
										<span class="streaming-cursor">&#x2588;</span>
									</div>
								{/if}
								<span class="bubble-time">{formatTime(item.date)}</span>
							</div>
						</div>

					{:else if isPlan(item)}
						{@const plan = item.content.value}
						{@const planState = getPlanState(item)}
						<div class="timeline-item plan-block">
							<div class="plan-card state-{planState}">
								<div class="plan-header">
									<span class="plan-icon">&#x2637;</span>
									<span class="plan-state-badge">{planState}</span>
									<button class="plan-cycle-btn" onclick={() => cyclePlanState(item)} title="Cycle plan state">
										&#x21BB;
									</button>
								</div>
								<div class="plan-body">
									<MarkdownRenderer content={plan.markdown} class="plan-markdown" />
								</div>
							</div>
						</div>

					{:else if isTodo(item)}
						{@const todos = item.content.value}
						<div class="timeline-item todo-block">
							<div class="todo-card">
								<div class="todo-list">
									{#each todos as todo, i (i)}
										<div class="todo-item status-{todo.status}">
											<span class="todo-check">
												{#if todo.status === 'done'}
													<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3"><path d="M20 6L9 17l-5-5"/></svg>
												{:else if todo.status === 'active'}
													<span class="todo-spinner"></span>
												{:else}
													<span class="todo-empty"></span>
												{/if}
											</span>
											<span class="todo-text">{todo.text}</span>
										</div>
									{/each}
								</div>
							</div>
						</div>

					{:else if isToolCall(item)}
						{@const tool = item.content.value}
						<div class="timeline-item tool-row">
							<div class="tool-card">
								<div class="tool-header">
									<span class="tool-icon-wrap">
										<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
											<path d={getToolIcon(tool.kind)}/>
										</svg>
									</span>
									<span class="tool-kind">{tool.kind}</span>
									<span class="tool-title">{tool.title}</span>
									<span class="tool-duration">{formatDuration(tool.started_at, tool.finished_at)}</span>
									<span class="tool-status {getToolStatusClass(tool.status)}">
										{tool.status}
									</span>
								</div>
								{#if tool.output}
									<details class="tool-details">
										<summary class="tool-summary">
											output
											{#if tool.output.split('\n').length > 5}
												<span class="tool-line-count">{tool.output.split('\n').length} lines</span>
											{/if}
										</summary>
										<pre class="tool-body">{formatToolOutput(tool.output)}</pre>
									</details>
								{/if}
								{#if hasFileEdits(tool)}
									<div class="tool-edits">
										<span class="tool-edits-label">{tool.edits.length} file{tool.edits.length !== 1 ? 's' : ''} changed</span>
										{#each tool.edits as edit (edit.path)}
											<span class="tool-edit-chip" class:added={edit.additions > 0 && edit.deletions === 0} class:deleted={edit.deletions > 0 && edit.additions === 0} class:modified={edit.additions > 0 && edit.deletions > 0}>
												{edit.path}
												{#if edit.additions > 0}<span class="edit-stat edit-add">+{edit.additions}</span>{/if}
												{#if edit.deletions > 0}<span class="edit-stat edit-del">−{edit.deletions}</span>{/if}
											</span>
										{/each}
									</div>
								{/if}
							</div>
						</div>

					{:else if isTurnEnd(item)}
						{@const turn = item.content.value}
						<div class="timeline-item turn-end-block">
							<div class="turn-end-card">
								<span class="turn-end-icon">&#x2713;</span>
								<span class="turn-end-text">
									Turn {turn.index + 1} complete
									{#if turn.files_changed > 0}
										· {turn.files_changed} files · +{turn.additions} −{turn.deletions}
									{/if}
								</span>
							</div>
						</div>

					{:else if isNotice(item)}
						{@const notice = item.content.value}
						<div class="timeline-item notice-row">
							<div class="notice-pill notice-{notice.level}">
								<span class="notice-dot"></span>
								<span class="notice-text">{notice.message}</span>
							</div>
						</div>
					{/if}
				{/each}
			</div>
		{:else}
			<div class="empty-state">
				<div class="empty-logo">
					<img src="/icons/swarmcode-logo.svg" alt="Swarm Code" width="48" height="48" />
				</div>
				<h3>No messages yet</h3>
				<p>Type a message below to start the conversation.</p>
			</div>
		{/if}

		<!-- Composer area (inside ChatView, matching Swift) -->
		<div class="composer-area">
			<Composer {thread} />
		</div>

		<!-- JumpToLatestButton -->
		{#if showJumpToLatest && !isAtBottom}
			<button class="jump-to-latest" onclick={scrollToBottom} title="Jump to latest">
				<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
					<path d="M12 5v14M5 12l7 7 7-7"/>
				</svg>
			</button>
		{/if}
	</div>

	<!-- Terminal overlay -->
	{#if terminalVisible}
		<TerminalPanel threadId={thread.id} />
	{/if}

	<!-- Hydra panel overlay -->
	{#if showHydraPanel}
		<div class="floating-panel hydra-panel-overlay">
			<HydraPanel threadId={thread.id} onClose={() => showHydraPanel = false} />
		</div>
	{/if}

	<!-- Subagent panel overlay -->
	{#if showSubagentPanel}
		<div class="floating-panel subagent-panel-overlay">
			<SubagentPanel threadId={thread.id} isExpanded={true} />
		</div>
	{/if}

	<!-- Attachment preview modal -->
	{#if previewAttachment}
		<AttachmentPreview
			attachment={previewAttachment}
			onClose={() => previewAttachment = null}
		/>
	{/if}
</div>
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

	/* ===== Chrome Header ===== */
	.chat-chrome {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 6px 16px;
		border-bottom: var(--border-1) var(--border-color-2);
		background: var(--surface-2);
		flex-shrink: 0;
		min-height: 40px;
		gap: var(--space-3);
	}

	.chrome-left {
		display: flex;
		align-items: center;
		gap: 8px;
		min-width: 0;
		flex: 1;
	}

	.chrome-title {
		font-size: var(--font-size-sm);
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
		font-family: var(--font-mono);
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
		flex-shrink: 0;
	}

	.chrome-model, .chrome-effort, .chrome-mode {
		font-size: 11px;
		color: var(--text-tertiary);
		white-space: nowrap;
	}

	.chrome-git {
		font-size: 11px;
		color: var(--text-tertiary);
		white-space: nowrap;
		font-family: var(--font-mono);
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
		animation: hydra-pulse 1.5s ease-in-out infinite;
	}

	@keyframes hydra-pulse {
		0%, 100% { opacity: 1; }
		50% { opacity: 0.4; }
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

	/* ===== Generating indicator ===== */
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

	.gen-dot:nth-child(2) { animation-delay: 0.2s; }
	.gen-dot:nth-child(3) { animation-delay: 0.4s; }

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

	.chat-timeline:focus-visible {
		outline: none;
	}

	.timeline {
		padding: 16px 0;
	}

	.timeline-item {
		margin-bottom: 16px;
		padding: 0 20px;
	}

	/* ===== User Message ===== */
	.user-row {
		display: flex;
		justify-content: flex-end;
	}

	.user-bubble {
		background: var(--accent-1);
		color: var(--text-inverse);
		border-radius: 16px 16px 2px 16px;
		max-width: 75%;
		padding: 10px 14px;
	}

	.user-bubble .bubble-text {
		white-space: pre-wrap;
		word-wrap: break-word;
		line-height: 1.5;
		font-size: var(--font-size-md);
	}

	.user-bubble .attachments-row {
		display: flex;
		flex-wrap: wrap;
		gap: 6px;
		margin-top: 8px;
		padding-top: 8px;
		border-top: 1px solid rgba(255,255,255,0.2);
	}

	.attachment-thumb {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		padding: 3px 8px;
		background: rgba(255,255,255,0.2);
		border-radius: var(--radius-full);
		font-size: 11px;
		color: rgba(255,255,255,0.9);
		cursor: pointer;
		border: none;
		transition: background 0.15s;
	}

	.attachment-thumb:hover {
		background: rgba(255,255,255,0.3);
	}

	.att-thumb-name {
		max-width: 120px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.user-bubble .bubble-time {
		display: block;
		font-size: 10px;
		margin-top: 4px;
		text-align: right;
		opacity: 0.7;
	}

	/* ===== Assistant Message ===== */
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
		background: var(--accent-1);
		color: var(--text-inverse);
	}

	.assistant-bubble {
		background: var(--surface-2);
		border: 1px solid var(--border-color-2);
		color: var(--text-primary);
		border-radius: 16px 16px 16px 2px;
		max-width: 85%;
		padding: 12px 16px;
		line-height: 1.6;
	}

	.assistant-bubble.streaming {
		border-color: var(--accent-3);
	}

	.message-markdown {
		font-size: var(--font-size-md);
		line-height: var(--line-height-normal);
	}

	.message-markdown :global(p) {
		margin-bottom: 0.5em;
	}

	.message-markdown :global(p:last-child) {
		margin-bottom: 0;
	}

	.streaming-placeholder {
		display: flex;
		align-items: center;
		gap: 2px;
	}

	.streaming-cursor {
		color: var(--accent-1);
		animation: cursor-blink 0.8s step-end infinite;
		font-size: var(--font-size-md);
	}

	@keyframes cursor-blink {
		0%, 100% { opacity: 1; }
		50% { opacity: 0; }
	}

	.assistant-bubble .bubble-time {
		display: block;
		font-size: 10px;
		margin-top: 6px;
		color: var(--text-tertiary);
	}

	/* ===== Reasoning ===== */
	.reasoning-block {
		max-width: 85%;
	}

	.reasoning-details {
		border: 1px solid var(--border-color-2);
		border-radius: var(--radius-md);
		background: var(--surface-2);
		overflow: hidden;
	}

	.reasoning-toggle {
		font-size: 11px;
		color: var(--text-tertiary);
		cursor: pointer;
		user-select: none;
		list-style: none;
		padding: 6px 10px;
		display: flex;
		align-items: center;
		gap: 6px;
		font-weight: 500;
	}

	.reasoning-toggle::-webkit-details-marker {
		display: none;
	}

	.reasoning-toggle::before {
		content: '\25B8 ';
	}

	.reasoning-details[open] .reasoning-toggle::before {
		content: '\25BE ';
	}

	.reasoning-body {
		padding: 8px 12px 12px;
		border-top: 1px solid var(--border-color-2);
	}

	.reasoning-markdown {
		font-size: 12px;
		color: var(--text-tertiary);
		font-style: italic;
	}

	.reasoning-markdown :global(p) {
		margin-bottom: 0.4em;
	}

	.reasoning-icon {
		font-size: 10px;
	}

	/* ===== Tool Calls ===== */
	.tool-row {
		padding-left: 38px;
	}

	.tool-card {
		display: flex;
		flex-direction: column;
		gap: 4px;
		max-width: 85%;
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

	.tool-icon-wrap {
		display: flex;
		align-items: center;
		flex-shrink: 0;
		color: var(--warning);
	}

	.tool-kind {
		font-family: var(--font-mono);
		font-size: 10px;
		text-transform: uppercase;
		letter-spacing: 0.4px;
		color: var(--text-tertiary);
		background: var(--surface-3);
		padding: 1px 5px;
		border-radius: 3px;
		flex-shrink: 0;
	}

	.tool-title {
		flex: 1;
		font-family: var(--font-mono);
		font-size: 12px;
		font-weight: 500;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
		min-width: 0;
	}

	.tool-duration {
		font-size: 10px;
		font-family: var(--font-mono);
		color: var(--text-tertiary);
		flex-shrink: 0;
	}

	.tool-status {
		font-size: 10px;
		padding: 1px 8px;
		border-radius: 9999px;
		font-family: var(--font-system);
		flex-shrink: 0;
		font-weight: 500;
	}

	.tool-running {
		background: rgba(90, 200, 250, 0.12);
		color: var(--info);
	}
	.tool-completed {
		background: rgba(52, 199, 89, 0.12);
		color: var(--success);
	}
	.tool-failed {
		background: rgba(255, 59, 48, 0.12);
		color: var(--danger);
	}
	.tool-declined {
		background: rgba(255, 149, 0, 0.12);
		color: var(--warning);
	}
	.tool-unknown {
		background: var(--surface-3);
		color: var(--text-secondary);
	}

	.tool-details {
		margin-top: 2px;
	}

	.tool-summary {
		font-size: 11px;
		color: var(--text-tertiary);
		cursor: pointer;
		user-select: none;
		list-style: none;
		padding: 2px 10px;
		display: flex;
		align-items: center;
		gap: 6px;
	}

	.tool-summary::-webkit-details-marker {
		display: none;
	}

	.tool-summary::before {
		content: '\25B8 ';
	}

	.tool-line-count {
		font-size: 10px;
		opacity: 0.7;
	}

	.tool-body {
		font-size: var(--font-size-xs);
		color: var(--text-secondary);
		white-space: pre-wrap;
		overflow-x: auto;
		margin: 4px 0 0 0;
		padding: 8px 10px;
		background: var(--surface-2);
		border-radius: 6px;
		font-family: var(--font-mono);
		line-height: var(--line-height-normal);
		max-height: 300px;
		overflow-y: auto;
	}

	.tool-edits {
		display: flex;
		flex-wrap: wrap;
		gap: 4px;
		padding: 4px 10px 8px;
	}

	.tool-edits-label {
		font-size: 10px;
		color: var(--text-tertiary);
		width: 100%;
		margin-bottom: 2px;
	}

	.tool-edit-chip {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		font-size: 10px;
		font-family: var(--font-mono);
		padding: 1px 8px;
		border-radius: var(--radius-full);
		background: var(--surface-3);
		color: var(--text-secondary);
		max-width: 200px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.tool-edit-chip.added {
		background: rgba(52, 199, 89, 0.1);
		color: var(--success);
	}

	.tool-edit-chip.deleted {
		background: rgba(255, 59, 48, 0.1);
		color: var(--danger);
	}

	.tool-edit-chip.modified {
		background: rgba(255, 149, 0, 0.1);
		color: var(--warning);
	}

	.edit-stat {
		font-size: 9px;
		font-weight: 600;
	}

	.edit-add { color: var(--success); }
	.edit-del { color: var(--danger); }

	/* ===== Plan Block ===== */
	.plan-block {
		max-width: 85%;
	}

	.plan-card {
		border: 1px solid var(--border-color-2);
		border-radius: var(--radius-lg);
		background: var(--surface-2);
		overflow: hidden;
	}

	.plan-card.state-drafting {
		border-left: 3px solid var(--text-tertiary);
	}
	.plan-card.state-proposed {
		border-left: 3px solid var(--accent-1);
	}
	.plan-card.state-accepted {
		border-left: 3px solid var(--success);
	}
	.plan-card.state-dismissed {
		border-left: 3px solid var(--danger);
		opacity: 0.7;
	}

	.plan-header {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 6px 12px;
		border-bottom: 1px solid var(--border-color-2);
		background: var(--surface-3);
	}

	.plan-icon {
		font-size: 13px;
	}

	.plan-state-badge {
		font-size: 10px;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.4px;
	}

	.state-drafting .plan-state-badge { color: var(--text-tertiary); }
	.state-proposed .plan-state-badge { color: var(--accent-1); }
	.state-accepted .plan-state-badge { color: var(--success); }
	.state-dismissed .plan-state-badge { color: var(--danger); }

	.plan-cycle-btn {
		margin-left: auto;
		width: 20px;
		height: 20px;
		border: none;
		background: transparent;
		border-radius: 4px;
		color: var(--text-tertiary);
		cursor: pointer;
		font-size: 14px;
		display: flex;
		align-items: center;
		justify-content: center;
		transition: all 0.15s;
	}

	.plan-cycle-btn:hover {
		background: var(--surface-4);
		color: var(--text-primary);
	}

	.plan-body {
		padding: 12px 14px;
	}

	.plan-markdown {
		font-size: var(--font-size-sm);
	}

	/* ===== Todo Block ===== */
	.todo-card {
		border: 1px solid var(--border-color-2);
		border-radius: var(--radius-md);
		background: var(--surface-2);
		padding: 10px 14px;
		max-width: 85%;
	}

	.todo-list {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}

	.todo-item {
		display: flex;
		align-items: center;
		gap: 8px;
		font-size: var(--font-size-sm);
	}

	.todo-item.status-pending {
		color: var(--text-tertiary);
	}

	.todo-item.status-active {
		color: var(--text-primary);
	}

	.todo-item.status-done {
		color: var(--text-tertiary);
	}

	.todo-check {
		width: 14px;
		height: 14px;
		display: flex;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
	}

	.todo-spinner {
		width: 10px;
		height: 10px;
		border: 2px solid var(--accent-3);
		border-top-color: var(--accent-1);
		border-radius: 50%;
		animation: spin 0.7s linear infinite;
	}

	.todo-empty {
		width: 8px;
		height: 8px;
		border: 1.5px solid var(--text-tertiary);
		border-radius: 2px;
	}

	.todo-text {
		flex: 1;
	}

	/* ===== Turn End ===== */
	.turn-end-block {
		display: flex;
		justify-content: center;
	}

	.turn-end-card {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 4px 12px;
		font-size: 11px;
		color: var(--text-tertiary);
		background: var(--surface-2);
		border-radius: var(--radius-full);
		border: 1px solid var(--border-color-2);
	}

	.turn-end-icon {
		color: var(--success);
		font-size: 12px;
	}

	/* ===== Notices ===== */
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

	.notice-info {
		color: var(--info);
		background: rgba(90, 200, 250, 0.08);
	}
	.notice-info .notice-dot {
		background: var(--info);
	}

	.notice-warning {
		color: var(--warning);
		background: rgba(255, 149, 0, 0.08);
	}
	.notice-warning .notice-dot {
		background: var(--warning);
	}

	.notice-error {
		color: var(--danger);
		background: rgba(255, 59, 48, 0.08);
	}
	.notice-error .notice-dot {
		background: var(--danger);
	}

	.notice-text {
		white-space: pre-wrap;
		word-wrap: break-word;
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
		font-size: var(--font-size-md);
		font-weight: 500;
	}

	.empty-state p {
		font-size: var(--font-size-sm);
		color: var(--text-tertiary);
		max-width: 280px;
		line-height: 1.5;
	}

	/* ===== Scrollbar ===== */
	.chat-timeline::-webkit-scrollbar {
		width: 5px;
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

	@keyframes spin {
		to { transform: rotate(360deg); }
	}

	/* ===== Chat column — Swift ChatView VStack(spacing: 0) ===== */
	.chat-column {
		display: flex;
		flex-direction: column;
		height: 100%;
		max-width: 820px;
		margin: 0 auto;
		position: relative;
	}

	.chat-pane {
		flex: 1;
		display: flex;
		flex-direction: column;
		min-height: 0;
	}

	/* ===== Composer area ===== */
	.composer-area {
		flex-shrink: 0;
		position: relative;
	}
</style>
