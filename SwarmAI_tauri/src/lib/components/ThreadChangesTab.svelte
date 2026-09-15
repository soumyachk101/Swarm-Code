<script lang="ts">
	// ---------------------------------------------------------------------------
	// ThreadChangesTab – files changed during thread
	// Matches ThreadChangesTab.swift: shows git diffs with accept/reject.
	// ---------------------------------------------------------------------------

	import { v4 as uuidv4 } from 'uuid';

	// ---------------------------------------------------------------------------
	// Types
	// ---------------------------------------------------------------------------

	export interface ChangeEntry {
		id: string;
		path: string;
		status: 'added' | 'modified' | 'deleted';
		additions: number;
		deletions: number;
		diff: string;
		baseTree?: string;
	}

	// ---------------------------------------------------------------------------
	// Props
	// ---------------------------------------------------------------------------

	interface Props {
		changes: ChangeEntry[];
		readonly?: boolean;
		onAccept: (entry: ChangeEntry) => void;
		onReject: (entry: ChangeEntry) => void;
		onAcceptAll: () => void;
		onRejectAll: () => void;
	}

	let { changes = [], readonly = false, onAccept, onReject, onAcceptAll, onRejectAll }: Props = $props();

	// ---------------------------------------------------------------------------
	// State
	// ---------------------------------------------------------------------------

	let expandedId = $state<string | null>(null);
	let filterStatus = $state<string>('all');

	// ---------------------------------------------------------------------------
	// Derived
	// ---------------------------------------------------------------------------

	let filteredChanges = $derived(() => {
		if (filterStatus === 'all') return changes;
		return changes.filter((c) => c.status === filterStatus);
	});

	let totals = $derived(() => {
		let additions = 0;
		let deletions = 0;
		let count = 0;
		for (const c of changes) {
			additions += c.additions;
			deletions += c.deletions;
			count++;
		}
		return { count, additions, deletions };
	});

	function statusLabel(status: string): string {
		const labels: Record<string, string> = {
			added: 'Added',
			modified: 'Modified',
			deleted: 'Deleted',
		};
		return labels[status] ?? status;
	}

	function statusColor(status: string): string {
		const colors: Record<string, string> = {
			added: '#10b981',
			modified: '#f59e0b',
			deleted: '#ef4444',
		};
		return colors[status] ?? '#6b7280';
	}

	function accept(entry: ChangeEntry) {
		if (readonly) return;
		onAccept(entry);
	}

	function reject(entry: ChangeEntry) {
		if (readonly) return;
		onReject(entry);
	}

	function toggleExpand(id: string) {
		expandedId = expandedId === id ? null : id;
	}

	function setFilter(status: string) {
		filterStatus = status;
	}

	// ---------------------------------------------------------------------------
	// Diff formatter (simple)
	// ---------------------------------------------------------------------------

	function formatDiff(diff: string): string[] {
		return diff.split('\n').slice(0, 200);
	}
</script>

<div class="changes-root">
	<!-- Header -->
	<header class="header">
		<div class="header-left">
			<span class="title">Changes</span>
			<span class="badge">{totals().count} files</span>
			<span class="stat stat-add">+{totals().additions}</span>
			<span class="stat stat-del">−{totals().deletions}</span>
		</div>

		<div class="header-actions">
			<button class="btn-accept-all" onclick={onAcceptAll} disabled={readonly} type="button">
				Accept All
			</button>
			<button class="btn-reject-all" onclick={onRejectAll} disabled={readonly} type="button">
				Reject All
			</button>
		</div>
	</header>

	<!-- Filter pills -->
	<div class="filter-row">
		{#each [{ id: 'all', label: 'All' }, { id: 'added', label: 'Added' }, { id: 'modified', label: 'Modified' }, { id: 'deleted', label: 'Deleted' }] as f}
			<button
				class="filter-pill"
				class:active={filterStatus === f.id}
				onclick={() => setFilter(f.id)}
				type="button"
			>
				{f.label}
			</button>
		{/each}
	</div>

	<!-- Change list -->
	<div class="change-list" role="list">
		{#if filteredChanges().length === 0}
			<div class="empty">
				<span class="empty-icon">📋</span>
				<p class="empty-text">No files were changed in this thread.</p>
			</div>
		{:else}
			{#each filteredChanges() as change (change.id)}
				{@const isExpanded = expandedId === change.id}
				<div
					class="change-card"
					class:expanded={isExpanded}
					role="listitem"
				>
					<!-- Summary row -->
					<button class="change-header" onclick={() => toggleExpand(change.id)} type="button">
						<span class="chevron" class:open={isExpanded}>▶</span>

						<span
							class="status-dot"
							style="background: {statusColor(change.status)}"
						/>

						<span class="file-path">{change.path}</span>

						<span
							class="status-tag"
							style="color: {statusColor(change.status)}; background: {statusColor(change.status)}15; border-color: {statusColor(change.status)}30;"
						>
							{statusLabel(change.status)}
						</span>

						<span class="line-stats">
							<span class="add-stat">+{change.additions}</span>
							<span class="del-stat">−{change.deletions}</span>
						</span>

						<!-- Actions -->
						{#if !readonly}
							<div class="row-actions" onclick={(e) => e.stopPropagation()}>
								<button
									class="row-btn accept"
									onclick={() => accept(change)}
									type="button"
									title="Accept this change"
								>✓</button>
								<button
									class="row-btn reject"
									onclick={() => reject(change)}
									type="button"
									title="Reject this change"
								>✕</button>
							</div>
						{/if}
					</button>

					<!-- Diff -->
					{#if isExpanded}
						<div class="diff-panel">
							{#if change.baseTree}
								<div class="diff-meta">
									<span class="base-tree-label">Base tree:</span>
									<code class="base-tree-value">{change.baseTree.slice(0, 12)}</code>
								</div>
							{/if}
							<div class="diff-scroll">
								{#each formatDiff(change.diff) as line, lineIndex}
									{@const isAdd = line.startsWith('+')}
									{@const isDel = line.startsWith('-')}
									{@const isHunk = line.startsWith('@@')}
									<div
										class="diff-line"
										class:add-line={isAdd}
										class:del-line={isDel}
										class:hunk-line={isHunk}
									>
										<span class="line-number">{lineIndex + 1}</span>
										<span class="line-prefix">
											{#if isAdd}+{:else if isDel}−{:else if isHunk}@{:else} </span>
										</span>
										<span class="line-content">{line.slice(1)}</span>
									</div>
								{/each}
							</div>
						</div>
					{/if}
				</div>
			{/each}
		{/if}
	</div>
</div>

<style>
	.changes-root {
		display: flex;
		flex-direction: column;
		gap: 10px;
		padding: 12px;
		font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', sans-serif;
	}

	.header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 8px;
		flex-wrap: wrap;
	}

	.header-left {
		display: flex;
		align-items: center;
		gap: 10px;
	}

	.title {
		font-size: 13px;
		font-weight: 600;
		color: var(--chrome-primary, #111827);
	}

	.badge {
		font-size: 11px;
		color: var(--chrome-secondary, #6b7280);
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.04));
		padding: 2px 7px;
		border-radius: 8px;
	}

	.stat {
		font-size: 11px;
		font-weight: 600;
		font-family: 'SF Mono', monospace;
	}

	.stat-add {
		color: #10b981;
	}

	.stat-del {
		color: #ef4444;
	}

	.header-actions {
		display: flex;
		gap: 6px;
	}

	.btn-accept-all,
	.btn-reject-all {
		appearance: none;
		border: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.1));
		background: transparent;
		font-size: 11px;
		font-weight: 500;
		padding: 5px 10px;
		border-radius: 7px;
		cursor: pointer;
		transition: all 140ms ease;
		font-family: inherit;
	}

	.btn-accept-all {
		color: #10b981;
	}

	.btn-reject-all {
		color: #ef4444;
	}

	.btn-accept-all:hover:not(:disabled) {
		background: #10b98112;
		border-color: #10b98140;
	}

	.btn-reject-all:hover:not(:disabled) {
		background: #ef444412;
		border-color: #ef444440;
	}

	.btn-accept-all:disabled,
	.btn-reject-all:disabled {
		opacity: 0.35;
		cursor: not-allowed;
	}

	.filter-row {
		display: flex;
		gap: 4px;
	}

	.filter-pill {
		appearance: none;
		border: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.06));
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

	.filter-pill:hover {
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.04));
	}

	.filter-pill.active {
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.08));
		color: var(--chrome-primary, #111827);
	}

	.change-list {
		display: flex;
		flex-direction: column;
		gap: 4px;
		max-height: 600px;
		overflow-y: auto;
	}

	.change-card {
		border: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.06));
		border-radius: 8px;
		background: var(--chrome-surface, transparent);
		overflow: hidden;
		transition: border-color 140ms ease;
	}

	.change-card:hover {
		border-color: var(--chrome-overlay, rgba(0, 0, 0, 0.12));
	}

	.change-card.expanded {
		border-color: var(--chrome-overlay, rgba(0, 0, 0, 0.15));
	}

	.change-header {
		appearance: none;
		border: none;
		background: transparent;
		display: flex;
		align-items: center;
		gap: 8px;
		width: 100%;
		padding: 10px 12px;
		cursor: pointer;
		text-align: left;
		font-family: inherit;
		color: var(--chrome-primary, #111827);
		font-size: 12px;
		transition: background 120ms;
	}

	.change-header:hover {
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.02));
	}

	.chevron {
		font-size: 8px;
		color: var(--chrome-secondary, #9ca3af);
		transition: transform 160ms ease;
		flex-shrink: 0;
	}

	.chevron.open {
		transform: rotate(90deg);
	}

	.status-dot {
		width: 7px;
		height: 7px;
		border-radius: 50%;
		flex-shrink: 0;
	}

	.file-path {
		font-family: 'SF Mono', 'Menlo', monospace;
		font-size: 12px;
		flex: 1;
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		font-weight: 500;
	}

	.status-tag {
		font-size: 10px;
		font-weight: 600;
		padding: 2px 7px;
		border-radius: 4px;
		text-transform: uppercase;
		letter-spacing: 0.04em;
		border: 1px solid;
		flex-shrink: 0;
	}

	.line-stats {
		display: flex;
		gap: 6px;
		font-family: 'SF Mono', monospace;
		font-size: 11px;
		flex-shrink: 0;
	}

	.add-stat {
		color: #10b981;
		font-weight: 600;
	}

	.del-stat {
		color: #ef4444;
		font-weight: 600;
	}

	.row-actions {
		display: flex;
		gap: 2px;
		flex-shrink: 0;
	}

	.row-btn {
		appearance: none;
		border: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.08));
		background: transparent;
		font-size: 11px;
		padding: 3px 7px;
		border-radius: 6px;
		cursor: pointer;
		transition: all 120ms ease;
		font-family: inherit;
		line-height: 1;
	}

	.row-btn:hover {
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.08));
	}

	.row-btn.accept {
		color: #10b981;
	}

	.row-btn.accept:hover {
		background: #10b98115;
		border-color: #10b98140;
	}

	.row-btn.reject {
		color: #ef4444;
	}

	.row-btn.reject:hover {
		background: #ef444415;
		border-color: #ef444440;
	}

	/* ── Diff panel ── */

	.diff-panel {
		border-top: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.06));
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.02));
	}

	.diff-meta {
		padding: 6px 12px;
		font-size: 10px;
		color: var(--chrome-secondary, #6b7280);
		display: flex;
		gap: 6px;
		align-items: center;
	}

	.base-tree-label {
		text-transform: uppercase;
		letter-spacing: 0.04em;
		font-weight: 600;
	}

	.base-tree-value {
		font-family: 'SF Mono', monospace;
		font-size: 10px;
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.04));
		padding: 2px 5px;
		border-radius: 3px;
	}

	.diff-scroll {
		max-height: 300px;
		overflow-y: auto;
		padding: 8px 0;
	}

	.diff-line {
		display: flex;
		font-family: 'SF Mono', 'Menlo', 'Consolas', monospace;
		font-size: 11px;
		line-height: 1.6;
		padding: 0 12px;
		min-height: 1.6em;
	}

	.diff-line.add-line {
		background: #10b9810d;
	}

	.diff-line.add-line .line-prefix {
		color: #10b981;
	}

	.diff-line.del-line {
		background: #ef44440d;
	}

	.diff-line.del-line .line-prefix {
		color: #ef4444;
	}

	.diff-line.hunk-line {
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.03));
	}

	.diff-line.hunk-line .line-prefix {
		color: #8b5cf6;
	}

	.line-number {
		color: var(--chrome-secondary, #9ca3af);
		min-width: 36px;
		text-align: right;
		padding-right: 14px;
		flex-shrink: 0;
		opacity: 0.6;
	}

	.line-prefix {
		width: 14px;
		text-align: center;
		flex-shrink: 0;
		font-weight: 600;
	}

	.line-content {
		color: var(--chrome-primary, #111827);
		white-space: pre;
	}

	.empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 8px;
		padding: 40px 16px;
		color: var(--chrome-secondary, #6b7280);
	}

	.empty-icon {
		font-size: 32px;
		opacity: 0.5;
	}

	.empty-text {
		font-size: 12px;
		text-align: center;
		margin: 0;
	}

	@media (max-width: 600px) {
		.header {
			flex-direction: column;
			align-items: flex-start;
		}
		.change-header {
			flex-wrap: wrap;
		}
		.row-actions {
			width: 100%;
			justify-content: flex-end;
			margin-top: 4px;
		}
	}
</style>
