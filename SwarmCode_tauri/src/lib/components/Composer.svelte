<script lang="ts">
	import { onMount, tick } from 'svelte';
	import { sendMessage, sendFollowUp, approveRequest, answerQuestion } from '$lib/api/commands';
	import { appStore } from '$lib/stores/appStore';
	import {
		isGenerating,
		stopGeneration,
		effortLevel,
		hydraEnabled,
		hydraHeadCount,
		attachments,
		addAttachment,
		removeAttachment,
		clearAttachments,
		followUps,
		pendingApprovals,
		pendingQuestions
	} from '$lib/stores/chatStore';
	import type { ChatThread } from '$lib/types';

	interface Props {
		thread: ChatThread | null;
		disabled?: boolean;
	}

	let { thread = null, disabled = false }: Props = $props();

	let textarea = $state<HTMLTextAreaElement | null>(null);
	let messageText = $state('');
	let effortValue = $state<string | null>(null);
	let showEffortSlider = $state(false);
	let isSubmitting = $state(false);
	let isFocusMode = $state(false);

	$effect(() => {
		effortValue = thread?.effort ?? $effortLevel;
	});

	function handleKeyDown(e: KeyboardEvent) {
		if (e.key === 'Enter' && (e.metaKey || e.ctrlKey) && !e.shiftKey) {
			e.preventDefault();
			handleSubmit();
		}
	}

	function adjustHeight() {
		if (textarea) {
			textarea.style.height = 'auto';
			const maxH = 160;
			textarea.style.height = Math.min(textarea.scrollHeight, maxH) + 'px';
		}
	}

	$effect(() => {
		if (messageText) adjustHeight();
	});

	async function handleSubmit() {
		if (!thread || !messageText.trim() || isSubmitting) return;

		const text = messageText.trim();
		isSubmitting = true;
		messageText = '';
		if (textarea) {
			textarea.style.height = 'auto';
		}

		try {
			await sendMessage(thread.id, {
				text,
				attachments: $attachments.map(a => ({ path: a.path, name: a.name })),
				effort: effortValue,
				hydra_enabled: $hydraEnabled,
				hydra_heads: $hydraHeadCount,
			});
			clearAttachments();
		} catch (e) {
			console.error('Failed to send message:', e);
		} finally {
			isSubmitting = false;
		}
	}

	function handleAttach() {
		const input = document.createElement('input');
		input.type = 'file';
		input.multiple = true;
		input.onchange = () => {
			const files = input.files;
			if (!files) return;
			for (const file of files) {
				const id = crypto.randomUUID();
				const reader = new FileReader();
				reader.onload = () => {
					addAttachment({ id, name: file.name, path: file.name, size: file.size });
				};
				reader.readAsDataURL(file);
			}
		};
		input.click();
	}

	function handleFollowUp(fuId: string) {
		if (!thread) return;
		sendFollowUp(thread.id, fuId);
	}

	function handleApprove(requestId: string, role: string) {
		if (!thread) return;
		approveRequest(thread.id, requestId, role);
	}

	function handleAnswer(questionId: string, choices: string[]) {
		if (!thread) return;
		answerQuestion(thread.id, questionId, choices);
	}

	// Helpers for showing data from store
	type ApproxApproval = { id: string; text: string; options: string[] };
	type ApproxQuestion = { id: string; text: string; choices: string[] };
	type ApproxFollowUp = { id: string; text: string };

	let showFollowUps = $derived(($followUps?.length ?? 0) > 0);
	let showApprovals = $derived(($pendingApprovals?.length ?? 0) > 0);
	let showQuestions = $derived(($pendingQuestions?.length ?? 0) > 0);

	let approvalItems = $derived<ApproxApproval[]>(
		($pendingApprovals ?? []).map((a: any) => ({
			id: a.id,
			text: a.headline || a.text || a.message || 'Approval needed',
			options: Array.isArray(a.options) && a.options.length
				? a.options.map((o: any) => (typeof o === 'string' ? o : o.title ?? o.role ?? 'Approve'))
				: ['Approve', 'Reject']
		}))
	);

	let questionItems = $derived<ApproxQuestion[]>(
		($pendingQuestions ?? []).map((q: any) => ({
			id: q.id,
			text: q.headline || q.text || q.message || 'Question',
			choices: Array.isArray(q.choices) && q.choices.length
				? q.choices.map((c: any) => (typeof c === 'string' ? c : c.title ?? c.label ?? ''))
				: Array.isArray(q.options) && q.options.length
					? q.options.map((o: any) => (typeof o === 'string' ? o : o.title ?? o.label ?? ''))
					: []
		}))
	);

	let followUpItems = $derived<ApproxFollowUp[]>(
		($followUps ?? []).map((f: any) => ({ id: f.id, text: f.text || f.title || '' }))
	);

	function getPlaceholder(): string {
		if (!thread) return 'Select a thread to start chatting…';
		if ($hydraEnabled) {
			if (thread.provider) {
				return `Ask ${thread.provider} for anything; big jobs go out to a team of heads`;
			}
			return 'Ask the assistant for anything…';
		}
		if (thread.provider) {
			return `Ask ${thread.provider} to build, fix or explain. @ for files, / for commands`;
		}
		return 'Type a message… (⌘+Enter to send)';
	}
</script>

<div class="composer-area" class:focus-mode={isFocusMode} class:disabled class:generating={$isGenerating}>
	<!-- ========================================================
	     Slot: cards stacked ABOVE the pill (follow-ups, approvals, questions)
	     ======================================================== -->
	{#if showApprovals}
		<div class="slot-stack">
			{#each approvalItems as appr (appr.id)}
				<div class="slot-card approval-card">
					<p class="slot-card-text">{appr.text}</p>
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

	{#if showFollowUps}
		<div class="slot-stack">
			{#each followUpItems as fu (fu.id)}
				<button
					class="slot-card followup-card"
					onclick={() => handleFollowUp(fu.id)}
				>
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

	{#if showQuestions}
		<div class="slot-stack">
			{#each questionItems as q (q.id)}
				<div class="slot-card question-card">
					<p class="slot-card-text">{q.text}</p>
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

	<!-- ========================================================
	     Effort slider panel (collapsible inside the pill)
	     ======================================================== -->
	{#if showEffortSlider}
		<div class="effort-panel">
			<span class="effort-label">Effort</span>
			<div class="effort-options">
				{#each ['minimal', 'low', 'medium', 'high', 'xhigh'] as level}
					<button
						class="effort-btn"
						class:active={effortValue === level}
						onclick={() => { effortValue = level; effortLevel.set(level); }}
					>
						{level}
					</button>
				{/each}
			</div>
		</div>
	{/if}

	<!-- ========================================================
	     Glass Pill Composer
	     ======================================================== -->
	<div class="composer-pill" class:is-running={$isGenerating}>
		<!-- Working dots: accent dots flow along the pill's bottom edge -->
		{#if $isGenerating}
			<div class="working-dots">
				<span class="dot"></span>
				<span class="dot"></span>
				<span class="dot"></span>
				<span class="dot"></span>
				<span class="dot"></span>
				<span class="dot"></span>
			</div>
		{/if}

		<!-- Attachment chips (inside pill, above textarea) -->
		{#if $attachments.length > 0}
			<div class="attachments-strip">
				{#each $attachments as att (att.id)}
					<div class="attachment-chip">
						<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
							<path d="M13 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/>
							<polyline points="13 2 13 9 20 9"/>
						</svg>
						<span class="attachment-name">{att.name}</span>
						<button class="attachment-remove" onclick={() => removeAttachment(att.id)}>
							<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
								<path d="M18 6L6 18M6 6l12 12"/>
							</svg>
						</button>
					</div>
				{/each}
			</div>
		{/if}

		<!-- Pill body: textarea + controls (bottom-aligned) -->
		<div class="pill-row">
			<textarea
				bind:this={textarea}
				bind:value={messageText}
				onkeydown={handleKeyDown}
				placeholder={getPlaceholder()}
				{disabled}
				rows={1}
				class="pill-textarea"
			></textarea>

			<div class="pill-controls">
				<button
					class="control-btn"
					class:toggled={showEffortSlider}
					onclick={() => showEffortSlider = !showEffortSlider}
					title="Effort level"
					type="button"
				>
					<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
						<path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z"/>
					</svg>
				</button>

				<button
					class="control-btn"
					class:toggled={$hydraEnabled}
					onclick={() => { hydraEnabled.update((v: boolean) => !v); }}
					title={`Hydra (${$hydraHeadCount} heads)`}
					type="button"
				>
					<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
						<path d="M12 2l2 4 4 1-3 3 1 4-4-2-4 2 1-4-3-3 4-1z"/>
					</svg>
				</button>

				<div class="control-divider"></div>

				<button
					class="control-btn attach-btn"
					onclick={handleAttach}
					title="Attach file"
					type="button"
				>
					<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
						<path d="M21.44 11.05l-9.19 9.19a6 6 0 0 1-8.49-8.49l9.19-9.19a4 4 0 0 1 5.66 5.66l-9.2 9.19a2 2 0 0 1-2.83-2.83l8.49-8.48"/>
					</svg>
				</button>

				{#if $isGenerating}
					<button
						class="send-btn stop-btn-pill"
						onclick={() => stopGeneration()}
						disabled={disabled}
						type="button"
						title="Stop generating"
					>
						<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor">
							<rect x="6" y="6" width="12" height="12" rx="2"/>
						</svg>
					</button>
				{:else}
					<button
						class="send-btn"
						class:active={messageText.trim().length > 0}
						onclick={handleSubmit}
						disabled={!thread || !messageText.trim() || isSubmitting || disabled}
						type="button"
						title="Send (⌘+Enter)"
					>
						<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
							<path d="M22 2L11 13"/>
							<path d="M22 2l-7 20-4-9-9-4 20-7z"/>
						</svg>
					</button>
				{/if}
			</div>
		</div>
	</div>
</div>

<style>
	/* ============================================================
	   Composer Area — bottom section of the chat view
	   ============================================================ */
	.composer-area {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		padding: var(--space-4) var(--space-5) var(--space-5);
		border-top: var(--border-1) var(--border-color-1);
		background: var(--surface-1);
		flex-shrink: 0;
		position: relative;
	}

	.composer-area.disabled {
		opacity: 0.5;
		pointer-events: none;
	}

	/* ============================================================
	   Slot Stack — cards stacked above the pill
	   ============================================================ */
	.slot-stack {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		max-height: 180px;
		overflow-y: auto;
		animation: slot-pop 0.18s ease;
	}

	.slot-card {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		padding: 9px 14px;
		font-family: var(--font-system);
		font-size: var(--font-size-sm);
		animation: slot-pop 0.18s ease;
	}

	.followup-card {
		flex-direction: row;
		align-items: center;
		gap: var(--space-2);
		border: var(--border-1) var(--border-color-1);
		background: var(--surface-2);
		border-radius: var(--radius-lg);
		color: var(--text-primary);
		cursor: pointer;
		transition: all var(--transition-fast);
		text-align: left;
		padding: 8px 14px;
	}

	.followup-card:hover {
		background: var(--surface-3);
		border-color: var(--accent-1);
		color: var(--accent-1);
	}

	.followup-card svg {
		color: var(--accent-1);
		flex-shrink: 0;
	}

	.followup-text {
		flex: 1;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.followup-arrow {
		color: var(--text-tertiary);
		font-size: 14px;
		line-height: 1;
	}

	.approval-card {
		background: rgba(255, 149, 0, 0.06);
		border: var(--border-1) rgba(255, 149, 0, 0.18);
		border-radius: var(--radius-lg);
	}

	.question-card {
		background: var(--surface-3);
		border-radius: var(--radius-lg);
	}

	.slot-card-text {
		font-size: var(--font-size-sm);
		color: var(--text-primary);
		margin: 0;
		line-height: 1.4;
	}

	.slot-card-actions {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-2);
	}

	.slot-action-btn {
		padding: 5px 14px;
		border: var(--border-1) var(--border-color-1);
		background: var(--surface-1);
		border-radius: var(--radius-full);
		font-size: var(--font-size-xs);
		font-weight: 500;
		color: var(--text-primary);
		cursor: pointer;
		transition: all var(--transition-fast);
		font-family: var(--font-system);
	}

	.slot-action-btn:hover {
		background: var(--accent-1);
		color: var(--text-inverse);
		border-color: var(--accent-1);
	}

	.slot-action-btn.approve:hover {
		background: rgba(52, 199, 89, 0.15);
		border-color: var(--success);
		color: var(--success);
	}

	.slot-action-btn.reject:hover {
		background: rgba(255, 59, 48, 0.12);
		border-color: var(--danger);
		color: var(--danger);
	}

	/* ============================================================
	   Glass Pill Composer
	   ============================================================ */
	.composer-pill {
		display: flex;
		flex-direction: column;
		position: relative;
		border-radius: 22px;
		background: var(--surface-2);
		backdrop-filter: blur(20px) saturate(1.8);
		-webkit-backdrop-filter: blur(20px) saturate(1.8);
		border: var(--border-1) var(--border-color-2);
		box-shadow:
			var(--shadow-sm),
			inset 0 1px 0 rgba(255, 255, 255, 0.4);
		overflow: hidden;
		transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
	}

	:global([data-theme="dark"]) .composer-pill,
	:root[data-theme="dark"] .composer-pill {
		background: rgba(44, 44, 46, 0.7);
		box-shadow:
			var(--shadow-md),
			inset 0 1px 0 rgba(255, 255, 255, 0.06);
	}

	@media (prefers-color-scheme: dark) {
		:root[data-theme="system"] .composer-pill {
			background: rgba(44, 44, 46, 0.7);
			box-shadow:
				var(--shadow-md),
				inset 0 1px 0 rgba(255, 255, 255, 0.06);
		}
	}

	.composer-pill:focus-within {
		border-color: var(--accent-1);
		box-shadow:
			var(--shadow-md),
			0 0 0 3px var(--accent-3),
			inset 0 1px 0 rgba(255, 255, 255, 0.4);
	}

	/* ============================================================
	   Working Dots — animated accents flowing along pill's bottom edge
	   ============================================================ */
	.working-dots {
		position: absolute;
		bottom: 0;
		left: 0;
		right: 0;
		height: 18px;
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 4px;
		padding: 0 24px;
		pointer-events: none;
		z-index: 1;
		overflow: hidden;
		mask-image: linear-gradient(to right, transparent, black 12%, black 88%, transparent);
		-webkit-mask-image: linear-gradient(to right, transparent, black 12%, black 88%, transparent);
	}

	.working-dots .dot {
		width: 4px;
		height: 4px;
		border-radius: 50%;
		background: var(--accent-1);
		opacity: 0;
		animation: dot-flow 1.6s ease-in-out infinite;
	}

	.working-dots .dot:nth-child(1) { animation-delay: 0s; }
	.working-dots .dot:nth-child(2) { animation-delay: 0.18s; }
	.working-dots .dot:nth-child(3) { animation-delay: 0.36s; }
	.working-dots .dot:nth-child(4) { animation-delay: 0.54s; }
	.working-dots .dot:nth-child(5) { animation-delay: 0.72s; }
	.working-dots .dot:nth-child(6) { animation-delay: 0.9s; }

	@keyframes dot-flow {
		0% {
			opacity: 0;
			transform: translateX(-14px) scale(0.5);
		}
		20% {
			opacity: 0.9;
		}
		70% {
			opacity: 0.9;
		}
		100% {
			opacity: 0;
			transform: translateX(14px) scale(0.5);
		}
	}

	/* ============================================================
	   Attachment Chips — inside pill, above textarea
	   ============================================================ */
	.attachments-strip {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-2);
		padding: 10px 14px 0;
		position: relative;
		z-index: 2;
	}

	.attachment-chip {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		padding: 3px 8px 3px 8px;
		background: var(--surface-3);
		border-radius: var(--radius-full);
		font-size: var(--font-size-xs);
		color: var(--text-secondary);
		max-width: 160px;
	}

	.attachment-name {
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.attachment-remove {
		display: flex;
		align-items: center;
		justify-content: center;
		border: none;
		background: none;
		color: var(--text-tertiary);
		cursor: pointer;
		padding: 1px;
		border-radius: 50%;
		flex-shrink: 0;
	}

	.attachment-remove:hover {
		color: var(--danger);
		background: var(--surface-4);
	}

	/* ============================================================
	   Pill Row — textarea + trailing controls
	   ============================================================ */
	.pill-row {
		display: flex;
		align-items: flex-end;
		gap: var(--space-1);
		padding: 7px 8px 7px 14px;
		position: relative;
		z-index: 2;
	}

	.pill-textarea {
		flex: 1;
		resize: none;
		border: none;
		background: transparent;
		padding: 6px 0;
		font-family: var(--font-system);
		font-size: var(--font-size-md);
		line-height: var(--line-height-normal);
		color: var(--text-primary);
		outline: none;
		min-height: 26px;
		max-height: 160px;
	}

	.pill-textarea::placeholder {
		color: var(--text-tertiary);
	}

	.pill-controls {
		display: flex;
		align-items: flex-end;
		gap: 1px;
		flex-shrink: 0;
		padding-bottom: 3px;
	}

	.control-btn {
		width: 28px;
		height: 28px;
		border: none;
		background: transparent;
		border-radius: var(--radius-md);
		color: var(--text-tertiary);
		cursor: pointer;
		display: flex;
		align-items: center;
		justify-content: center;
		transition: all var(--transition-fast);
		flex-shrink: 0;
	}

	.control-btn:hover {
		background: var(--surface-3);
		color: var(--text-primary);
	}

	.control-btn.toggled {
		background: var(--accent-3);
		color: var(--accent-1);
	}

	.control-divider {
		width: 1px;
		height: 18px;
		background: var(--border-color-2);
		margin: 0 4px;
		flex-shrink: 0;
	}

	.send-btn {
		width: 30px;
		height: 30px;
		border: none;
		background: var(--surface-3);
		border-radius: 50%;
		color: var(--text-tertiary);
		cursor: pointer;
		display: flex;
		align-items: center;
		justify-content: center;
		transition: all var(--transition-fast);
		flex-shrink: 0;
	}

	.send-btn.active {
		background: var(--accent-1);
		color: var(--text-inverse);
	}

	.send-btn:disabled {
		opacity: 0.4;
		cursor: not-allowed;
	}

	.send-btn:hover:not(:disabled) {
		transform: scale(1.05);
	}

	.stop-btn-pill {
		background: var(--accent-1);
		color: var(--text-inverse);
	}

	.stop-btn-pill:hover {
		background: var(--accent-2);
		transform: scale(1.05);
	}

	/* ============================================================
	   Effort Slider Panel
	   ============================================================ */
	.effort-panel {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		padding: var(--space-3) var(--space-4);
		background: var(--surface-2);
		border: var(--border-1) var(--border-color-2);
		border-radius: var(--radius-lg);
		animation: slot-pop 0.15s ease;
	}

	.effort-label {
		font-size: var(--font-size-xs);
		font-weight: 500;
		color: var(--text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.3px;
	}

	.effort-options {
		display: flex;
		gap: 3px;
		flex: 1;
	}

	.effort-btn {
		flex: 1;
		padding: 4px 8px;
		border: var(--border-1) var(--border-color-1);
		background: var(--surface-1);
		border-radius: var(--radius-sm);
		font-size: var(--font-size-xs);
		color: var(--text-secondary);
		cursor: pointer;
		transition: all var(--transition-fast);
		font-weight: 500;
		font-family: var(--font-system);
	}

	.effort-btn:hover {
		background: var(--surface-3);
	}

	.effort-btn.active {
		background: var(--accent-1);
		color: var(--text-inverse);
		border-color: var(--accent-1);
	}

	/* ============================================================
	   Animations
	   ============================================================ */
	@keyframes slot-pop {
		from { opacity: 0; transform: translateY(6px); }
		to { opacity: 1; transform: translateY(0); }
	}

	/* ============================================================
	   Composer scrollbar (slot cards)
	   ============================================================ */
	.slot-stack::-webkit-scrollbar {
		width: 4px;
	}

	.slot-stack::-webkit-scrollbar-track {
		background: transparent;
	}

	.slot-stack::-webkit-scrollbar-thumb {
		background: var(--surface-4);
		border-radius: var(--radius-full);
	}

	.composer-area.focus-mode .composer-pill {
		border-color: var(--accent-1);
	}

	@media (prefers-reduced-motion: reduce) {
		.working-dots .dot {
			animation: none;
			opacity: 0.4;
		}
		.slot-card,
		.slot-stack,
		.effort-panel {
			animation: none;
		}
	}
</style>
