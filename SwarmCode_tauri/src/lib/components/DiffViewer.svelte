<script lang="ts">
	import { invoke } from '@tauri-apps/api/core';
	import type { GitStatus, DiffEntry } from '$lib/types';

	interface Props {
		projectPath: string | null;
		onClose?: () => void;
	}

	let { projectPath = null, onClose }: Props = $props();

	let status = $state<GitStatus | null>(null);
	let selectedPath = $state<string | null>(null);
	let diffContent = $state('');
	let isLoading = $state(true);
	let error = $state<string | null>(null);

	$effect(() => {
		loadGitStatus();
	});

	async function loadGitStatus() {
		if (!projectPath) {
			isLoading = false;
			return;
		}
		try {
			status = await invoke<GitStatus>('get_git_status', { projectPath });
			error = null;
		} catch (e) {
			console.error('Failed to load git status:', e);
			error = 'Failed to load git status';
			status = null;
		} finally {
			isLoading = false;
		}
	}

	async function selectFile(path: string) {
		selectedPath = path;
		diffContent = '';
		try {
			const diffs = await invoke<DiffEntry[]>('get_diff', {
				projectPath,
				paths: [path]
			});
			if (diffs.length > 0) {
				diffContent = diffs[0].diff ?? '';
			}
		} catch (e) {
			console.error('Failed to load diff:', e);
			diffContent = 'Unable to load diff';
		}
	}

	let allFiles = $derived(() => {
		if (!status) return [];
		const files: Array<{ path: string; status: string; staged: boolean }> = [];
		for (const p of status.staged ?? []) files.push({ path: p, status: 'staged', staged: true });
		for (const p of status.modified ?? []) files.push({ path: p, status: 'modified', staged: false });
		for (const p of status.added ?? []) files.push({ path: p, status: 'added', staged: false });
		for (const p of status.deleted ?? []) files.push({ path: p, status: 'deleted', staged: false });
		for (const p of status.renamed ?? []) files.push({ path: p, status: 'renamed', staged: false });
		for (const p of status.untracked ?? []) files.push({ path: p, status: 'untracked', staged: false });
		return files;
	});

	let stagedCount = $derived((status?.staged ?? []).length);
	let modifiedCount = $derived((status?.modified ?? []).length);
	let addedCount = $derived((status?.added ?? []).length);
	let deletedCount = $derived((status?.deleted ?? []).length);
	let untrackedCount = $derived((status?.untracked ?? []).length);

	let diffLines = $derived(() => {
		if (!diffContent) return [];
		return diffContent.split('\n').map(line => {
			if (line.startsWith('+') && !line.startsWith('+++')) return { text: line, type: 'add' as const };
			if (line.startsWith('-') && !line.startsWith('---')) return { text: line, type: 'del' as const };
			if (line.startsWith('@@')) return { text: line, type: 'meta' as const };
			return { text: line, type: 'context' as const };
		});
	});

	function statusBadgeColor(st: string): string {
		switch (st) {
			case 'staged': return 'var(--info)';
			case 'modified': return 'var(--warning)';
			case 'added': return 'var(--success)';
			case 'deleted': return 'var(--danger)';
			case 'renamed': return 'var(--accent-1)';
			case 'untracked': return 'var(--text-tertiary)';
			default: return 'var(--text-tertiary)';
		}
	}

	function statusLabel(st: string): string {
		switch (st) {
			case 'staged': return 'S';
			case 'modified': return 'M';
			case 'added': return 'A';
			case 'deleted': return 'D';
			case 'renamed': return 'R';
			case 'untracked': return '?';
			default: return '?';
		}
	}

	function formatPath(p: string): string {
		const parts = p.split('/');
		return parts.length > 1 ? parts.slice(-2).join('/') : p;
	}
</script>

<div class="diff-viewer">
	<div class="diff-header">
		<div class="diff-title">
			<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
				<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
				<polyline points="14,2 14,8 20,8"/>
				<line x1="9" y1="13" x2="15" y2="13"/>
				<line x1="9" y1="17" x2="15" y2="17"/>
			</svg>
			<span>Git Changes</span>
		</div>
		{#if status}
			<div class="diff-summary">
				<span class="summary-item">
					<span class="summary-count" style="color: var(--info)">{stagedCount}</span>
					<span class="summary-label">staged</span>
				</span>
				<span class="summary-item">
					<span class="summary-count" style="color: var(--warning)">{modifiedCount}</span>
					<span class="summary-label">modified</span>
				</span>
				<span class="summary-item">
					<span class="summary-count" style="color: var(--success)">{addedCount}</span>
					<span class="summary-label">added</span>
				</span>
				<span class="summary-item">
					<span class="summary-count" style="color: var(--danger)">{deletedCount}</span>
					<span class="summary-label">deleted</span>
				</span>
				{#if status?.branch}
					<span class="branch-badge">&#x2398; {status.branch}</span>
				{/if}
			</div>
		{/if}
		{#if onClose}
			<button class="close-btn" onclick={onClose} title="Close">
				<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
					<path d="M18 6L6 18M6 6l12 12"/>
				</svg>
			</button>
		{/if}
	</div>

	{#if isLoading}
		<div class="loading-state">
			<div class="spinner"></div>
			<p>Loading git status…</p>
		</div>
	{:else if error}
		<div class="error-state">
			<p>{error}</p>
		</div>
	{:else}
		<div class="diff-body">
			<!-- File list -->
			<div class="file-list">
				{#if allFiles().length === 0}
					<div class="empty-state">
						<svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" opacity="0.4">
							<circle cx="18" cy="18" r="3"/>
							<circle cx="6" cy="6" r="3"/>
							<path d="M6 21V9a9 9 0 0 0 9 9"/>
						</svg>
						<p>Working tree clean</p>
						<span>No changes to commit</span>
					</div>
				{:else}
					{#each allFiles() as file}
						<div
							class="file-row"
							class:selected={selectedPath === file.path}
						>
							<button class="file-button" onclick={() => selectFile(file.path)}>
								<span class="status-icon" style="color: {statusBadgeColor(file.status)}">
									{statusLabel(file.status)}
								</span>
								<span class="file-name">{file.path.split('/').pop()}</span>
								<span class="file-path">{formatPath(file.path)}</span>
							</button>
						</div>
					{/each}
				{/if}
			</div>

			<!-- Diff content -->
			<div class="diff-content">
				{#if selectedPath}
					<div class="diff-content-header">
						<span class="diff-content-path">{selectedPath}</span>
					</div>
					<div class="diff-pane">
						{#if diffLines().length === 0}
							<div class="no-diff">No diff available</div>
						{:else}
							{#each diffLines() as line, idx (idx)}
								<div class="diff-line {line.type}">
									<span class="line-num">{idx + 1}</span>
									<span class="line-marker">
										{line.type === 'add' ? '+' :
											line.type === 'del' ? '-' :
											line.type === 'meta' ? '@' : ' '}
									</span>
									<span class="line-text">{line.text}</span>
								</div>
							{/each}
						{/if}
					</div>
				{:else}
					<div class="no-selection">
						<svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" opacity="0.3">
							<polyline points="9 14 4 9 9 4"/>
							<path d="M20 20v-7a4 4 0 0 0-4-4H4"/>
						</svg>
						<p>Select a file to view its diff</p>
					</div>
				{/if}
			</div>
		</div>
	{/if}
</div>

<style>
	.diff-viewer {
		display: flex;
		flex-direction: column;
		height: 100%;
		background: var(--surface-2);
		border-left: var(--border-1) var(--border-color-1);
		width: 480px;
		flex-shrink: 0;
		overflow: hidden;
	}

	.diff-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: var(--space-3) var(--space-4);
		border-bottom: var(--border-1) var(--border-color-1);
		flex-shrink: 0;
		gap: var(--space-3);
	}

	.diff-title {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		font-size: var(--font-size-sm);
		font-weight: 600;
		color: var(--text-primary);
		flex: 1;
		min-width: 0;
	}

	.diff-summary {
		display: flex;
		align-items: center;
		gap: var(--space-3);
	}

	.summary-item {
		display: flex;
		align-items: center;
		gap: var(--space-1);
	}

	.summary-count {
		font-size: var(--font-size-sm);
		font-weight: 600;
		font-family: var(--font-mono);
	}

	.summary-label {
		font-size: 10px;
		color: var(--text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.3px;
	}

	.branch-badge {
		display: inline-flex;
		align-items: center;
		gap: 2px;
		font-size: 10px;
		font-family: var(--font-mono);
		color: var(--text-secondary);
		background: var(--surface-3);
		padding: 2px 8px;
		border-radius: var(--radius-full);
	}

	.close-btn {
		display: flex;
		align-items: center;
		justify-content: center;
		width: 28px;
		height: 28px;
		border: none;
		background: transparent;
		border-radius: var(--radius-sm);
		color: var(--text-tertiary);
		cursor: pointer;
		transition: all var(--transition-fast);
		flex-shrink: 0;
	}

	.close-btn:hover {
		background: var(--surface-3);
		color: var(--text-primary);
	}

	.diff-body {
		flex: 1;
		display: flex;
		overflow: hidden;
	}

	.file-list {
		flex: 1;
		overflow-y: auto;
		min-width: 0;
	}

	.file-row {
		padding: 0;
	}

	.file-row.selected {
		background: var(--accent-3);
	}

	.file-button {
		width: 100%;
		display: flex;
		align-items: center;
		gap: var(--space-2);
		padding: 5px var(--space-3) 5px var(--space-4);
		border: none;
		background: none;
		text-align: left;
		cursor: pointer;
		min-width: 0;
	}

	.status-icon {
		flex-shrink: 0;
		font-size: 10px;
		font-weight: 700;
		font-family: var(--font-mono);
	}

	.file-name {
		font-size: var(--font-size-xs);
		font-weight: 500;
		color: var(--text-primary);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.file-path {
		flex: 1;
		font-size: 10px;
		color: var(--text-tertiary);
		font-family: var(--font-mono);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		min-width: 0;
	}

	.diff-content {
		flex: 1.2;
		display: flex;
		flex-direction: column;
		border-left: var(--border-1) var(--border-color-1);
		min-width: 0;
	}

	.diff-content-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: var(--space-2) var(--space-4);
		border-bottom: var(--border-1) var(--border-color-1);
		flex-shrink: 0;
	}

	.diff-content-path {
		font-size: var(--font-size-xs);
		font-family: var(--font-mono);
		color: var(--text-secondary);
		flex: 1;
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.diff-pane {
		flex: 1;
		overflow-y: auto;
		background: var(--surface-1);
		font-family: var(--font-mono);
		font-size: 12px;
	}

	.diff-line {
		display: flex;
		padding: 2px 16px;
		line-height: 1.5;
	}

	.diff-line.context {
		background: var(--surface-1);
		color: var(--text-secondary);
	}

	.diff-line.add {
		background: rgba(48, 209, 88, 0.1);
	}

	.diff-line.add .line-text {
		color: var(--success);
	}

	.diff-line.del {
		background: rgba(255, 59, 48, 0.1);
	}

	.diff-line.del .line-text {
		color: var(--danger);
	}

	.diff-line.meta {
		background: var(--surface-3);
		color: var(--info);
		padding-left: 24px;
	}

	.line-num {
		width: 32px;
		color: var(--text-tertiary);
		text-align: right;
		margin-right: 16px;
		flex-shrink: 0;
		user-select: none;
	}

	.line-marker {
		width: 18px;
		font-weight: 700;
		flex-shrink: 0;
	}

	.line-text {
		flex: 1;
		white-space: pre;
	}

	.no-diff {
		padding: var(--space-4);
		color: var(--text-tertiary);
		text-align: center;
		font-style: italic;
	}

	.no-selection {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		flex: 1;
		padding: var(--space-4);
		color: var(--text-tertiary);
		text-align: center;
	}

	.no-selection p {
		font-size: var(--font-size-sm);
		margin-top: var(--space-2);
	}

	.empty-state {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		padding: var(--space-8) var(--space-4);
		color: var(--text-tertiary);
		gap: var(--space-2);
	}

	.empty-state p {
		font-size: var(--font-size-sm);
		color: var(--text-secondary);
		margin-top: var(--space-2);
	}

	.error-state {
		display: flex;
		align-items: center;
		justify-content: center;
		flex: 1;
		padding: var(--space-4);
		color: var(--danger);
		font-size: var(--font-size-sm);
	}

	.loading-state {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		flex: 1;
		gap: var(--space-2);
		color: var(--text-tertiary);
	}

	.spinner {
		width: 24px;
		height: 24px;
		border: 2px solid var(--surface-3);
		border-top-color: var(--accent-1);
		border-radius: 50%;
		animation: spin 0.7s linear infinite;
	}

	@keyframes spin {
		to { transform: rotate(360deg); }
	}

	/* Scrollbar */
	.file-list::-webkit-scrollbar,
	.diff-pane::-webkit-scrollbar {
		width: 5px;
	}

	.file-list::-webkit-scrollbar-track,
	.diff-pane::-webkit-scrollbar-track {
		background: transparent;
	}

	.file-list::-webkit-scrollbar-thumb,
	.diff-pane::-webkit-scrollbar-thumb {
		background: var(--surface-4);
		border-radius: var(--radius-full);
	}
</style>
