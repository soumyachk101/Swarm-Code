<script lang="ts">
	// ---------------------------------------------------------------------------
	// ChromeRow – the glass toolbar at the top of the conversation pane.
	// Matches ChatChromeRow.swift: new thread, hydra, branch, title, zoom,
	// open-in-menu, terminal, and changes buttons.
	// ---------------------------------------------------------------------------

	import { createEventDispatcher } from 'svelte';
	import type { ChatThread, Provider } from '$lib/types';

	interface Props {
		thread: ChatThread;
		projectName: string | null;
		directory: string;
		isRepository: boolean;
		branches: string[];
		hydraEnabled: boolean;
		isGenerating: boolean;
	}

	let {
		thread,
		projectName,
		directory,
		isRepository,
		branches = [],
		hydraEnabled,
		isGenerating
	}: Props = $props();

	const dispatch = createEventDispatcher<{
		newThread: void;
		toggleTerminal: void;
		toggleChanges: void;
		rename: void;
	}>();

	let showBranchMenu = $state(false);
	let showThreadMenu = $state(false);
	let showOpenMenu = $state(false);
</script>

<div class="chrome-row" role="toolbar" aria-label="Chat chrome">
	<div class="chrome-inner">
		{#if projectName === null}
			<button
				class="chrome-btn chrome-icon-btn"
				onclick={() => dispatch('newThread')}
				title="New thread"
				aria-label="New thread"
			>
				<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
					<path d="M12 5v14M5 12h14"/>
				</svg>
			</button>
		{/if}

		{#if thread && hydraEnabled && !thread.is_helper}
			<button
				class="chrome-btn chrome-icon-btn hydra-btn"
				title="Hydra panel"
				aria-label="Hydra"
			>
				<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
					<circle cx="12" cy="5" r="2"/>
					<circle cx="5" cy="19" r="2"/>
					<circle cx="19" cy="19" r="2"/>
					<line x1="12" y1="7" x2="5" y2="17"/>
					<line x1="12" y1="7" x2="19" y2="17"/>
				</svg>
			</button>
		{/if}

		{#if isGenerating}
			<span class="gen-indicator" aria-label="Generating">
				<span class="gen-dot"></span>
				<span class="gen-dot"></span>
				<span class="gen-dot"></span>
			</span>
		{/if}

		<div class="chrome-title-area">
			<button
				class="chrome-title-btn"
				onclick={() => dispatch('rename')}
				title="Click to copy or rename"
			>
				{thread.title || 'New thread'}
			</button>
		</div>

		<div class="chrome-right">
			{#if isRepository}
				<div class="chrome-pill-group">
					{#if branches.length > 0}
						<button
							class="chrome-pill branch-pill"
							onclick={() => showBranchMenu = !showBranchMenu}
						>
							<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
								<path d="M6 3v12"/>
								<circle cx="18" cy="6" r="3"/>
								<circle cx="6" cy="18" r="3"/>
								<path d="M18 9a9 9 0 0 1-9 9"/>
							</svg>
							<span>{branches[0] || 'main'}</span>
						</button>
					{/if}
				</div>
			{/if}

			<div class="chrome-pill-group">
				<button
					class="chrome-icon-btn"
					onclick={() => dispatch('toggleTerminal')}
					title="Terminal"
					aria-label="Toggle terminal"
				>
					<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
						<rect x="2" y="3" width="20" height="14" rx="2" ry="2"/>
						<line x1="8" y1="21" x2="16" y2="21"/>
						<line x1="12" y1="17" x2="12" y2="21"/>
					</svg>
				</button>

				<button
					class="chrome-icon-btn"
					onclick={() => dispatch('toggleChanges')}
					title="Changes"
					aria-label="Toggle changes"
				>
					<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
						<path d="M12 20h9"/>
						<path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4z"/>
					</svg>
				</button>
			</div>
		</div>
	</div>
</div>

<style>
	.chrome-row {
		position: sticky;
		top: 0;
		z-index: 10;
		background: color-mix(in srgb, var(--surface-0) 80%, transparent);
		backdrop-filter: blur(20px) saturate(1.4);
		-webkit-backdrop-filter: blur(20px) saturate(1.4);
		border-bottom: 1px solid var(--border-subtle);
	}

	.chrome-inner {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 8px 14px;
		height: 42px;
	}

	.chrome-btn {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		background: transparent;
		border: none;
		color: var(--text-secondary);
		cursor: pointer;
		border-radius: 6px;
		transition: background 0.15s, color 0.15s;
		width: 30px;
		height: 30px;
		flex-shrink: 0;
	}

	.chrome-btn:hover {
		background: var(--surface-2);
		color: var(--text-primary);
	}

	.chrome-icon-btn {
		padding: 0;
	}

	.gen-indicator {
		display: inline-flex;
		gap: 3px;
		padding: 0 4px;
	}

	.gen-dot {
		width: 5px;
		height: 5px;
		border-radius: 50%;
		background: var(--accent);
		animation: genPulse 1.2s ease-in-out infinite;
	}

	.gen-dot:nth-child(2) { animation-delay: 0.2s; }
	.gen-dot:nth-child(3) { animation-delay: 0.4s; }

	@keyframes genPulse {
		0%, 80%, 100% { opacity: 0.3; transform: scale(0.85); }
		40% { opacity: 1; transform: scale(1); }
	}

	.chrome-title-area {
		flex: 1;
		min-width: 0;
		display: flex;
		align-items: center;
		justify-content: center;
	}

	.chrome-title-btn {
		font-size: 13px;
		font-weight: 600;
		color: var(--text-primary);
		background: transparent;
		border: none;
		cursor: pointer;
		padding: 4px 10px;
		border-radius: 4px;
		transition: background 0.15s;
		max-width: 100%;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.chrome-title-btn:hover {
		background: var(--surface-2);
	}

	.chrome-right {
		display: flex;
		align-items: center;
		gap: 4px;
	}

	.chrome-pill-group {
		display: flex;
		align-items: center;
		gap: 4px;
	}

	.chrome-pill {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		padding: 3px 10px;
		border-radius: 12px;
		border: 1px solid var(--border-subtle);
		background: var(--surface-1);
		color: var(--text-secondary);
		font-size: 11px;
		font-weight: 500;
		cursor: pointer;
		transition: background 0.15s, color 0.15s;
	}

	.chrome-pill:hover {
		background: var(--surface-2);
		color: var(--text-primary);
	}

	.branch-pill svg {
		flex-shrink: 0;
	}
</style>
