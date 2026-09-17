<script lang="ts">
	import { onMount } from 'svelte';
	import { appStore, selectProject, selectThread, toggleSidebar } from '$lib/stores/appStore';
	import { getHydraHeads } from '$lib/stores/appStore';
	import { threads, searchQuery, setSearchQuery, selectedThreadId, selectThread as selectThreadAction, loadThreads, removeThread, createThread, setSidebarWidth, sidebarWidth, showArchive, sortOrder, loadProjects, activeProjectId } from '$lib/stores/sidebarStore';
	import type { ChatThread, HydraHeadInfo } from '$lib/types';

	let {
		selectedProjectID = $bindable(),
		selectedThreadID = $bindable(),
		viewKind = $bindable('chat')
	}: {
		selectedProjectID: string | null;
		selectedThreadID: string | null;
		viewKind: string;
	} = $props();

	let showNewThreadInput = $state(false);
	let newThreadTitle = $state('');
	let isResizing = $state(false);
	let localSearchQuery = $state('');

	function handleSelectProject(projectId: string) {
		selectProject(projectId);
		selectedThreadID = null;
		loadThreads(projectId);
	}

	function handleSelectThread(thread: ChatThread) {
		selectThread(thread.id);
		selectedProjectID = thread.projectID;
		selectedThreadID = thread.id;
		viewKind = 'chat';
	}

	async function handleCreateThread() {
		if (!newThreadTitle.trim()) return;
		const projectId = selectedProjectID;
		await createThread({
			title: newThreadTitle.trim(),
			projectID: projectId
		});
		newThreadTitle = '';
		showNewThreadInput = false;
	}

	function handleResizeStart(e: MouseEvent) {
		isResizing = true;
		const startX = e.clientX;
		const startWidth = $sidebarWidth;

		function onMouseMove(ev: MouseEvent) {
			const newWidth = Math.min(Math.max(startWidth + (ev.clientX - startX), 200), 400);
			setSidebarWidth(newWidth);
		}

		function onMouseUp() {
			isResizing = false;
			document.removeEventListener('mousemove', onMouseMove);
			document.removeEventListener('mouseup', onMouseUp);
		}

		document.addEventListener('mousemove', onMouseMove);
		document.addEventListener('mouseup', onMouseUp);
	}

	let visibleThreads = $derived($threads.filter(t => $showArchive || !t.isArchived));
	let sortedThreads = $derived([...visibleThreads].sort((a, b) => {
		if (a.isPinned && !b.isPinned) return -1;
		if (!a.isPinned && b.isPinned) return 1;
		return new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime();
	}));
	let filteredThreads = $derived(sortedThreads.filter(t => {
		if (!$localSearchQuery) return true;
		const q = $localSearchQuery.toLowerCase();
		return t.title.toLowerCase().includes(q) || t.provider?.toLowerCase().includes(q);
	}));
	let pinnedThreads = $derived(filteredThreads.filter(t => t.isPinned));
	let unpinnedThreads = $derived(filteredThreads.filter(t => !t.isPinned));

	function formatDate(dateStr: string): string {
		const date = new Date(dateStr);
		const now = new Date();
		const diffMs = now.getTime() - date.getTime();
		const diffDays = Math.floor(diffMs / 86400000);
		if (diffDays === 0) return 'Today';
		if (diffDays === 1) return 'Yesterday';
		if (diffDays < 7) return `${diffDays}d ago`;
		return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
	}

	// Load projects on mount
	onMount(() => {
		loadProjects();
	});

	let selectedProjects = $derived($appStore.projects);
	let activeProject = $derived($appStore.projects.find(p => p.id === selectedProjectID));

	function navigateTo(view: string) {
		viewKind = view;
	}
</script>

<div class="sidebar" style="width: {$sidebarWidth}px;">
	<!-- Sidebar Header -->
	<div class="sidebar-header">
		<div class="sidebar-logo">
			<img src="/icons/swarmai-logo.svg" alt="SwarmAI" class="logo-icon" width="22" height="22" />
			<span class="logo-text">SwarmAI</span>
		</div>
		<div class="sidebar-header-actions">
			<button class="icon-btn" onclick={toggleSidebar} title="Collapse sidebar">
				<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
					<rect x="3" y="3" width="18" height="18" rx="2"/>
					<path d="M9 3v18"/>
				</svg>
			</button>
		</div>
	</div>

	<!-- Project Selector -->
	<div class="project-section">
		<select
			class="project-select"
			value={selectedProjectID ?? ''}
			onchange={(e) => {
				const val = e.currentTarget.value;
				handleSelectProject(val);
			}}
		>
			<option value="">All Projects</option>
			{#each selectedProjects as project (project.id)}
				<option value={project.id}>{project.name}</option>
			{/each}
		</select>
	</div>

	<!-- Search -->
	<div class="search-section">
		<div class="search-input-wrapper">
			<svg class="search-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
				<circle cx="11" cy="11" r="8"/>
				<path d="m21 21-4.35-4.35"/>
			</svg>
			<input
				type="text"
				class="search-input"
				placeholder="Search threads…"
				value={localSearchQuery}
				oninput={(e) => localSearchQuery = e.currentTarget.value}
			/>
			{#if localSearchQuery}
				<button class="search-clear" onclick={() => localSearchQuery = ''}>
					<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
						<path d="M18 6L6 18M6 6l12 12"/>
					</svg>
				</button>
			{/if}
		</div>
	</div>

	<!-- New Thread Button -->
	<div class="new-thread-section">
		{#if showNewThreadInput}
			<div class="new-thread-form">
				<input
					type="text"
					class="new-thread-input"
					placeholder="Thread title…"
					value={newThreadTitle}
					oninput={(e) => newThreadTitle = e.currentTarget.value}
					onkeydown={(e) => {
						if (e.key === 'Enter') handleCreateThread();
						if (e.key === 'Escape') { showNewThreadInput = false; newThreadTitle = ''; }
					}}
					autofocus
				/>
				<div class="new-thread-actions">
					<button class="create-btn" onclick={handleCreateThread}>Create</button>
					<button class="cancel-btn" onclick={() => { showNewThreadInput = false; newThreadTitle = ''; }}>Cancel</button>
				</div>
			</div>
		{:else}
			<button class="new-thread-btn" onclick={() => showNewThreadInput = true}>
				<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
					<path d="M12 5v14M5 12h14"/>
				</svg>
				New Thread
			</button>
		{/if}
	</div>

	<!-- Thread List -->
	<div class="thread-list">
		{#if pinnedThreads.length > 0}
			<div class="thread-group">
				{#each pinnedThreads as thread (thread.id)}
					{@const hydraHeads = getHydraHeads(thread)}
					<div
						class="thread-item"
						class:selected={thread.id === selectedThreadID}
						class:running={thread.lastStatus === 'running'}
						onclick={() => handleSelectThread(thread)}
					>
						<div class="thread-item-content">
							<span class="thread-title">{thread.title}</span>
							<span class="thread-date">{formatDate(thread.updatedAt)}</span>
						</div>
						<div class="thread-item-meta">
							{#if thread.provider}
								<span class="thread-provider">{thread.provider}</span>
							{/if}
							{#if hydraHeads.length > 0}
								<span class="hydra-indicator">
									<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
										<path d="M12 2l2 4 4 1-3 3 1 4-4-2-4 2 1-4-3-3 4-1z"/>
									</svg>
								</span>
							{/if}
							{#if thread.lastStatus === 'running'}
								<span class="running-dot"></span>
							{/if}
							<button
								class="thread-delete"
								onclick={(e) => { e.stopPropagation(); removeThread(thread.id); }}
								title="Delete thread"
							>
								<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
									<path d="M3 6h18M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>
								</svg>
							</button>
						</div>
					</div>
				{/each}
			</div>
		{/if}

		{#each unpinnedThreads as thread (thread.id)}
			{@const hydraHeads = getHydraHeads(thread)}
			<div
				class="thread-item"
				class:selected={thread.id === selectedThreadID}
				class:running={thread.lastStatus === 'running'}
				onclick={() => handleSelectThread(thread)}
			>
				<div class="thread-item-content">
					<span class="thread-title">{thread.title}</span>
					<span class="thread-date">{formatDate(thread.updatedAt)}</span>
				</div>
				<div class="thread-item-meta">
					{#if thread.provider}
						<span class="thread-provider">{thread.provider}</span>
					{/if}
					{#if hydraHeads.length > 0}
						<span class="hydra-indicator">
							<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
								<path d="M12 2l2 4 4 1-3 3 1 4-4-2-4 2 1-4-3-3 4-1z"/>
							</svg>
						</span>
					{/if}
					{#if thread.lastStatus === 'running'}
						<span class="running-dot"></span>
					{/if}
					<button
						class="thread-delete"
						onclick={(e) => { e.stopPropagation(); removeThread(thread.id); }}
						title="Delete thread"
					>
						<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
							<path d="M3 6h18M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>
						</svg>
					</button>
				</div>
			</div>
		{/each}

		{#if filteredThreads.length === 0}
			<div class="empty-threads">
				{#if localSearchQuery}
					<p>No threads match your search.</p>
				{:else if selectedProjectID}
					<p>No threads in this project yet.</p>
				{:else}
					<p>Select a project or create a thread.</p>
				{/if}
			</div>
		{/if}
	</div>

	<!-- Sidebar Footer -->
	<div class="sidebar-footer">
		<div class="footer-nav">
			<button
				class="footer-btn"
				class:active={viewKind === 'chat'}
				onclick={() => navigateTo('chat')}
				title="Chat"
			>
				<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
					<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
				</svg>
			</button>
			<button
				class="footer-btn"
				class:active={viewKind === 'settings'}
				onclick={() => navigateTo('settings')}
				title="Settings"
			>
				<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
					<circle cx="12" cy="12" r="3"/>
					<path d="M12 1v6m0 6v6m4.22-10.22l4.24-4.24M6.34 17.66l-4.24 4.24M23 12h-6m-6 0H1m20.07-4.93l-4.24 4.24M6.34 6.34L2.1 2.1"/>
				</svg>
			</button>
			<button
				class="footer-btn"
				class:active={viewKind === 'about'}
				onclick={() => navigateTo('about')}
				title="About"
			>
				<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
					<circle cx="12" cy="12" r="10"/>
					<path d="M12 16v-4M12 8h.01"/>
				</svg>
			</button>
		</div>
	</div>

	<!-- Resize Handle -->
	{#if !isResizing}
		<div class="resize-handle" onmousedown={handleResizeStart}></div>
	{/if}
</div>

<style>
	.sidebar {
		display: flex;
		flex-direction: column;
		background: var(--surface-2);
		border-right: var(--border-1) var(--border-color-1);
		flex-shrink: 0;
		overflow: hidden;
		position: relative;
		user-select: none;
	}

	.sidebar-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: var(--space-4) var(--space-5);
		flex-shrink: 0;
		border-bottom: var(--border-1) var(--border-color-2);
	}

	.sidebar-logo {
		display: flex;
		align-items: center;
		gap: var(--space-2);
	}

	.logo-icon {
		width: 22px;
		height: 22px;
		flex-shrink: 0;
	}

	.logo-text {
		font-size: var(--font-size-md);
		font-weight: 700;
		color: var(--text-primary);
		letter-spacing: -0.3px;
	}

	.sidebar-header-actions {
		display: flex;
		align-items: center;
		gap: var(--space-1);
	}

	.icon-btn {
		width: 26px;
		height: 26px;
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

	.icon-btn:hover {
		background: var(--surface-3);
		color: var(--text-primary);
	}

	.project-section {
		padding: var(--space-3) var(--space-4);
		flex-shrink: 0;
	}

	.project-select {
		width: 100%;
		padding: 5px 8px;
		border: var(--border-1) var(--border-color-1);
		background: var(--surface-1);
		border-radius: var(--radius-sm);
		font-size: var(--font-size-xs);
		color: var(--text-primary);
		font-family: var(--font-system);
		cursor: pointer;
		outline: none;
		appearance: none;
		-webkit-appearance: none;
		background-image: url("data:image/svg+xml,%3Csvg width='8' height='5' viewBox='0 0 8 5' fill='none' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath d='M1 1l3 3 3-3' stroke='%2398989d' stroke-width='1.5' stroke-linecap='round'/%3E%3C/svg%3E");
		background-repeat: no-repeat;
		background-position: right 8px center;
		padding-right: 24px;
	}

	.project-select:focus {
		border-color: var(--accent-1);
	}

	.search-section {
		padding: var(--space-2) var(--space-4);
		flex-shrink: 0;
	}

	.search-input-wrapper {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		padding: 0 var(--space-3);
		border: var(--border-1) var(--border-color-1);
		background: var(--surface-1);
		border-radius: var(--radius-md);
		transition: border-color var(--transition-fast);
	}

	.search-input-wrapper:focus-within {
		border-color: var(--accent-1);
	}

	.search-icon {
		color: var(--text-tertiary);
		flex-shrink: 0;
	}

	.search-input {
		flex: 1;
		border: none;
		background: none;
		padding: 5px 0;
		font-size: var(--font-size-xs);
		color: var(--text-primary);
		outline: none;
		font-family: var(--font-system);
	}

	.search-input::placeholder {
		color: var(--text-tertiary);
	}

	.search-clear {
		display: flex;
		align-items: center;
		justify-content: center;
		border: none;
		background: none;
		color: var(--text-tertiary);
		cursor: pointer;
		padding: 2px;
		border-radius: 50%;
		transition: all var(--transition-fast);
	}

	.search-clear:hover {
		background: var(--surface-3);
		color: var(--text-primary);
	}

	.new-thread-section {
		padding: var(--space-2) var(--space-4);
		flex-shrink: 0;
	}

	.new-thread-btn {
		width: 100%;
		display: flex;
		align-items: center;
		justify-content: center;
		gap: var(--space-2);
		padding: 6px;
		border: var(--border-1) var(--border-color-1);
		background: var(--surface-1);
		border-radius: var(--radius-md);
		font-size: var(--font-size-xs);
		font-weight: 500;
		color: var(--text-secondary);
		cursor: pointer;
		transition: all var(--transition-fast);
	}

	.new-thread-btn:hover {
		background: var(--accent-3);
		border-color: var(--accent-1);
		color: var(--accent-1);
	}

	.new-thread-form {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}

	.new-thread-input {
		width: 100%;
		padding: 6px 10px;
		border: var(--border-1) var(--accent-1);
		background: var(--surface-1);
		border-radius: var(--radius-md);
		font-size: var(--font-size-xs);
		color: var(--text-primary);
		outline: none;
		font-family: var(--font-system);
	}

	.new-thread-actions {
		display: flex;
		gap: var(--space-2);
	}

	.create-btn {
		flex: 1;
		padding: 4px 10px;
		border: none;
		background: var(--accent-1);
		color: var(--text-inverse);
		border-radius: var(--radius-sm);
		font-size: var(--font-size-xs);
		font-weight: 500;
		cursor: pointer;
		transition: background var(--transition-fast);
	}

	.create-btn:hover {
		background: var(--accent-2);
	}

	.cancel-btn {
		flex: 1;
		padding: 4px 10px;
		border: var(--border-1) var(--border-color-1);
		background: none;
		border-radius: var(--radius-sm);
		font-size: var(--font-size-xs);
		color: var(--text-secondary);
		cursor: pointer;
	}

	.cancel-btn:hover {
		background: var(--surface-3);
	}

	.thread-list {
		flex: 1;
		overflow-y: auto;
		padding: var(--space-1) var(--space-2);
	}

	.thread-group {
		margin-bottom: var(--space-2);
	}

	.thread-group-label {
		padding: var(--space-2) var(--space-3);
		font-size: 10px;
		font-weight: 600;
		color: var(--text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.5px;
	}

	.thread-item {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--space-2);
		padding: 7px var(--space-3);
		border-radius: var(--radius-md);
		cursor: pointer;
		transition: all var(--transition-fast);
		position: relative;
	}

	.thread-item:hover {
		background: var(--surface-3);
	}

	.thread-item.selected {
		background: var(--accent-3);
	}

	.thread-item.selected::before {
		content: '';
		position: absolute;
		left: 0;
		top: 6px;
		bottom: 6px;
		width: 3px;
		border-radius: 0 2px 2px 0;
		background: var(--accent-1);
	}

	.thread-item.running {
		/* subtle indicator for running threads */
	}

	.thread-item-content {
		display: flex;
		flex-direction: column;
		gap: 1px;
		min-width: 0;
		flex: 1;
	}

	.thread-title {
		font-size: var(--font-size-xs);
		font-weight: 500;
		color: var(--text-primary);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.thread-item.running .thread-title {
		color: var(--accent-1);
	}

	.thread-date {
		font-size: 10px;
		color: var(--text-tertiary);
	}

	.thread-item-meta {
		display: flex;
		align-items: center;
		gap: var(--space-1);
		flex-shrink: 0;
	}

	.thread-provider {
		font-size: 9px;
		font-family: var(--font-mono);
		text-transform: uppercase;
		padding: 1px 6px;
		border-radius: var(--radius-full);
		background: var(--surface-3);
		color: var(--text-tertiary);
		letter-spacing: 0.3px;
	}

	.hydra-indicator {
		color: var(--accent-1);
		display: flex;
	}

	.running-dot {
		width: 5px;
		height: 5px;
		border-radius: 50%;
		background: var(--accent-1);
		animation: blink 1s ease-in-out infinite;
	}

	@keyframes blink {
		0%, 100% { opacity: 1; }
		50% { opacity: 0.3; }
	}

	.thread-delete {
		display: none;
		align-items: center;
		justify-content: center;
		width: 18px;
		height: 18px;
		border: none;
		background: transparent;
		color: var(--text-tertiary);
		cursor: pointer;
		border-radius: var(--radius-sm);
		transition: all var(--transition-fast);
	}

	.thread-item:hover .thread-delete {
		display: flex;
	}

	.thread-delete:hover {
		background: rgba(255, 59, 48, 0.15);
		color: var(--danger);
	}

	.empty-threads {
		padding: var(--space-8) var(--space-4);
		text-align: center;
		color: var(--text-tertiary);
		font-size: var(--font-size-xs);
	}

	.sidebar-footer {
		border-top: var(--border-1) var(--border-color-2);
		padding: var(--space-2);
		flex-shrink: 0;
	}

	.footer-nav {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: var(--space-1);
	}

	.footer-btn {
		width: 34px;
		height: 30px;
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

	.footer-btn:hover {
		background: var(--surface-3);
		color: var(--text-primary);
	}

	.footer-btn.active {
		background: var(--accent-3);
		color: var(--accent-1);
	}

	.resize-handle {
		position: absolute;
		right: 0;
		top: 0;
		bottom: 0;
		width: 4px;
		cursor: col-resize;
		z-index: 10;
	}

	.resize-handle:hover {
		background: var(--accent-3);
	}

	/* Scrollbar */
	.thread-list::-webkit-scrollbar {
		width: 5px;
	}

	.thread-list::-webkit-scrollbar-track {
		background: transparent;
	}

	.thread-list::-webkit-scrollbar-thumb {
		background: var(--surface-4);
		border-radius: var(--radius-full);
	}

	.thread-list::-webkit-scrollbar-thumb:hover {
		background: var(--surface-5);
	}
</style>
