<script lang="ts">
	import { onMount, onDestroy } from 'svelte';

	interface Props {
		open: boolean;
		onClose: () => void;
		onSelect: (id: string) => void;
		items: CommandItem[];
	}

	interface CommandItem {
		id: string;
		label: string;
		icon?: string;
		category?: string;
		keywords?: string[];
		action?: () => void;
	}

	let { open = false, onClose, onSelect, items = [] }: Props = $props();

	let inputEl: HTMLInputElement | null = null;
	let query = $state('');
	let selectedIndex = $state(0);

	let filtered = $derived(() => {
		const q = query.toLowerCase().trim();
		if (!q) return items;
		return items.filter(item => {
			const labelMatch = item.label.toLowerCase().includes(q);
			const keywordMatch = item.keywords?.some(k => k.toLowerCase().includes(q));
			const catMatch = item.category?.toLowerCase().includes(q);
			return labelMatch || keywordMatch || catMatch;
		});
	});

	let grouped: { category?: string; items: typeof items }[] = $derived(() => {
		const result: { category?: string; items: typeof items }[] = [];
		const groups = new Map<string | undefined, typeof items>();

		for (const item of filtered()) {
			const cat = item.category ?? '';
			if (!groups.has(cat)) {
				groups.set(cat, []);
			}
			groups.get(cat)!.push(item);
		}

		for (const [cat, catItems] of groups) {
			result.push({ category: cat || undefined, items: catItems });
		}

		return result;
	});

	let flatItems = $derived(filtered().slice(0, 20));

	$effect(() => {
		selectedIndex = 0;
	});

	$effect(() => {
		if (open) {
			query = '';
			selectedIndex = 0;
			onMount(() => inputEl?.focus());
		}
	});

	function handleKeyDown(e: KeyboardEvent) {
		if (e.key === 'ArrowDown') {
			e.preventDefault();
			selectedIndex = Math.min(selectedIndex + 1, flatItems.length - 1);
		} else if (e.key === 'ArrowUp') {
			e.preventDefault();
			selectedIndex = Math.max(selectedIndex - 1, 0);
		} else if (e.key === 'Enter') {
			e.preventDefault();
			if (flatItems[selectedIndex]) {
				handleSelect(flatItems[selectedIndex]);
			}
		} else if (e.key === 'Escape') {
			onClose();
		}
	}

	function handleSelect(item: typeof items[0]) {
		if (item.action) item.action();
		onSelect(item.id);
		onClose();
	}

	let commands: CommandItem[] = [
		{ id: 'new-thread', label: 'New Thread', icon: 'plus', category: 'Threads', keywords: ['create', 'new'] },
		{ id: 'switch-project', label: 'Switch Project', icon: 'folder', category: 'Threads', keywords: ['project', 'switch'] },
		{ id: 'archive-threads', label: 'Archive Old Threads', icon: 'archive', category: 'Threads', keywords: ['clean', 'archive'] },
		{ id: 'settings', label: 'Open Settings', icon: 'settings', category: 'Navigation', keywords: ['preferences', 'config'] },
		{ id: 'toggle-sidebar', label: 'Toggle Sidebar', icon: 'sidebar', category: 'Navigation', keywords: ['hide', 'show'] },
		{ id: 'focus-mode', label: 'Toggle Focus Mode', icon: 'focus', category: 'View', keywords: ['distraction', 'full'] },
		{ id: 'new-hydra', label: 'Launch Hydra Swarm', icon: 'hydra', category: 'Actions', keywords: ['swarm', 'parallel', 'multi'] },
		{ id: 'attach-file', label: 'Attach File', icon: 'attach', category: 'Actions', keywords: ['upload', 'file'] },
		{ id: 'terminal', label: 'Open Terminal', icon: 'terminal', category: 'Navigation', keywords: ['shell', 'bash', 'cli'] },
		{ id: 'git-diff', label: 'View Git Diff', icon: 'diff', category: 'Git', keywords: ['changes', 'diff'] },
		{ id: 'git-commit', label: 'Git Commit', icon: 'git', category: 'Git', keywords: ['commit', 'save'] },
		{ id: 'about', label: 'About SwarmAI', icon: 'info', category: 'Navigation', keywords: ['version', 'info'] },
	];

	let iconMap: Record<string, string> = {
		plus: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 5v14M5 12h14"/></svg>',
		folder: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>',
		archive: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="3" width="20" height="5" rx="1"/><path d="M4 8v11a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8"/><path d="M10 12h4"/></svg>',
		settings: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3"/><path d="M12 1v6m0 6v6m4.22-10.22l4.24-4.24M6.34 17.66l-4.24 4.24M23 12h-6m-6 0H1m20.07-4.93l-4.24 4.24M6.34 6.34L2.1 2.1"/></svg>',
		sidebar: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M9 3v18"/></svg>',
		focus: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M8 3H5a2 2 0 0 0-2 2v3m18 0V5a2 2 0 0 0-2-2h-3m0 18h3a2 2 0 0 0 2-2v-3M3 16v3a2 2 0 0 0 2 2h3"/></svg>',
		hydra: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 2l2 4 4 1-3 3 1 4-4-2-4 2 1-4-3-3 4-1z"/></svg>',
		attach: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21.44 11.05l-9.19 9.19a6 6 0 0 1-8.49-8.49l9.19-9.19a4 4 0 0 1 5.66 5.66l-9.2 9.19a2 2 0 0 1-2.83-2.83l8.49-8.48"/></svg>',
		terminal: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>',
		diff: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14,2 14,8 20,8"/><path d="M7 15v4M11 15v2M15 11v4"/></svg>',
		git: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="18" cy="18" r="3"/><circle cx="6" cy="6" r="3"/><path d="M6 21V9a9 9 0 0 0 9 9"/></svg>',
		info: '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/></svg>',
	};

	$effect(() => {
		items = commands;
	});
</script>

{#if open}
	<div class="palette-overlay" onclick={onClose}>
		<div class="palette-dialog" onclick={(e) => e.stopPropagation()}>
			<div class="palette-search">
				<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="search-icon">
					<circle cx="11" cy="11" r="8"/>
					<path d="m21 21-4.35-4.35"/>
				</svg>
				<input
					bind:this={inputEl}
					bind:value={query}
					onkeydown={handleKeyDown}
					placeholder="Type a command…"
					class="palette-input"
				/>
				<kbd class="esc-hint">ESC</kbd>
			</div>

			<div class="palette-results">
				{#each grouped() as group}
					{#if group.category}
						<div class="result-group-label">{group.category}</div>
					{/if}
					{#each group.items as item, idx (item.id)}
						{@const globalIdx = flatItems.indexOf(item)}
						<button
							class="result-item"
							class:selected={globalIdx === selectedIndex}
							onclick={() => handleSelect(item)}
							onmouseenter={() => selectedIndex = globalIdx}
						>
							{#if item.icon && iconMap[item.icon]}
								<span class="item-icon">{@html iconMap[item.icon] ?? ''}</span>
							{/if}
							<span class="item-label">{item.label}</span>
						</button>
					{/each}
				{/each}

				{#if filtered().length === 0}
					<div class="no-results">
						<p>No commands found for "{query}"</p>
					</div>
				{/if}
			</div>

			<div class="palette-footer">
				<span class="footer-hint"><kbd>↑↓</kbd> Navigate</span>
				<span class="footer-hint"><kbd>↵</kbd> Select</span>
				<span class="footer-hint"><kbd>esc</kbd> Close</span>
			</div>
		</div>
	</div>
{/if}

<style>
	.palette-overlay {
		position: fixed;
		inset: 0;
		background: rgba(0, 0, 0, 0.5);
		backdrop-filter: blur(4px);
		display: flex;
		align-items: flex-start;
		justify-content: center;
		padding-top: 20vh;
		z-index: 1000;
		animation: fade-in 0.15s ease-out;
	}

	@keyframes fade-in {
		from { opacity: 0; }
		to { opacity: 1; }
	}

	.palette-dialog {
		width: 520px;
		max-height: 420px;
		background: var(--surface-2);
		border: var(--border-1) var(--border-color-1);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-xl);
		display: flex;
		flex-direction: column;
		overflow: hidden;
		animation: scale-in 0.15s ease-out;
	}

	@keyframes scale-in {
		from { transform: scale(0.96); opacity: 0; }
		to { transform: scale(1); opacity: 1; }
	}

	.palette-search {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		padding: var(--space-3) var(--space-4);
		border-bottom: var(--border-1) var(--border-color-1);
	}

	.search-icon {
		color: var(--text-tertiary);
		flex-shrink: 0;
	}

	.palette-input {
		flex: 1;
		border: none;
		background: none;
		font-size: var(--font-size-md);
		color: var(--text-primary);
		outline: none;
		font-family: var(--font-system);
	}

	.palette-input::placeholder {
		color: var(--text-tertiary);
	}

	.esc-hint {
		font-size: 11px;
		padding: 2px 6px;
		border: var(--border-1) var(--border-color-1);
		border-radius: var(--radius-sm);
		color: var(--text-tertiary);
		font-family: var(--font-mono);
	}

	.palette-results {
		flex: 1;
		overflow-y: auto;
		padding: var(--space-2) 0;
	}

	.result-group-label {
		padding: var(--space-2) var(--space-4);
		font-size: 10px;
		font-weight: 600;
		color: var(--text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.5px;
	}

	.result-item {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		width: 100%;
		padding: var(--space-2) var(--space-4);
		border: none;
		background: none;
		color: var(--text-primary);
		font-size: var(--font-size-sm);
		cursor: pointer;
		transition: background var(--transition-fast);
		text-align: left;
	}

	.result-item:hover,
	.result-item.selected {
		background: var(--accent-3);
	}

	.item-icon {
		width: 20px;
		height: 20px;
		display: flex;
		align-items: center;
		justify-content: center;
		color: var(--text-tertiary);
		flex-shrink: 0;
	}

	.item-label {
		flex: 1;
	}

	.no-results {
		padding: var(--space-8) var(--space-4);
		text-align: center;
		color: var(--text-tertiary);
	}

	.no-results p {
		font-size: var(--font-size-sm);
	}

	.palette-footer {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: var(--space-4);
		padding: var(--space-2) var(--space-4);
		border-top: var(--border-1) var(--border-color-2);
	}

	.footer-hint {
		display: flex;
		align-items: center;
		gap: var(--space-1);
		font-size: 11px;
		color: var(--text-tertiary);
	}

	kbd {
		font-size: 10px;
		padding: 1px 5px;
		border: var(--border-1) var(--border-color-1);
		border-radius: var(--radius-sm);
		font-family: var(--font-mono);
		background: var(--surface-3);
		color: var(--text-secondary);
	}
</style>
