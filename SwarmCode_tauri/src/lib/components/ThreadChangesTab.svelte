<script lang="ts">
	// ---------------------------------------------------------------------------
	// ThreadChangesTab – files changed during thread, shown as a small tab.
	// Matches ThreadChangesTab.swift: "+N -M" pill that opens the diff popover.
	// ---------------------------------------------------------------------------

	export interface ChangeStats {
		files: number;
		additions: number;
		deletions: number;
	}

	interface Props {
		stats: ChangeStats;
		onClick: () => void;
	}

	let { stats, onClick }: Props = $props();

	const filesLabel = $derived(stats.files === 1 ? '1 file' : `${stats.files} files`);
</script>

<button
	type="button"
	class="changes-tab"
	onclick={onClick}
	title="Show this thread's changes"
	aria-label="{filesLabel} changed, {stats.additions} added, {stats.deletions} removed"
>
	<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
		<path d="M7 10l3-3 3 3 6-6"/>
		<path d="M7 14l3 3 3-3 6 6"/>
		<line x1="3" y1="3" x2="21" y2="21" stroke-width="1.5"/>
	</svg>
	<span class="ct-files">{filesLabel}</span>
	<span class="ct-add">+{stats.additions}</span>
	<span class="ct-del">−{stats.deletions}</span>
</button>

<style>
	.changes-tab {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		padding: 4px 11px;
		height: 30px;
		border: 1px solid var(--border-color-1, #2a2a30);
		background: var(--surface-2, #1f1f24);
		color: var(--text-primary, #eee);
		font: 500 11px/1.2 var(--font-mono, 'SF Mono', Menlo, monospace);
		font-variant-numeric: tabular-nums;
		border-radius: 8px;
		cursor: pointer;
		transition: all 120ms ease;
		white-space: nowrap;
	}

	.changes-tab:hover {
		background: var(--surface-3, #25252b);
		border-color: var(--border-color-2, #3a3a44);
	}

	.ct-files {
		color: var(--text-primary, #eee);
		opacity: 0.9;
	}

	.ct-add {
		color: var(--success, #10b981);
		font-weight: 600;
	}

	.ct-del {
		color: var(--danger, #ef4444);
		font-weight: 600;
	}
</style>
