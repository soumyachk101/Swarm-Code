<script lang="ts">
	// ---------------------------------------------------------------------------
	// Composer – self-contained. Matches Swift ComposerView: placeholder logic,
	// suggestions popover, attachments, history recall, send/steer, running dots.
	// ---------------------------------------------------------------------------

	import { onMount, tick } from 'svelte';
	import { sendMessage, sendFollowUp, approveRequest, answerQuestion } from '$lib/api/commands';
	import { appStore } from '$lib/stores/appStore';
	import {
		isGenerating,
		stopGeneration,
		effortLevel,
		attachments,
		addAttachment,
		removeAttachment,
		clearAttachments,
		followUps,
		pendingApprovals,
		pendingQuestions,
		changeStats
	} from '$lib/stores/chatStore';
	import type { ChatThread, DraftAttachment } from '$lib/types';

	interface Props {
		thread: ChatThread | null;
	}

	let { thread = null }: Props = $props();

	let textarea = $state<HTMLTextAreaElement | null>(null);
	let messageText = $state('');
	let effortValue = $state<string | null>(null);
	let showEffortSlider = $state(false);
	let isSubmitting = $state(false);
	let isFocusMode = $state(false);
	let showToolPicker = $state(false);
	let showSuggestions = $state(false);
	let suggestionKind = $state<'command' | 'file'>('command');
	let suggestionItems = $state<Array<{ id: string; title: string; detail: string; symbol: string; value: string }>>([]);
	let selectedSuggestionIndex = $state(0);
	let attachmentNotice = $state<string | null>(null);
	let suggestionRange = $state({ start: 0, end: 0 });
	let showRecents = $state(false);
	let recentsAnchor = $state<{ x: number; y: number } | null>(null);

	// Expose for parent tab slot
	let _showFollowUps = $derived(($followUps?.length ?? 0) > 0);
	let _showApprovals = $derived(($pendingApprovals?.length ?? 0) > 0);
	let _showQuestions = $derived(($pendingQuestions?.length ?? 0) > 0);

	let questionItems = $derived(
		($pendingQuestions ?? []).map((q: any) => ({
			id: q.id,
			headline: q.headline || q.text || q.message || 'Question',
			choices: Array.isArray(q.choices) ? q.choices : []
		}))
	);

	let followUpItems = $derived(
		($followUps ?? []).map((f: any) => ({
			id: f.id,
			text: f.text || f.headline || 'Follow-up'
		}))
	);

	let approvalItems = $derived(
		($pendingApprovals ?? []).map((a: any) => ({
			id: a.id,
			headline: a.headline || a.text || a.message || 'Approval needed',
			options: Array.isArray(a.options) && a.options.length
				? a.options.map((o: any) => (typeof o === 'string' ? o : o.title ?? o.role ?? 'Approve'))
				: ['Approve', 'Reject']
		}))
	);

	let isRunning = $derived($isGenerating);

	// ---------- placeholders ----------
	let placeholder = $derived.by(() => {
		if (!thread) return '';
		if (thread.interaction_mode === 'plan') return 'Describe what you want to plan';
		if (thread.hydra_enabled) {
			if ($appStore.hydra_always_heads) return 'Goes to a head; ' + (thread.provider || 'provider') + ' leads and reports back';
			return 'Ask ' + (thread.provider || '') + ' for anything; big jobs go out to a team of heads';
		}
		return 'Ask ' + (thread.provider || '') + ' to build, fix or explain. @ for files, / for commands';
	});

	// ---------- lifecycle ----------

	onMount(() => {
		effortValue = thread?.effort ?? $effortLevel;
	});

	$effect(() => {
		if (thread) {
			effortValue = thread.effort ?? $effortLevel;
		}
	});

	// ---------- focus ----------

	function focusTextarea() {
		textarea?.focus();
	}

	// ---------- send ----------

	async function handleSend() {
		if (!thread) return;
		const text = messageText.trim();
		const atts = getAttachmentsArray();
		if (!text && atts.length === 0) return;

		isSubmitting = true;
		try {
			if (isRunning) {
				await stopGeneration();
			}
			messageText = '';
			clearAttachments();
			await sendMessage(thread.id, text, atts, { effort: effortValue });
		} finally {
			isSubmitting = false;
			focusTextarea();
		}
	}

	function handleKeyDown(e: KeyboardEvent) {
		const mod = e.metaKey || e.ctrlKey;

		if (showSuggestions) {
			if (e.key === 'ArrowDown') {
				e.preventDefault();
				selectedSuggestionIndex = Math.min(selectedSuggestionIndex + 1, suggestionItems.length - 1);
				return;
			}
			if (e.key === 'ArrowUp') {
				e.preventDefault();
				selectedSuggestionIndex = Math.max(selectedSuggestionIndex - 1, 0);
				return;
			}
			if (e.key === 'Tab' || e.key === 'Enter') {
				e.preventDefault();
				pickSuggestion(suggestionItems[selectedSuggestionIndex]);
				return;
			}
			if (e.key === 'Escape') {
				showSuggestions = false;
				return;
			}
		}

		if (e.key === 'Enter' && !mod) {
			e.preventDefault();
			handleSend();
		}
		if (e.key === 'Enter' && mod) {
			// Command+Enter: queue / steer
			e.preventDefault();
			handleSend();
		}
	}

	// ---------- suggestions ----------

	async function refreshSuggestions() {
		if (!textarea) return;
		const text = textarea.value;
		const cursor = textarea.selectionStart ?? text.length;
		const start = findWordStart(text, cursor);
		const word = text.slice(start, cursor);
		const range = { start, end: cursor };

		if (word.startsWith('@')) {
			suggestionKind = 'file';
			const query = word.slice(1);
			const items = await searchFiles(query);
			if (items.length > 0 && start < cursor) {
				suggestionItems = items.slice(0, 8);
				selectedSuggestionIndex = 0;
				suggestionRange = range;
				showSuggestions = true;
			} else {
				showSuggestions = false;
			}
		} else if (word.startsWith('/') && start === 0) {
			suggestionKind = 'command';
			const items = commandSuggestions(word.slice(1));
			if (items.length > 0) {
				suggestionItems = items.slice(0, 8);
				selectedSuggestionIndex = 0;
				suggestionRange = range;
				showSuggestions = true;
			} else {
				showSuggestions = false;
			}
		} else {
			showSuggestions = false;
		}
	}

	function findWordStart(text: string, cursor: number): number {
		let i = cursor;
		while (i > 0) {
			const ch = text[i - 1];
			if (ch === ' ' || ch === '\n' || ch === '\t') break;
			i--;
		}
		return i;
	}

	async function searchFiles(query: string): Promise<Array<{ id: string; title: string; detail: string; symbol: string; value: string }>> {
		// Simplified: in production use the FileIndex API
		return [];
	}

	function commandSuggestions(query: string): Array<{ id: string; title: string; detail: string; symbol: string; value: string }> {
		const commands = [
			{ name: 'plan', detail: 'Turn plan mode on or off', isBuiltIn: true },
			{ name: 'compact', detail: 'Summarize the conversation to free up context', isBuiltIn: true },
		];
		const needle = query.toLowerCase();
		const prefixed = commands.filter(c => c.name.toLowerCase().startsWith(needle));
		const contained = commands.filter(c => !c.name.toLowerCase().startsWith(needle) && c.name.toLowerCase().includes(needle));
		return [...prefixed, ...contained].slice(0, 8).map(c => ({
			id: c.name,
			title: '/' + c.name,
			detail: c.detail,
			symbol: c.isBuiltIn ? 'command' : 'sparkles',
			value: '/' + c.name + ' '
		}));
	}

	function pickSuggestion(item: { id: string; value: string }) {
		if (!textarea) return;
		const text = textarea.value;
		const before = text.slice(0, suggestionRange.start);
		const after = text.slice(suggestionRange.end);
		messageText = before + item.value + after;
		showSuggestions = false;
		textarea.focus();
	}

	// ---------- attachments ----------

	function getAttachmentsArray(): AttachmentInfo[] {
		return ($attachments ?? []).map(a => ({ id: a.id, name: a.name, path: a.path, mime_type: a.mime_type }));
	}

	function handleDrop(e: DragEvent) {
		e.preventDefault();
		const files = e.dataTransfer?.files;
		if (!files || files.length === 0) return;
		for (const file of files) {
			const id = crypto.randomUUID();
			addAttachment({ id, name: file.name, path: file.name, mime_type: file.type || 'application/octet-stream' });
		}
	}

	function handleFileSelect(e: Event) {
		const input = e.target as HTMLInputElement;
		const files = input.files;
		if (!files) return;
		for (const file of files) {
			const id = crypto.randomUUID();
			addAttachment({ id, name: file.name, path: file.name, mime_type: file.type || 'application/octet-stream' });
		}
	}

	function handleRecentsPick(url: string) {
		showRecents = false;
		if (!url) return;
		addAttachment({
			id: crypto.randomUUID(),
			name: url.split('/').pop() || url,
			path: url,
			size: 0,
			data: null
		});
	}

	// ---------- follow-ups / approvals / questions ----------

	async function handleFollowUp(fuId: string) {
		if (!thread) return;
		await sendFollowUp(thread.id, fuId);
	}

	async function handleApprove(requestId: string, role: string) {
		if (!thread) return;
		await approveRequest(thread.id, requestId, role);
	}

	function handleAnswer(questionId: string, choices: string[]) {
		if (!thread) return;
		answerQuestion(thread.id, questionId, choices);
	}

	// ---------- focus mode ----------

	function toggleFocusMode() {
		isFocusMode = !isFocusMode;
		if (isFocusMode) {
			document.body.classList.add('focus-mode');
		} else {
			document.body.classList.remove('focus-mode');
		}
	}

	// ---------- history ----------

	let historyIndex: number | null = $state(null);
	let sentPrompts = $derived<string[]>([]); // would come from runtime

	function recallOlder() {
		if (historyIndex === null) {
			historyIndex = sentPrompts.length - 1;
		} else {
			historyIndex = Math.max(0, historyIndex - 1);
		}
		if (historyIndex !== null && historyIndex < sentPrompts.length) {
			messageText = sentPrompts[historyIndex];
		}
	}

	function recallNewer() {
		if (historyIndex === null) return;
		historyIndex = Math.min(sentPrompts.length - 1, historyIndex + 1);
		if (historyIndex !== null && historyIndex < sentPrompts.length) {
			messageText = sentPrompts[historyIndex];
		} else {
			historyIndex = null;
			messageText = '';
		}
	}

	// ---------- label types ----------
	type ApproxApproval = { id: string; headline: string; options: string[] };
	type ApproxQuestion = { id: string; headline: string; choices: string[] };
	type ApproxFollowUp = { id: string; text: string };
	type DraftAttachment = { id: string; name: string; path: string; size?: number; data?: string | null };
</script>

<!-- ============================================================
     Tab slot — Swift ComposerArea priority:
     approvals > questions > follow-ups > changes
     ============================================================ -->
{#if _showApprovals}
	<div class="slot-stack">
		{#each approvalItems as appr (appr.id)}
			<div class="slot-card approval-card">
				<p class="slot-card-text">{appr.headline}</p>
				<div class="slot-card-actions">
					{#each appr.options as opt}
						<button
							class="slot-action-btn"
							class:approve={opt.toLowerCase().includes('approv')}
							class:reject={opt.toLowerCase().includes('reject')}
							onclick={() => handleApprove(appr.id, opt)}
						>
							{opt}
						</button>
					{/each}
				</div>
			</div>
		{/each}
	</div>
{/if}

{#if _showQuestions}
	<div class="slot-stack">
		{#each questionItems as q (q.id)}
			<div class="slot-card question-card">
				<p class="slot-card-text">{q.headline}</p>
				{#if q.choices.length > 0}
					<div class="slot-card-actions">
						{#each q.choices as choice}
							<button
								class="slot-action-btn"
								onclick={() => handleAnswer(q.id, [choice])}
							>
								{choice}
							</button>
						{/each}
					</div>
				{/if}
			</div>
		{/each}
	</div>
{/if}

{#if _showFollowUps}
	<div class="slot-stack">
		{#each followUpItems as fu (fu.id)}
			<button class="slot-card followup-card" onclick={() => handleFollowUp(fu.id)}>
				<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
					<path d="M17 1l4 4-4 4"/>
					<path d="M3 11V9a4 4 0 0 1 4-4h14"/>
					<path d="M7 23l-4 4 4 4"/>
					<path d="M21 13v2a4 4 0 0 1-4 4H3"/>
				</svg>
				<span class="followup-text">{fu.text}</span>
				<span class="followup-arrow">&rsaquo;</span>
			</button>
		{/each}
	</div>
{/if}

<!-- ============================================================
     Composer pill — Swift ComposerView
     ============================================================ -->
<div
	class="composer-pill"
	class:is-running={isRunning}
	class:has-attachments={($attachments?.length ?? 0) > 0}
	role="textbox"
	aria-multiline="true"
	aria-label="Message composer"
>
	<!-- Running dots -->
	{#if isRunning}
		<div class="composer-dots">
			<span class="c-dot"></span>
			<span class="c-dot"></span>
			<span class="c-dot"></span>
			<span class="c-dot"></span>
		</div>
	{/if}

	<!-- Main row -->
	<div class="composer-main">
		<!-- Attachments + textarea -->
		<div class="composer-text-wrap" ondrop={handleDrop} ondragover={(e) => e.preventDefault()}>
			{#if ($attachments?.length ?? 0) > 0}
				<div class="attachment-chips">
					{#each $attachments as att (att.id)}
						<span class="att-chip">
							<span class="att-chip-name">{att.name}</span>
							<button class="att-chip-remove" onclick={() => removeAttachment(att.id)} aria-label="Remove attachment">
								<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
									<line x1="18" y1="6" x2="6" y2="18"/>
									<line x1="6" y1="6" x2="18" y2="18"/>
								</svg>
							</button>
						</span>
					{/each}
				</div>
			{/if}

			<textarea
				bind:this={textarea}
				bind:value={messageText}
				{placeholder}
				rows="1"
				disabled={isSubmitting}
				onkeydown={handleKeyDown}
				oninput={() => refreshSuggestions()}
				onfocus={() => { if (!showRecents) showRecents = false; }}
				class="composer-textarea"
			></textarea>

			{#if attachmentNotice}
				<div class="attachment-notice">{attachmentNotice}</div>
			{/if}

			{#if showSuggestions && suggestionItems.length > 0}
				<div class="suggestions-popover">
					{#each suggestionItems as item, idx (item.id)}
						<button
							class="suggestion-item"
							class:selected={idx === selectedSuggestionIndex}
							onclick={() => pickSuggestion(item)}
						>
							<span class="suggestion-symbol">
								{#if item.symbol === 'command'}
									<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>
								{:else if item.symbol === 'sparkles'}
									<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 2l2.4 7.2h7.6l-6 4.8 2.4 7.2-6-4.8-6 4.8 2.4-7.2-6-4.8h7.6z"/></svg>
								{:else}
									<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
								{/if}
							</span>
							<span class="suggestion-title">{item.title}</span>
							<span class="suggestion-detail">{item.detail}</span>
						</button>
					{/each}
				</div>
			{/if}
		</div>

		<!-- Controls -->
		<div class="composer-controls">
			{#if isRunning}
				<button
					class="ctrl-btn stop-btn"
					onclick={() => stopGeneration()}
					title="Stop generating"
					aria-label="Stop"
				>
					<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor">
						<rect x="6" y="6" width="12" height="12" rx="2"/>
					</svg>
				</button>
			{:else}
				<input type="file" id="composer-file-input" class="file-input" onchange={handleFileSelect} multiple />
				<button class="ctrl-btn" onclick={() => document.getElementById('composer-file-input')?.click()} title="Attach files" aria-label="Attach">
					<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
						<path d="M21.44 11.05l-9.19 9.19a6 6 0 0 1-8.49-8.49l9.19-9.19a4 4 0 0 1 5.66 5.66l-9.2 9.19a2 2 0 0 1-2.83-2.83l8.49-8.48"/>
					</svg>
				</button>

				<button
					class="ctrl-btn"
					class:active={showEffortSlider}
					onclick={() => showEffortSlider = !showEffortSlider}
					title="Effort"
					aria-label="Effort"
				>
					<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
						<circle cx="12" cy="12" r="3"/>
						<path d="M12 1v4M12 19v4M4.22 4.22l2.83 2.83M16.95 16.95l2.83 2.83M1 12h4M19 12h4M4.22 19.78l2.83-2.83M16.95 7.05l2.83-2.83"/>
					</svg>
					{#if effortValue}
						<span class="effort-badge">{effortValue}</span>
					{/if}
				</button>

				{#if effortValue}
					<span class="effort-label">{effortValue}</span>
				{/if}

				<button class="send-btn" onclick={handleSend} disabled={!messageText.trim() && ($attachments?.length ?? 0) === 0} title="Send message">
					<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
						<line x1="22" y1="2" x2="11" y2="13"/>
						<polygon points="22 2 15 22 11 13 2 9 22 2"/>
					</svg>
				</button>
			{/if}
		</div>
	</div>
</div>

<!-- Effort slider panel -->
{#if showEffortSlider}
	<div class="effort-panel">
		<span class="effort-label">Effort</span>
		<div class="effort-options">
			{#each ['low', 'medium', 'high', 'max'] as level}
				<button class="effort-btn" class:active={effortValue === level} onclick={() => { effortValue = level; effortLevel.set(level); }}>
					{level}
				</button>
			{/each}
		</div>
	</div>
{/if}

<style>
	/* ===== Tab slot ===== */
	.slot-stack {
		display: flex;
		flex-direction: column;
		gap: 6px;
		margin-bottom: 4px;
	}

	.slot-card {
		display: flex;
		flex-direction: column;
		gap: 6px;
		padding: 10px 14px;
		border-radius: 10px;
		border: 1px solid var(--border-subtle);
		background: var(--surface-2);
		text-align: left;
		width: 100%;
		font-family: inherit;
		font-size: inherit;
		cursor: default;
	}

	.approval-card {
		border-left: 3px solid var(--accent);
	}

	.question-card {
		border-left: 3px solid #f59e0b;
	}

	.followup-card {
		cursor: pointer;
		transition: background 0.15s;
		align-items: center;
		flex-direction: row;
		gap: 8px;
	}

	.followup-card:hover {
		background: var(--surface-3);
	}

	.followup-text {
		flex: 1;
		font-size: 13px;
		color: var(--text-secondary);
	}

	.followup-arrow {
		color: var(--text-tertiary);
		font-size: 14px;
	}

	.slot-card-text {
		font-size: 13px;
		font-weight: 500;
		color: var(--text-primary);
		margin: 0;
		line-height: 1.4;
	}

	.slot-card-actions {
		display: flex;
		gap: 6px;
		flex-wrap: wrap;
	}

	.slot-action-btn {
		padding: 4px 12px;
		border-radius: 6px;
		border: 1px solid var(--border-subtle);
		background: var(--surface-1);
		color: var(--text-secondary);
		font-size: 12px;
		font-weight: 500;
		cursor: pointer;
		transition: all 0.15s;
		font-family: inherit;
	}

	.slot-action-btn:hover {
		background: var(--surface-3);
		color: var(--text-primary);
	}

	.slot-action-btn.approve {
		background: rgba(52, 199, 89, 0.1);
		color: #34c759;
		border-color: rgba(52, 199, 89, 0.25);
	}

	.slot-action-btn.approve:hover {
		background: rgba(52, 199, 89, 0.2);
	}

	.slot-action-btn.reject {
		background: rgba(255, 69, 58, 0.08);
		color: #ff453a;
		border-color: rgba(255, 69, 58, 0.2);
	}

	.slot-action-btn.reject:hover {
		background: rgba(255, 69, 58, 0.15);
	}

	/* ===== Composer pill ===== */
	.composer-pill {
		position: relative;
		background: var(--surface-2);
		border: 1px solid var(--border-subtle);
		border-radius: 22px;
		padding: 8px 12px 8px 14px;
		margin: 0 16px 12px;
		max-width: 800px;
		transition: border-color 0.2s;
	}

	.composer-pill:focus-within {
		border-color: var(--accent);
	}

	.composer-pill.is-running {
		border-color: color-mix(in srgb, var(--accent) 30%, transparent);
	}

	.composer-main {
		display: flex;
		align-items: flex-end;
		gap: 6px;
	}

	.composer-text-wrap {
		flex: 1;
		min-width: 0;
		position: relative;
		display: flex;
		flex-direction: column;
		gap: 4px;
	}

	.attachment-chips {
		display: flex;
		flex-wrap: wrap;
		gap: 4px;
	}

	.att-chip {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		padding: 2px 6px 2px 8px;
		border-radius: 12px;
		background: var(--surface-3);
		border: 1px solid var(--border-subtle);
		font-size: 11px;
		color: var(--text-secondary);
		max-width: 160px;
	}

	.att-chip-name {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.att-chip-remove {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 14px;
		height: 14px;
		border: none;
		background: transparent;
		color: var(--text-tertiary);
		cursor: pointer;
		border-radius: 50%;
		padding: 0;
		flex-shrink: 0;
	}

	.att-chip-remove:hover {
		background: var(--surface-4);
		color: var(--text-primary);
	}

	.attachment-notice {
		font-size: 11px;
		color: var(--warning);
		padding: 2px 4px;
	}

	.composer-textarea {
		width: 100%;
		min-height: 22px;
		max-height: 120px;
		resize: none;
		border: none;
		outline: none;
		background: transparent;
		color: var(--text-primary);
		font-family: inherit;
		font-size: 14px;
		line-height: 1.5;
		padding: 0;
		overflow-y: auto;
	}

	.composer-textarea::placeholder {
		color: var(--text-tertiary);
	}

	.file-input {
		display: none;
	}

	/* Suggestions */
	.suggestions-popover {
		position: absolute;
		bottom: 100%;
		left: 0;
		margin-bottom: 6px;
		min-width: 280px;
		max-width: 360px;
		background: var(--surface-0);
		border: 1px solid var(--border-subtle);
		border-radius: 10px;
		box-shadow: 0 8px 32px rgba(0,0,0,0.2);
		z-index: 50;
		overflow: hidden;
	}

	.suggestion-item {
		display: flex;
		align-items: center;
		gap: 8px;
		width: 100%;
		padding: 7px 12px;
		border: none;
		background: transparent;
		color: var(--text-primary);
		font-family: inherit;
		font-size: 13px;
		cursor: pointer;
		text-align: left;
		transition: background 0.1s;
	}

	.suggestion-item:hover,
	.suggestion-item.selected {
		background: var(--surface-2);
	}

	.suggestion-symbol {
		width: 18px;
		height: 18px;
		display: flex;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
		color: var(--text-tertiary);
	}

	.suggestion-title {
		font-weight: 500;
		flex-shrink: 0;
	}

	.suggestion-detail {
		flex: 1;
		font-size: 11px;
		color: var(--text-tertiary);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	/* Controls */
	.composer-controls {
		display: flex;
		align-items: center;
		gap: 3px;
		flex-shrink: 0;
	}

	.ctrl-btn {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 28px;
		height: 28px;
		border: none;
		background: transparent;
		color: var(--text-tertiary);
		border-radius: 8px;
		cursor: pointer;
		transition: all 0.15s;
		position: relative;
		flex-shrink: 0;
	}

	.ctrl-btn:hover {
		background: var(--surface-3);
		color: var(--text-primary);
	}

	.ctrl-btn.active {
		background: var(--surface-3);
		color: var(--accent);
	}

	.stop-btn {
		color: #ff453a;
	}

	.stop-btn:hover {
		background: rgba(255, 69, 58, 0.1);
	}

	.effort-badge {
		font-size: 9px;
		font-weight: 600;
		color: var(--accent);
		margin-left: 1px;
		text-transform: uppercase;
	}

	.effort-label {
		font-size: 10px;
		color: var(--text-tertiary);
		margin-right: 2px;
	}

	.send-btn {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 28px;
		height: 28px;
		border: none;
		background: var(--accent-1);
		color: white;
		border-radius: 8px;
		cursor: pointer;
		transition: all 0.15s;
		flex-shrink: 0;
	}

	.send-btn:hover:not(:disabled) {
		background: var(--accent-2);
		transform: scale(1.05);
	}

	.send-btn:disabled {
		opacity: 0.35;
		cursor: not-allowed;
	}

	/* Effort panel */
	.effort-panel {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 6px 16px 8px;
		max-width: 800px;
		margin: 0 auto;
	}

	.effort-options {
		display: flex;
		gap: 4px;
	}

	.effort-btn {
		padding: 3px 12px;
		border-radius: 12px;
		border: 1px solid var(--border-subtle);
		background: var(--surface-1);
		color: var(--text-secondary);
		font-size: 11px;
		font-weight: 500;
		cursor: pointer;
		transition: all 0.15s;
		font-family: inherit;
	}

	.effort-btn:hover {
		background: var(--surface-3);
		color: var(--text-primary);
	}

	.effort-btn.active {
		background: var(--accent-1);
		color: white;
		border-color: var(--accent-1);
	}

	/* Running dots */
	.composer-dots {
		position: absolute;
		bottom: 0;
		left: 16px;
		right: 16px;
		height: 4px;
		display: flex;
		gap: 3px;
		overflow: hidden;
		border-radius: 0 0 22px 22px;
		pointer-events: none;
		z-index: 1;
	}

	.c-dot {
		width: 8px;
		height: 4px;
		border-radius: 2px;
		background: var(--accent);
		animation: composerDot 1.4s ease-in-out infinite;
		opacity: 0.3;
	}

	.c-dot:nth-child(2) { animation-delay: 0.2s; }
	.c-dot:nth-child(3) { animation-delay: 0.4s; }
	.c-dot:nth-child(4) { animation-delay: 0.6s; }

	@keyframes composerDot {
		0%, 80%, 100% { opacity: 0.2; transform: scaleX(0.6); }
		40% { opacity: 1; transform: scaleX(1); }
	}

	/* Focus mode */
	:global(body.focus-mode) .app-shell > :not(.main-area),
	:global(body.focus-mode) .sidebar {
		opacity: 0.08;
		pointer-events: none;
	}

	:global(body.focus-mode) .composer-pill {
		max-width: 800px;
		margin-left: auto;
		margin-right: auto;
		box-shadow: 0 0 0 1px var(--border-subtle);
	}
</style>
