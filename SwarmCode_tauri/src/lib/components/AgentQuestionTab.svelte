<script lang="ts">
	// ---------------------------------------------------------------------------
	// AgentQuestionTab – the agent's questions rising as a tab above the composer.
	// Uses the project's QuestionRequest / Question / QuestionChoice types.
	// ---------------------------------------------------------------------------

	import type { QuestionRequest, Question, QuestionChoice } from '$lib/types';

	interface Props {
		request: QuestionRequest;
		onSkip: () => void;
		onSubmit: (answers: Record<string, string[]>) => void;
	}

	let { request, onSkip, onSubmit }: Props = $props();

	// ---------------------------------------------------------------------------
	// State
	// ---------------------------------------------------------------------------

	/// Selected choices keyed by question id
	let selections = $state<Record<string, string[]>>({});
	/// Free-form "other" text keyed by question id
	let written = $state<Record<string, string>>({});

	function toggleChoice(q: Question, label: string) {
		const current = selections[q.id] ?? [];
		const multi = q.allows_multiple ?? false;
		const next = multi
			? (current.includes(label) ? current.filter(l => l !== label) : [...current, label])
			: (current[0] === label ? [] : [label]);
		selections = { ...selections, [q.id]: next };
	}

	let answers = $derived.by(() => {
		const result: Record<string, string[]> = {};
		for (const q of request.questions) {
			const chosen = selections[q.id] ?? [];
			const freeText = (written[q.id] ?? '').trim();
			result[q.id] = freeText ? [...chosen, freeText] : chosen;
		}
		return result;
	});

	let isAnswered = (q: AgentQuestion) => (answers[q.id] ?? []).length > 0;

	let unansweredCount = $derived(request.questions.filter(q => !isAnswered(q)).length);
	let isComplete = $derived(unansweredCount === 0);

	let countLabel = $derived(request.questions.length === 1
		? '1 question'
		: `${request.questions.length} questions`);
</script>

<div class="agent-question-tab" role="region" aria-label="Agent questions">
	<header class="aq-header">
		<span class="aq-icon" aria-hidden="true">
			<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
				<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
				<path d="M9 9h.01M9 13h6"/>
			</svg>
		</span>
		<span class="aq-count">{countLabel}</span>
		<span class="aq-suffix">to answer</span>
	</header>

	<div class="aq-divider"></div>

	<div class="aq-scroll">
		{#each request.questions as question (question.id)}
			{@const multi = question.allows_multiple ?? false}
			<div class="aq-question">
				{#if question.header}
					<div class="aq-question-header">{question.header}</div>
				{/if}
				<div class="aq-prompt-row">
					<p class="aq-prompt">{question.prompt}</p>
					{#if !isAnswered(question)}
						<span class="aq-waiting-dot" title="Not answered yet" aria-label="Not answered yet"></span>
					{/if}
				</div>

				{#each question.choices as choice (choice.label)}
					{@const selected = (selections[question.id] ?? []).includes(choice.label)}
					<button
						type="button"
						class="aq-choice"
						class:selected
						onclick={() => toggleChoice(question, choice.label)}
					>
						<span class="aq-choice-icon">
							{#if multi}
								{#if selected}
									<svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor"><rect x="3" y="3" width="18" height="18" rx="3"/></svg>
								{:else}
									<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="3"/></svg>
								{/if}
							{:else if selected}
								<svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="12" r="6"/></svg>
							{:else}
								<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/></svg>
							{/if}
						</span>
						<span class="aq-choice-body">
							<span class="aq-choice-label">{choice.label}</span>
							{#if choice.detail}
								<span class="aq-choice-detail">{choice.detail}</span>
							{/if}
						</span>
					</button>
				{/each}

				{#if question.allows_other || question.choices.length === 0}
					{#if question.is_secret}
						<input
							class="aq-input"
							type="password"
							placeholder="Your answer"
							value={written[question.id] ?? ''}
							oninput={(e) => { written = { ...written, [question.id]: (e.target as HTMLInputElement).value }; }}
							onkeydown={(e) => { if (e.key === 'Enter' && isComplete) { onSubmit(answers); } }}
						/>
					{:else}
						<input
							class="aq-input"
							type="text"
							placeholder={question.choices.length === 0 ? 'Your answer' : 'Something else'}
							value={written[question.id] ?? ''}
							oninput={(e) => { written = { ...written, [question.id]: (e.target as HTMLInputElement).value }; }}
							onkeydown={(e) => { if (e.key === 'Enter' && isComplete) { onSubmit(answers); } }}
						/>
					{/if}
				{/if}
			</div>
		{/each}
	</div>

	<div class="aq-divider"></div>

	<footer class="aq-footer">
		{#if unansweredCount > 0}
			<span class="aq-waiting">
				{unansweredCount === 1 ? '1 question still to answer' : `${unansweredCount} questions still to answer`}
			</span>
		{:else}
			<span></span>
		{/if}
		<button type="button" class="aq-btn aq-btn-secondary" onclick={onSkip}>
			Skip these questions
		</button>
		<button
			type="button"
			class="aq-btn aq-btn-primary"
			disabled={!isComplete}
			title={isComplete
				? 'Sends your answers'
				: (request.questions.length === 1 ? 'Answer the question to send' : `Answer all ${request.questions.length} questions to send`)}
			onclick={() => onSubmit(answers)}
		>
			Send answer
		</button>
	</footer>
</div>

<style>
	.agent-question-tab {
		display: flex;
		flex-direction: column;
		background: var(--surface-2, #1f1f24);
		border: 1px solid var(--border-color-1, #2a2a30);
		border-radius: 12px;
		max-width: 560px;
		margin: 0 auto 6px;
		overflow: hidden;
		animation: aq-pop 0.18s ease;
	}

	@keyframes aq-pop {
		from { opacity: 0; transform: translateY(-6px); }
		to   { opacity: 1; transform: translateY(0); }
	}

	.aq-header {
		display: flex;
		align-items: center;
		gap: 7px;
		padding: 7px 12px;
		font-size: 12px;
		font-weight: 500;
		font-variant-numeric: tabular-nums;
		height: 22px;
	}

	.aq-icon {
		color: var(--text-tertiary, #999);
		display: inline-flex;
		align-items: center;
	}

	.aq-count {
		color: var(--text-primary, #eee);
		opacity: 0.9;
	}

	.aq-suffix {
		color: var(--text-tertiary, #999);
	}

	.aq-divider {
		height: 1px;
		background: var(--border-color-2, #2a2a30);
		opacity: 0.5;
	}

	.aq-scroll {
		max-height: 320px;
		overflow-y: auto;
		padding: 8px 12px 8px;
		display: flex;
		flex-direction: column;
		gap: 14px;
	}

	.aq-question {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}

	.aq-question-header {
		font-size: 11px;
		font-weight: 500;
		color: var(--text-tertiary, #999);
	}

	.aq-prompt-row {
		display: flex;
		align-items: flex-start;
		gap: 6px;
	}

	.aq-prompt {
		font-size: 13px;
		font-weight: 500;
		color: var(--text-primary, #eee);
		opacity: 0.92;
		margin: 0;
		flex: 1;
		user-select: text;
	}

	.aq-waiting-dot {
		flex-shrink: 0;
		width: 5px;
		height: 5px;
		border-radius: 50%;
		background: var(--warning, #f5a623);
		margin-top: 6px;
	}

	.aq-choice {
		appearance: none;
		display: flex;
		align-items: flex-start;
		gap: 8px;
		padding: 6px 8px;
		background: var(--surface-3, #25252b);
		border: none;
		border-radius: 8px;
		color: var(--text-primary, #eee);
		text-align: left;
		font: inherit;
		cursor: pointer;
		transition: background 120ms ease;
	}

	.aq-choice:hover {
		background: var(--surface-4, #2c2c34);
	}

	.aq-choice.selected {
		background: rgba(99, 102, 241, 0.14);
	}

	.aq-choice-icon {
		flex-shrink: 0;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 14px;
		height: 14px;
		color: var(--text-tertiary, #999);
		margin-top: 1px;
	}

	.aq-choice.selected .aq-choice-icon {
		color: var(--accent-1, #6366f1);
	}

	.aq-choice-body {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}

	.aq-choice-label {
		font-size: 12px;
		color: var(--text-primary, #eee);
		opacity: 0.9;
	}

	.aq-choice-detail {
		font-size: 11px;
		color: var(--text-tertiary, #999);
		line-height: 1.4;
	}

	.aq-input {
		appearance: none;
		width: 100%;
		padding: 6px 10px;
		background: var(--surface-3, #25252b);
		border: 1px solid var(--border-color-1, #2a2a30);
		border-radius: 6px;
		color: var(--text-primary, #eee);
		font: inherit;
		font-size: 12px;
		outline: none;
		transition: border-color 120ms ease;
	}

	.aq-input:focus {
		border-color: var(--accent-1, #6366f1);
	}

	.aq-footer {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 8px 12px 10px;
	}

	.aq-waiting {
		flex: 1;
		font-size: 11px;
		color: var(--text-tertiary, #999);
	}

	.aq-btn {
		appearance: none;
		border: 1px solid var(--border-color-1, #2a2a30);
		background: var(--surface-3, #25252b);
		color: var(--text-primary, #eee);
		font: inherit;
		font-size: 12px;
		font-weight: 500;
		padding: 4px 10px;
		border-radius: 6px;
		cursor: pointer;
		transition: all 120ms ease;
	}

	.aq-btn:hover:not(:disabled) {
		background: var(--surface-4, #2c2c34);
	}

	.aq-btn:disabled {
		opacity: 0.4;
		cursor: not-allowed;
	}

	.aq-btn-primary {
		background: var(--accent-1, #6366f1);
		border-color: var(--accent-1, #6366f1);
		color: #fff;
	}

	.aq-btn-primary:hover:not(:disabled) {
		background: var(--accent-2, #5158d8);
		border-color: var(--accent-2, #5158d8);
	}

	@media (prefers-reduced-motion: reduce) {
		.agent-question-tab { animation: none; }
		.aq-choice { transition: none; }
	}
</style>
