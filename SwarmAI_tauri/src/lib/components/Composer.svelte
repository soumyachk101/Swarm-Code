<script lang="ts">
	import { onMount, tick } from 'svelte';
	import { sendMessage, sendFollowUp, approveRequest, answerQuestion } from '$lib/api/commands';
	import { appStore } from '$lib/stores/appStore';
	import { isGenerating, stopGeneration, effortLevel, hydraEnabled, hydraHeadCount, attachments, addAttachment, removeAttachment, clearAttachments } from '$lib/stores/chatStore';
	import type { ChatThread } from '$lib/types';

	interface Props {
		thread: ChatThread | null;
		disabled?: boolean;
	}

	let { thread = null, disabled = false }: Props = $props();

	let textarea = $state<HTMLTextAreaElement | null>(null);
	let messageText = $state('');
	let activeTab = $state<'message' | 'followups' | 'approvals' | 'questions'>('message');
	let effortValue = $state<string | null>(null);
	let showEffortSlider = $state(false);
	let isSubmitting = $state(false);
	let isFocusMode = $state(false);

	let followUps = $state<Array<{ id: string; text: string }>>([]);
	let approvals = $state<Array<{ id: string; text: string; options: string[] }>>([]);
	let questions = $state<Array<{ id: string; text: string; choices: string[] }>>([]);

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
			const maxH = 200;
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
			if (activeTab === 'message') {
				await sendMessage(thread.id, {
					text,
					attachments: $attachments.map(a => ({ path: a.path, name: a.name })),
					effort: effortValue,
					hydra_enabled: $hydraEnabled,
					hydra_heads: $hydraHeadCount,
				});
				clearAttachments();
			}
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
				const reader = new FileReader();
				reader.onload = () => {
					// Store as data URL for preview
				};
			}
		};
		input.click();
	}

	$effect(() => {
		if (thread) {
			followUps = thread.followUps?.map(f => ({ id: f.id || '', text: f.text })) ?? [];
			approvals = [];
			questions = [];
		}
	});
</script>

<div class="composer" class:focus-mode={isFocusMode} class:disabled>
	<!-- Tabs -->
	<div class="composer-tabs">
		<button
			class="tab-btn"
			class:active={activeTab === 'message'}
			onclick={() => activeTab = 'message'}
		>
			<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
				<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
			</svg>
			Message
		</button>
		{#if followUps.length > 0}
			<button
				class="tab-btn"
				class:active={activeTab === 'followups'}
				onclick={() => activeTab = 'followups'}
			>
				<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
					<path d="M17 1l4 4-4 4"/>
					<path d="M3 11V9a4 4 0 0 1 4-4h14"/>
					<path d="M7 23l-4-4 4-4"/>
					<path d="M21 13v2a4 4 0 0 1-4 4H3"/>
				</svg>
				Follow-ups
				<span class="tab-count">{followUps.length}</span>
			</button>
		{/if}
		{#if approvals.length > 0}
			<button
				class="tab-btn"
				class:active={activeTab === 'approvals'}
				onclick={() => activeTab = 'approvals'}
			>
				<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
					<path d="M9 11l3 3L22 4"/>
					<path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/>
				</svg>
				Approvals
				<span class="tab-count warning">{approvals.length}</span>
			</button>
		{/if}
		{#if questions.length > 0}
			<button
				class="tab-btn"
				class:active={activeTab === 'questions'}
				onclick={() => activeTab = 'questions'}
			>
				<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
					<circle cx="12" cy="12" r="10"/>
					<path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/>
					<path d="M12 17h.01"/>
				</svg>
				Questions
			</button>
		{/if}
	</div>

	<!-- Message Tab -->
	{#if activeTab === 'message'}
		<div class="composer-message">
			<!-- Attachments bar -->
			{#if $attachments.length > 0}
				<div class="attachments-bar">
					{#each $attachments as att (att.id)}
						<div class="attachment-chip">
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

			<div class="composer-input-row">
				<textarea
					bind:this={textarea}
					bind:value={messageText}
					onkeydown={handleKeyDown}
					placeholder={thread ? 'Message the assistant… (⌘+Enter to send)' : 'Select a thread to start chatting…'}
					{disabled}
					rows={1}
					class="composer-textarea"
				></textarea>

				<div class="composer-actions">
					<button
						class="action-btn"
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
						class="action-btn"
						class:toggled={$hydraEnabled}
						onclick={() => {}}
						title={`Hydra (${$hydraHeadCount} heads)`}
						type="button"
					>
						<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
							<path d="M12 2l2 4 4 1-3 3 1 4-4-2-4 2 1-4-3-3 4-1z"/>
						</svg>
					</button>

					<button
						class="action-btn"
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
							class="send-btn stop-btn"
							onclick={() => stopGeneration()}
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
							disabled={!thread || !messageText.trim() || isSubmitting}
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

			{#if showEffortSlider}
				<div class="effort-panel">
					<span class="effort-label">Effort</span>
					<div class="effort-options">
						{#each ['minimal', 'low', 'medium', 'high', 'xhigh'] as level}
							<button
								class="effort-btn"
								class:active={effortValue === level}
								onclick={() => { effortValue = level; }}
							>
								{level}
							</button>
						{/each}
					</div>
				</div>
			{/if}
		</div>
	{/if}

	<!-- Follow-ups Tab -->
	{#if activeTab === 'followups'}
		<div class="composer-panel">
			{#each followUps as fu (fu.id)}
				<button class="followup-btn" onclick={() => { sendFollowUp(thread!.id, fu.id); activeTab = 'message'; }}>
					<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
						<path d="M17 1l4 4-4 4"/>
						<path d="M3 11V9a4 4 0 0 1 4-4h14"/>
					</svg>
					{fu.text}
				</button>
			{/each}
		</div>
	{/if}

	<!-- Approvals Tab -->
	{#if activeTab === 'approvals'}
		<div class="composer-panel">
			{#each approvals as appr (appr.id)}
				<div class="approval-card">
					<p class="approval-text">{appr.text}</p>
					<div class="approval-options">
						{#each appr.options as opt}
							<button class="approval-btn" onclick={() => approveRequest(thread!.id, appr.id, opt)}>
								{opt}
							</button>
						{/each}
					</div>
				</div>
			{/each}
		</div>
	{/if}

	<!-- Questions Tab -->
	{#if activeTab === 'questions'}
		<div class="composer-panel">
			{#each questions as q (q.id)}
				<div class="question-card">
					<p class="question-text">{q.text}</p>
					<div class="question-choices">
						{#each q.choices as choice}
							<button class="choice-btn" onclick={() => answerQuestion(thread!.id, q.id, choice)}>
								{choice}
							</button>
						{/each}
					</div>
				</div>
			{/each}
		</div>
	{/if}
</div>

<style>
	.composer {
		border-top: var(--border-1) var(--border-color-1);
		background: var(--surface-2);
		flex-shrink: 0;
	}

	.composer-tabs {
		display: flex;
		border-bottom: var(--border-1) var(--border-color-2);
		padding: 0 var(--space-4);
		gap: var(--space-1);
	}

	.tab-btn {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		padding: 6px 10px;
		border: none;
		background: none;
		color: var(--text-tertiary);
		font-size: var(--font-size-xs);
		font-weight: 500;
		cursor: pointer;
		border-bottom: 2px solid transparent;
		margin-bottom: -1px;
		transition: all var(--transition-fast);
		border-radius: var(--radius-sm) var(--radius-sm) 0 0;
	}

	.tab-btn:hover {
		color: var(--text-secondary);
		background: var(--surface-3);
	}

	.tab-btn.active {
		color: var(--accent-1);
		border-bottom-color: var(--accent-1);
	}

	.tab-count {
		font-size: 10px;
		background: var(--surface-3);
		padding: 0 5px;
		border-radius: var(--radius-full);
		margin-left: 2px;
	}

	.tab-count.warning {
		background: rgba(255, 149, 0, 0.2);
		color: var(--warning);
	}

	.composer-message {
		padding: var(--space-4);
	}

	.attachments-bar {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-2);
		margin-bottom: var(--space-3);
	}

	.attachment-chip {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		padding: 3px 8px;
		background: var(--surface-3);
		border-radius: var(--radius-full);
		font-size: var(--font-size-xs);
		color: var(--text-secondary);
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
	}

	.attachment-remove:hover {
		color: var(--danger);
		background: var(--surface-4);
	}

	.composer-input-row {
		display: flex;
		align-items: flex-end;
		gap: var(--space-2);
	}

	.composer-textarea {
		flex: 1;
		resize: none;
		border: var(--border-1) var(--border-color-1);
		background: var(--surface-1);
		border-radius: var(--radius-lg);
		padding: 10px 14px;
		font-family: var(--font-system);
		font-size: var(--font-size-md);
		line-height: var(--line-height-normal);
		color: var(--text-primary);
		outline: none;
		transition: border-color var(--transition-fast), box-shadow var(--transition-fast);
		min-height: 40px;
		max-height: 200px;
	}

	.composer-textarea:focus {
		border-color: var(--accent-1);
		box-shadow: 0 0 0 3px var(--accent-3);
	}

	.composer-textarea::placeholder {
		color: var(--text-tertiary);
	}

	.composer-actions {
		display: flex;
		align-items: center;
		gap: var(--space-1);
	}

	.action-btn {
		width: 34px;
		height: 34px;
		border: none;
		background: transparent;
		border-radius: var(--radius-md);
		color: var(--text-tertiary);
		cursor: pointer;
		display: flex;
		align-items: center;
		justify-content: center;
		transition: all var(--transition-fast);
	}

	.action-btn:hover {
		background: var(--surface-3);
		color: var(--text-primary);
	}

	.action-btn.toggled {
		background: var(--accent-3);
		color: var(--accent-1);
	}

	.send-btn {
		width: 34px;
		height: 34px;
		border: none;
		background: var(--surface-3);
		border-radius: 50%;
		color: var(--text-tertiary);
		cursor: pointer;
		display: flex;
		align-items: center;
		justify-content: center;
		transition: all var(--transition-fast);
	}

	.send-btn.active {
		background: var(--accent-1);
		color: var(--text-inverse);
	}

	.send-btn:disabled {
		opacity: 0.4;
		cursor: not-allowed;
	}

	.stop-btn {
		width: 100%;
		height: 100%;
		border: none;
		background: transparent;
		color: var(--text-inverse);
		cursor: pointer;
		display: flex;
		align-items: center;
		justify-content: center;
		border-radius: 50%;
	}

	.stop-btn:hover {
		background: rgba(255, 255, 255, 0.15);
	}

	.effort-panel {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		margin-top: var(--space-3);
		padding-top: var(--space-3);
		border-top: var(--border-1) var(--border-color-2);
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
	}

	.effort-btn:hover {
		background: var(--surface-3);
	}

	.effort-btn.active {
		background: var(--accent-1);
		color: var(--text-inverse);
		border-color: var(--accent-1);
	}

	/* ---- Panel Content (followups, approvals, questions) ---- */
	.composer-panel {
		padding: var(--space-4);
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		max-height: 200px;
		overflow-y: auto;
	}

	.followup-btn {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		padding: 10px 14px;
		border: var(--border-1) var(--border-color-1);
		background: var(--surface-1);
		border-radius: var(--radius-md);
		font-size: var(--font-size-sm);
		color: var(--text-primary);
		cursor: pointer;
		transition: all var(--transition-fast);
		text-align: left;
	}

	.followup-btn:hover {
		background: var(--surface-3);
		border-color: var(--accent-1);
	}

	.approval-card {
		padding: 12px 14px;
		background: rgba(255, 149, 0, 0.06);
		border: var(--border-1) rgba(255, 149, 0, 0.15);
		border-radius: var(--radius-md);
	}

	.approval-text {
		font-size: var(--font-size-sm);
		color: var(--text-primary);
		margin-bottom: var(--space-3);
	}

	.approval-options {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-2);
	}

	.approval-btn {
		padding: 6px 14px;
		border: var(--border-1) var(--border-color-1);
		background: var(--surface-1);
		border-radius: var(--radius-full);
		font-size: var(--font-size-xs);
		font-weight: 500;
		color: var(--text-primary);
		cursor: pointer;
		transition: all var(--transition-fast);
	}

	.approval-btn:hover {
		background: var(--accent-1);
		color: var(--text-inverse);
		border-color: var(--accent-1);
	}

	.question-card {
		padding: 12px 14px;
		background: var(--surface-3);
		border-radius: var(--radius-md);
	}

	.question-text {
		font-size: var(--font-size-sm);
		font-weight: 500;
		color: var(--text-primary);
		margin-bottom: var(--space-3);
	}

	.question-choices {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}

	.choice-btn {
		padding: 8px 12px;
		border: var(--border-1) var(--border-color-1);
		background: var(--surface-1);
		border-radius: var(--radius-sm);
		font-size: var(--font-size-sm);
		color: var(--text-primary);
		cursor: pointer;
		transition: all var(--transition-fast);
		text-align: left;
	}

	.choice-btn:hover {
		background: var(--accent-3);
		border-color: var(--accent-1);
		color: var(--accent-1);
	}

	.composer.disabled {
		opacity: 0.5;
		pointer-events: none;
	}
</style>
