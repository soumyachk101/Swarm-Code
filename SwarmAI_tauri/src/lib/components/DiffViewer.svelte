<script lang="ts">
	import { onMount } from 'svelte';
	import { invoke } from '@tauri-apps/api/core';
	import type { GitStatus, DiffEntry, GitCommit } from '$lib/types';

	interface Props {
		projectId: string | null;
		onClose?: () => void;
	}

	let { projectId = null, onClose }: Props = $props();

	let status = $state<GitStatus | null>(null);
	let selectedEntry = $state<DiffEntry | null>(null);
	let diffContent = $state('');
	let isLoading = $state(true);
	let diffView = $state<'split' | 'unified'>('split');
	let isCommitting = $state(false);
	let commitMessage = $state('');
	let showCommitForm = $state(false);

	$effect(() => {
		loadGitStatus();
	});

	async function loadGitStatus() {
		try {
			status = await invoke<GitStatus>('get_git_status', { projectId });
		} catch (e) {
			console.error('Failed to load git status:', e);
		} finally {
			isLoading = false;
		}
	}

	async function selectEntry(entry: DiffEntry) {
		selectedEntry = entry;
		try {
			diffContent = await invoke<string>('get_git_diff', {
				path: entry.path,
				staged: entry.isStaged
			});
		} catch (e) {
			console.error('Failed to load diff:', e);
			diffContent = '';
		}
	}

	async function handleStage(entry: DiffEntry) {
		try {
			await invoke('git_stage', { path: entry.path });
			await loadGitStatus();
		} catch (e) {
			console.error('Failed to stage:', e);
		}
	}

	async function handleUnstage(entry: DiffEntry) {
		try {
			await invoke('git_unstage', { path: entry.path });
			await loadGitStatus();
		} catch (e) {
			console.error('Failed to unstage:', e);
		}
	}

	async function handleCommit() {
		if (!commitMessage.trim() || isCommitting) return;
		isCommitting = true;
		try {
			await invoke('git_commit', { message: commitMessage.trim() });
			commitMessage = '';
			showCommitForm = false;
			await loadGitStatus();
		} catch (e) {
			console.error('Failed to commit:', e);
		} finally {
			isCommitting = false;
		}
	}

	async function handleDiscard(entry: DiffEntry) {
		if (!confirm('Discard changes to ' + entry.path + '?')) return;
		try {
			await invoke('git_discard', { path: entry.path });
			await loadGitStatus();
		} catch (e) {
			console.error('Failed to discard:', e);
		}
	}

	let diffLines = $derived(() => {
		if (!diffContent) return [];
		return diffContent.split('\n').map(line => ({
			text: line,
			type: line.startsWith('+') && !line.startsWith('+++') ? 'add' :
				line.startsWith('-') && !line.startsWith('---') ? 'del' :
				line.startsWith('@@') ? 'meta' : 'context'
		}));
	});

	let stagedEntries = $derived(status?.entries?.filter(e => e.isStaged) ?? []);
	let unstagedEntries = $derived(status?.entries?.filter(e => !e.isStaged) ?? []);

	function getStatusBadgeColor(type: string): string {
		switch (type) {
			case 'modified': return 'var(--warning)';
			case 'added': return 'var(--success)';
			case 'deleted': return 'var(--danger)';
			case 'renamed': return 'var(--info)';
			case 'untracked': return 'var(--text-tertiary)';
			default: return 'var(--text-tertiary)';
		}
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
					<span class="summary-count staged">{stagedEntries.length}</span>
					<span class="summary-label">staged</span>
				</span>
				<span class="summary-item">
					<span class="summary-count unstaged">{unstagedEntries.length}</span>
					<span class="summary-label">unstaged</span>
				</span>
				{#if status?.branch}
					<span class="branch-badge">⎇ {status.branch}</span>
				{/if}
			</div>
		{/if}
		<div class="diff-actions">
			<button
				class="action-btn"
				class:active={showCommitForm}
				onclick={() => showCommitForm = !showCommitForm}
				disabled={stagedEntries.length === 0}
			>
				<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
					<path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/>
					<polyline points="22 4 12 14.01 9 11.01"/>
				</svg>
				Commit
			</button>
			{#if onClose}
				<button class="action-btn" onclick={onClose} title="Close">
					<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
						<path d="M18 6L6 18M6 6l12 12"/>
					</svg>
				</button>
			{/if}
		</div>
	</div>

	{#if showCommitForm}
		<div class="commit-form">
			<textarea
				class="commit-input"
				placeholder="Commit message…"
				value={commitMessage}
				oninput={(e) => commitMessage = e.currentTarget.value}
				rows={3}
			></textarea>
			<div class="commit-form-actions">
				<button class="commit-btn" onclick={handleCommit} disabled={!commitMessage.trim() || isCommitting}>
					{isCommitting ? 'Committing…' : `Commit ${stagedEntries.length} files`}
				</button>
				<button class="cancel-btn" onclick={() => { showCommitForm = false; commitMessage = ''; }}>Cancel</button>
			</div>
		</div>
	{/if}

	{#if isLoading}
		<div class="loading-state">
			<div class="spinner"></div>
			<p>Loading git status…</p>
		</div>
	{:else}
		<div class="diff-body">
			<!-- File list -->
			<div class="file-list">
				{#if stagedEntries.length > 0}
					<div class="file-list-section">
						<h4 class="file-list-section-title">
							<span>Staged Changes</span>
							<span class="count">{stagedEntries.length}</span>
						</h4>
						{#each stagedEntries as entry (entry.path)}
							<div
								class="file-row"
								class:selected={selectedEntry?.path === entry.path}
							>
								<button class="file-button" onclick={() => selectEntry(entry)}>
									<span class="status-icon" style="color: {getStatusBadgeColor(entry.status)}">●</span>
									<span class="file-name">{entry.path.split('/').pop()}</span>
									<span class="file-path">{entry.path}</span>
								</button>
								<button class="file-action" onclick={() => handleUnstage(entry)} title="Unstage">
									<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
										<polyline points="9 14 4 9 9 4"/>
										<path d="M20 20v-7a4 4 0 0 0-4-4H4"/>
									</svg>
								</button>
							</div>
						{/each}
					</div>
				{/if}

				{#if unstagedEntries.length > 0}
					<div class="file-list-section">
						<h4 class="file-list-section-title">
							<span>Unstaged Changes</span>
							<span class="count">{unstagedEntries.length}</span>
						</h4>
						{#each unstagedEntries as entry (entry.path)}
							<div
								class="file-row"
								class:selected={selectedEntry?.path === entry.path}
							>
								<button class="file-button" onclick={() => selectEntry(entry)}>
									<span class="status-icon" style="color: {getStatusBadgeColor(entry.status)}">●</span>
									<span class="file-name">{entry.path.split('/').pop()}</span>
									<span class="file-path">{entry.path}</span>
								</button>
								<div class="file-actions">
									<button class="file-action" onclick={() => handleStage(entry)} title="Stage">
										<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
											<polyline points="15 10 20 15 15 20"/>
											<path d="M4 4v7a4 4 0 0 0 4 4h12"/>
										</svg>
									</button>
									<button class="file-action" onclick={() => handleDiscard(entry)} title="Discard">
										<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
											<path d="M3 6h18M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/>
										</svg>
									</button>
								</div>
							</div>
						{/each}
					</div>
				{/if}

				{#if status?.entries?.length === 0}
					<div class="empty-state">
						<svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" opacity="0.4">
							<circle cx="18" cy="18" r="3"/>
							<circle cx="6" cy="6" r="3"/>
							<path d="M6 21V9a9 9 0 0 0 9 9"/>
						</svg>
						<p>Working tree clean</p>
						<span>No changes to commit</span>
					</div>
				{/if}
			</div>

			<!-- Diff content -->
			<div class="diff-content">
				{#if selectedEntry}
					<div class="diff-content-header">
						<span class="diff-content-path">
							{selectedEntry.path}
						</span>
						<div class="diff-view-toggle">
							<button
								class="view-btn"
								class:active={diffView === 'split'}
								onclick={() => diffView = 'split'}
							>Split</button>
							<button
								class="view-btn"
								class:active={diffView === 'unified'}
								onclick={() => diffView = 'unified'}
							>Unified</button>
						</div>
					</div>
					<div class="diff-pane" class:split={diffView === 'split'}>
						{#if diffLines().length === 0}
							<div class="no-diff">No diff available</div>
						{:else}
							{#each diffLines() as line, idx (idx)}
								<div class="diff-line {line.type}">
									{#if diffView === 'split'}
										<span class="line-num">{idx + 1}</span>
									{/if}
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

	.summary-count.staged {
		color: var(--success);
	}

	.summary-count.unstaged {
		color: var(--warning);
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

	.diff-actions {
		display: flex;
		align-items: center;
		gap: 2px;
	}

	.action-btn {
		display: flex;
		align-items: center;
		gap: 4px;
		padding: 4px 10px;
		border: var(--border-1) var(--border-color-1);
		background: transparent;
		border-radius: var(--radius-sm);
		font-size: var(--font-size-xs);
		color: var(--text-secondary);
		cursor: pointer;
		transition: all var(--transition-fast);
		font-weight: 500;
	}

	.action-btn:hover:not(:disabled) {
		background: var(--surface-3);
		color: var(--text-primary);
	}

	.action-btn.active {
		background: var(--accent-3);
		color: var(--accent-1);
		border-color: var(--accent-1);
	}

	.action-btn:disabled {
		opacity: 0.4;
		cursor: not-allowed;
	}

	.commit-form {
		padding: var(--space-3) var(--space-4);
		background: var(--surface-3);
		border-bottom: var(--border-1) var(--border-color-1);
	}

	.commit-input {
		width: 100%;
		padding: 6px 10px;
		border: var(--border-1) var(--border-color-1);
		background: var(--surface-1);
		border-radius: var(--radius-sm);
		font-size: var(--font-size-sm);
		color: var(--text-primary);
		outline: none;
		font-family: var(--font-system);
		resize: vertical;
		min-height: 60px;
	}

	.commit-input:focus {
		border-color: var(--accent-1);
	}

	.commit-form-actions {
		display: flex;
		gap: var(--space-2);
		margin-top: var(--space-2);
	}

	.commit-btn {
		flex: 1;
		padding: 6px;
		border: none;
		background: var(--accent-1);
		color: var(--text-inverse);
		border-radius: var(--radius-sm);
		font-size: var(--font-size-xs);
		font-weight: 500;
		cursor: pointer;
		transition: background var(--transition-fast);
	}

	.commit-btn:hover:not(:disabled) {
		background: var(--accent-2);
	}

	.commit-btn:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}

	.cancel-btn {
		padding: 6px 12px;
		border: var(--border-1) var(--border-color-1);
		background: none;
		border-radius: var(--radius-sm);
		font-size: var(--font-size-xs);
		color: var(--text-secondary);
		cursor: pointer;
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

	.file-list-section {
		padding: var(--space-2) 0;
	}

	.file-list-section-title {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: var(--space-2) var(--space-4);
		font-size: 10px;
		font-weight: 600;
		color: var(--text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.3px;
	}

	.file-list-section-title .count {
		font-size: 10px;
		font-family: var(--font-mono);
		background: var(--surface-3);
		padding: 1px 6px;
		border-radius: var(--radius-full);
	}

	.file-row {
		display: flex;
		align-items: center;
		gap: var(--space-1);
		padding: 4px var(--space-2) 4px var(--space-4);
	}

	.file-row.selected {
		background: var(--accent-3);
	}

	.file-button {
		flex: 1;
		display: flex;
		align-items: center;
		gap: var(--space-2);
		padding: 4px 0;
		border: none;
		background: none;
		text-align: left;
		cursor: pointer;
		min-width: 0;
	}

	.status-icon {
		flex-shrink: 0;
		font-size: 10px;
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

	.file-actions {
		display: flex;
		align-items: center;
		gap: 2px;
	}

	.file-action {
		width: 22px;
		height: 22px;
		border: none;
		background: transparent;
		border-radius: var(--radius-sm);
		color: var(--text-tertiary);
		cursor: pointer;
		display: flex;
		align-items: center;
		justify-content: center;
		transition: all var(--transition-fast);
	}

	.file-action:hover {
		background: var(--surface-3);
		color: var(--text-primary);
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
	}

	.diff-content-path {
		font-size: var(--font-size-xs);
		font-family: var(--font-mono);
		color: var(--text-secondary);
	}

	.diff-view-toggle {
		display: flex;
		gap: 2px;
		padding: 2px;
		background: var(--surface-3);
		border-radius: var(--radius-sm);
	}

	.view-btn {
		padding: 3px 8px;
		border: none;
		background: transparent;
		border-radius: 3px;
		font-size: 11px;
		color: var(--text-secondary);
		cursor: pointer;
		transition: all var(--transition-fast);
	}

	.view-btn.active {
		background: var(--surface-1);
		color: var(--text-primary);
	}

	.diff-pane {
		flex: 1;
		overflow-y: auto;
		background: var(--surface-1);
		font-family: var(--font-mono);
		font-size: 12px;
	}

	.diff-pane.split {
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
		color: var(--success);
	}

	.diff-line.del {
		background: rgba(255, 59, 48, 0.1);
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

	.empty-state span {
		font-size: var(--font-size-xs);
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
