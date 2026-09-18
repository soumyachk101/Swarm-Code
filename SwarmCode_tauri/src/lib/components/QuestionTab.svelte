<script lang="ts">
	// ---------------------------------------------------------------------------
	// QuestionTab – suggested follow-up questions
	// Matches QuestionTab.swift: clickable suggestion chips with regenerate.
	// ---------------------------------------------------------------------------

	// ---------------------------------------------------------------------------
	// Props
	// ---------------------------------------------------------------------------

	interface SuggestedQuestion {
		id: string;
		text: string;
		context: string;
		category: string;
	}

	interface Props {
		questions: SuggestedQuestion[];
		readonly?: boolean;
		onRegenerate: () => void;
		onSend: (question: string) => void;
	}

	let { questions = [], readonly = false, onRegenerate, onSend }: Props = $props();

	// ---------------------------------------------------------------------------
	// State
	// ---------------------------------------------------------------------------

	let isRegenerating = $state(false);

	function sendQuestion(text: string) {
		if (readonly) return;
		onSend(text);
	}

	async function regenerate() {
		if (readonly || isRegenerating) return;
		isRegenerating = true;
		try {
			onRegenerate();
		} finally {
			// reset after a short visual delay
			setTimeout(() => {
				isRegenerating = false;
			}, 800);
		}
	}
</script>

<div class="question-tab-root">
	<header class="header">
		<span class="title">Suggested Follow-ups</span>
		{#if !readonly}
			<button
				class="regenerate-btn"
				class:spinning={isRegenerating}
				onclick={regenerate}
				disabled={isRegenerating}
				type="button"
				title="Regenerate suggestions"
			>
				<span class="regen-icon" class:spin={isRegenerating}>↻</span>
				{#if isRegenerating}
					<span class="regen-label">Regenerating…</span>
				{:else}
					<span class="regen-label">Regenerate</span>
				{/if}
			</button>
		{/if}
	</header>

	{#if questions.length === 0}
		<div class="empty">
			<span class="empty-icon">💡</span>
			<p class="empty-text">
				{isRegenerating ? 'Generating suggestions…' : 'No suggestions yet. Send a message and suggestions will appear here.'}
			</p>
		</div>
	{:else}
		<div class="question-list" role="list">
			{#each questions as question (question.id)}
				<button
					class="question-card"
					onclick={() => sendQuestion(question.text)}
					disabled={readonly}
					type="button"
					role="listitem"
				>
					<div class="card-inner">
						<span class="question-category">{question.category}</span>
						<p class="question-text">{question.text}</p>
						<div class="card-footer">
							<span class="question-context">Related to: {question.context}</span>
							<span class="send-hint">Click to send →</span>
						</div>
					</div>
				</button>
			{/each}
		</div>
	{/if}
</div>

<style>
	.question-tab-root {
		display: flex;
		flex-direction: column;
		gap: 12px;
		padding: 12px;
		font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', sans-serif;
	}

	.header {
		display: flex;
		align-items: center;
		justify-content: space-between;
	}

	.title {
		font-size: 13px;
		font-weight: 600;
		color: var(--chrome-primary, #111827);
	}

	.regenerate-btn {
		appearance: none;
		border: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.08));
		background: transparent;
		color: var(--chrome-secondary, #6b7280);
		font-size: 11px;
		font-weight: 500;
		padding: 5px 10px;
		border-radius: 8px;
		cursor: pointer;
		display: inline-flex;
		align-items: center;
		gap: 5px;
		transition: all 140ms ease;
		font-family: inherit;
	}

	.regenerate-btn:hover:not(:disabled) {
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.04));
		color: var(--chrome-primary, #111827);
	}

	.regenerate-btn:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}

	.regen-icon {
		display: inline-flex;
		transition: transform 400ms ease;
	}

	.regen-icon.spin {
		animation: spinOnce 500ms ease;
	}

	@keyframes spinOnce {
		from { transform: rotate(0deg); }
		to { transform: rotate(360deg); }
	}

	.regen-label {
		white-space: nowrap;
	}

	.question-list {
		display: flex;
		flex-direction: column;
		gap: 8px;
		max-height: 400px;
		overflow-y: auto;
	}

	.question-card {
		appearance: none;
		border: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.08));
		background: var(--chrome-surface, transparent);
		border-radius: 10px;
		cursor: pointer;
		text-align: left;
		font-family: inherit;
		transition: all 160ms ease;
		overflow: hidden;
	}

	.question-card:hover:not(:disabled) {
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.03));
		border-color: var(--chrome-accent, #6366f1);
		transform: translateX(2px);
	}

	.question-card:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}

	.card-inner {
		padding: 12px 14px;
		display: flex;
		flex-direction: column;
		gap: 4px;
	}

	.question-category {
		font-size: 10px;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--chrome-accent, #6366f1);
		background: #6366f112;
		padding: 2px 7px;
		border-radius: 4px;
		align-self: flex-start;
	}

	.question-text {
		font-size: 13px;
		line-height: 1.5;
		color: var(--chrome-primary, #111827);
		margin: 0;
		font-weight: 500;
	}

	.card-footer {
		display: flex;
		align-items: center;
		justify-content: space-between;
		margin-top: 4px;
	}

	.question-context {
		font-size: 10px;
		color: var(--chrome-secondary, #9ca3af);
	}

	.send-hint {
		font-size: 10px;
		color: var(--chrome-accent, #6366f1);
		opacity: 0;
		transition: opacity 140ms;
	}

	.question-card:hover:not(:disabled) .send-hint {
		opacity: 1;
	}

	.empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 8px;
		padding: 32px 16px;
		color: var(--chrome-secondary, #6b7280);
	}

	.empty-icon {
		font-size: 28px;
		opacity: 0.6;
	}

	.empty-text {
		font-size: 12px;
		text-align: center;
		margin: 0;
		max-width: 280px;
		line-height: 1.5;
	}

	@media (prefers-reduced-motion: reduce) {
		.question-card,
		.question-card:hover {
			transition: none;
			transform: none;
		}
		.regen-icon.spin {
			animation: none;
		}
	}
</style>
