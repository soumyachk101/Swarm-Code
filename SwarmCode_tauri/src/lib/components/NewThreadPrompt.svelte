<script lang="ts">
	// ---------------------------------------------------------------------------
	// NewThreadPrompt – quick prompt templates for new threads
	// Matches NewThreadPrompt.swift: shows recent prompts, categorized templates,
	// and a search field.
	// ---------------------------------------------------------------------------

	import type { ChatThread } from '$lib/types';

	// ---------------------------------------------------------------------------
	// Props
	// ---------------------------------------------------------------------------

	interface Props {
		recentThreads: ChatThread[];
		onSelect: (prompt: string) => void;
		readonly?: boolean;
	}

	let { recentThreads = [], onSelect, readonly = false }: Props = $props();

	// ---------------------------------------------------------------------------
	// State
	// ---------------------------------------------------------------------------

	let search = $state('');
	let activeCategory = $state<string>('all');
	let recentFilter = $state<'all' | 'today' | 'week' | 'month'>('all');

	// ---------------------------------------------------------------------------
	// Prompt templates
	// ---------------------------------------------------------------------------

	const templateCategories = [
		{
			id: 'all',
			label: 'All',
		},
		{
			id: 'code',
			label: 'Code',
			prompts: [
				'Review the code in the current file',
				'Refactor for readability',
				'Add error handling',
				'Write unit tests for the main module',
				'Optimize the algorithm',
				'Fix the bug in the latest commit',
			],
		},
		{
			id: 'docs',
			label: 'Docs',
			prompts: [
				'Write a README for this project',
				'Add docstrings to the main functions',
				'Generate API documentation',
				'Write a changelog entry',
			],
		},
		{
			id: 'plan',
			label: 'Plan',
			prompts: [
				'Plan a feature for user authentication',
				'Design the database schema',
				'Outline the project structure',
				'Create a migration strategy',
			],
		},
		{
			id: 'debug',
			label: 'Debug',
			prompts: [
				'Find and fix the source of this error',
				'Trace the data flow',
				'Check for memory leaks',
				'Investigate the crash logs',
			],
		},
	];

	// ---------------------------------------------------------------------------
	// Derived
	// ---------------------------------------------------------------------------

	let allTemplates = $derived(
		templateCategories
			.filter((c) => c.id !== 'all')
			.flatMap((c) => c.prompts.map((p) => ({ category: c.id, text: p })))
	);

	let filteredTemplates = $derived(() => {
		const s = search.toLowerCase().trim();
		let list = allTemplates;
		if (activeCategory !== 'all') {
			list = list.filter((t) => t.category === activeCategory);
		}
		if (s) {
			list = list.filter((t) => t.text.toLowerCase().includes(s));
		}
		return list;
	});

	let filteredThreads = $derived(() => {
		const now = Date.now();
		const dayMs = 86400000;
		return recentThreads
			.slice()
			.reverse()
			.filter((t) => {
				const created = new Date(t.created_at).getTime();
				if (recentFilter === 'today') return now - created < dayMs;
				if (recentFilter === 'week') return now - created < 7 * dayMs;
				if (recentFilter === 'month') return now - created < 30 * dayMs;
				return true;
			});
	});

	// ---------------------------------------------------------------------------
	// Actions
	// ---------------------------------------------------------------------------

	function selectPrompt(text: string) {
		if (readonly) return;
		onSelect(text);
	}

	function selectRecentThread(thread: ChatThread) {
		if (readonly) return;
		const title = thread.title || thread.id;
		onSelect(title);
	}

	function setCategory(id: string) {
		activeCategory = id;
	}

	function setRecentFilter(id: string) {
		recentFilter = id as typeof recentFilter;
	}
</script>

<div class="new-thread-prompt-root">
	<!-- Search -->
	<div class="search-row">
		<div class="search-field">
			<span class="search-icon">⌕</span>
			<input
				type="text"
				bind:value={search}
				placeholder="Search prompts…"
				{readonly}
				aria-label="Search prompts"
			/>
			{#if search}
				<button class="clear-btn" onclick={() => { search = ''; }} type="button" aria-label="Clear search">
					✕
				</button>
			{/if}
		</div>
	</div>

	<!-- Recent threads -->
	{#if recentThreads.length > 0}
		<section class="section">
			<header class="section-header">
				<span class="section-title">Recent</span>
				<div class="pill-row">
					{#each [{ id: 'all', label: 'All' }, { id: 'today', label: 'Today' }, { id: 'week', label: 'Week' }, { id: 'month', label: 'Month' }] as pill}
						<button
							class="pill"
							class:active={recentFilter === pill.id}
							onclick={() => setRecentFilter(pill.id)}
							type="button"
						>
							{pill.label}
						</button>
					{/each}
				</div>
			</header>
			<div class="recent-list">
				{#each filteredThreads as thread (thread.id)}
					<button
						class="recent-item"
						onclick={() => selectRecentThread(thread)}
						type="button"
						title={thread.title || thread.id}
					>
						<span class="recent-icon">💬</span>
						<span class="recent-title">{thread.title || thread.id.slice(0, 8)}</span>
						<span class="recent-date">
							{new Date(thread.created_at).toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}
						</span>
					</button>
				{/each}
			</div>
		</section>
	{/if}

	<!-- Templates -->
	<section class="section">
		<header class="section-header">
			<span class="section-title">Templates</span>
			<div class="pill-row">
				{#each templateCategories as cat}
					<button
						class="pill"
						class:active={activeCategory === cat.id}
						onclick={() => setCategory(cat.id)}
						type="button"
					>
						{cat.label}
					</button>
				{/each}
			</div>
		</header>

		<div class="template-grid">
			{#each filteredTemplates() as template, index (template.text)}
				<button
					class="template-chip"
					onclick={() => selectPrompt(template.text)}
					type="button"
					title={template.text}
				>
					{template.text}
				</button>
			{/each}
		</div>

		{#if filteredTemplates().length === 0 && search}
			<p class="no-results">No templates match "{search}"</p>
		{/if}
	</section>
</div>

<style>
	.new-thread-prompt-root {
		display: flex;
		flex-direction: column;
		gap: 16px;
		padding: 12px;
		font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', sans-serif;
	}

	.search-row {
		width: 100%;
	}

	.search-field {
		display: flex;
		align-items: center;
		gap: 8px;
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.04));
		border: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.08));
		border-radius: 10px;
		padding: 8px 10px;
		transition: border-color 140ms ease;
	}

	.search-field:focus-within {
		border-color: var(--chrome-accent, #6366f1);
	}

	.search-icon {
		font-size: 16px;
		opacity: 0.45;
		flex-shrink: 0;
	}

	.search-field input {
		flex: 1;
		border: none;
		background: transparent;
		outline: none;
		font-size: 13px;
		color: var(--chrome-primary, #111827);
		font-family: inherit;
	}

	.search-field input::placeholder {
		color: var(--chrome-secondary, #9ca3af);
	}

	.clear-btn {
		appearance: none;
		border: none;
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.08));
		color: var(--chrome-secondary, #6b7280);
		width: 18px;
		height: 18px;
		border-radius: 50%;
		cursor: pointer;
		font-size: 10px;
		display: flex;
		align-items: center;
		justify-content: center;
		transition: background 120ms;
		padding: 0;
	}

	.clear-btn:hover {
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.15));
	}

	.section {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}

	.section-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 8px;
		flex-wrap: wrap;
	}

	.section-title {
		font-size: 11px;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--chrome-secondary, #6b7280);
	}

	.pill-row {
		display: flex;
		gap: 4px;
	}

	.pill {
		appearance: none;
		border: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.08));
		background: transparent;
		color: var(--chrome-secondary, #6b7280);
		font-size: 11px;
		font-weight: 500;
		padding: 3px 9px;
		border-radius: 12px;
		cursor: pointer;
		transition: all 140ms ease;
		font-family: inherit;
	}

	.pill:hover {
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.04));
		color: var(--chrome-primary, #111827);
	}

	.pill.active {
		background: var(--chrome-accent, #6366f1);
		color: #ffffff;
		border-color: var(--chrome-accent, #6366f1);
	}

	.recent-list {
		display: flex;
		flex-direction: column;
		gap: 2px;
		max-height: 200px;
		overflow-y: auto;
	}

	.recent-item {
		appearance: none;
		border: none;
		background: transparent;
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 7px 10px;
		border-radius: 6px;
		cursor: pointer;
		text-align: left;
		font-family: inherit;
		color: var(--chrome-primary, #111827);
		transition: background 120ms ease;
	}

	.recent-item:hover {
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.04));
	}

	.recent-icon {
		font-size: 14px;
		opacity: 0.7;
	}

	.recent-title {
		font-size: 12px;
		flex: 1;
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.recent-date {
		font-size: 10px;
		color: var(--chrome-secondary, #6b7280);
		flex-shrink: 0;
	}

	.template-grid {
		display: flex;
		flex-wrap: wrap;
		gap: 6px;
	}

	.template-chip {
		appearance: none;
		border: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.1));
		background: var(--chrome-surface, transparent);
		color: var(--chrome-primary, #111827);
		font-size: 12px;
		padding: 6px 12px;
		border-radius: 8px;
		cursor: pointer;
		transition: all 140ms ease;
		font-family: inherit;
		text-align: left;
		line-height: 1.4;
	}

	.template-chip:hover {
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.05));
		border-color: var(--chrome-accent, #6366f1);
		color: var(--chrome-accent, #6366f1);
	}

	.template-chip:active {
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.08));
	}

	.no-results {
		font-size: 12px;
		color: var(--chrome-secondary, #6b7280);
		font-style: italic;
		padding: 4px 0;
	}

	@media (max-width: 480px) {
		.section-header {
			flex-direction: column;
			align-items: flex-start;
		}
	}
</style>
