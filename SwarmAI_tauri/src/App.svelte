<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import Sidebar from '$lib/components/Sidebar.svelte';
	import ChatView from '$lib/components/ChatView.svelte';
	import Composer from '$lib/components/Composer.svelte';
	import CommandPalette from '$lib/components/CommandPalette.svelte';
	import Tour from '$lib/components/Tour.svelte';
	import TerminalPanel from '$lib/components/TerminalPanel.svelte';
	import SettingsView from '$lib/components/settings/SettingsView.svelte';
	import { appStore } from '$lib/stores/appStore';
	import { loadThreads } from '$lib/stores/sidebarStore';
	import type { ViewKind, ChatThread, AppTheme } from '$lib/types';
	import { AppTheme as ThemeEnum } from '$lib/types';

	let {
		selectedThreadID = $bindable<string | null>(null),
		selectedProjectID = $bindable<string | null>(null),
		viewKind = $bindable<ViewKind>('chat')
	}: {
		selectedThreadID: string | null;
		selectedProjectID: string | null;
		viewKind: ViewKind;
	} = $props();

	let showCommandPalette = $state(false);
	let paletteQuery = $state('');
	let paletteIndex = $state(0);
	let isFirstLaunch = $state(false);
	let terminalVisible = $state(false);
	let sidebarCollapsed = $state(false);

	let selectedThread = $derived(
		$appStore.threads.find((t) => t.id === selectedThreadID) ?? null
	);

	let filteredPaletteItems = $derived(() => {
		const q = paletteQuery.toLowerCase().trim();
		const items: { label: string; desc: string; action: () => void; icon: string; shortcut?: string }[] = [];

		items.push({ label: 'New Thread', desc: 'Start a new conversation', action: () => { createNewThread(); showCommandPalette = false; }, icon: 'plus', shortcut: '⌘N' });
		items.push({ label: 'Settings', desc: 'Open settings', action: () => { viewKind = 'settings'; showCommandPalette = false; }, icon: 'gear', shortcut: '⌘,' });
		items.push({ label: 'Command Palette', desc: 'Search commands and actions', action: () => { showCommandPalette = true; paletteQuery = ''; paletteIndex = 0; }, icon: 'search', shortcut: '⌘K' });

		if (selectedThread) {
			items.push({ label: 'Toggle Terminal', desc: 'Show/hide terminal panel', action: () => { terminalVisible = !terminalVisible; showCommandPalette = false; }, icon: 'terminal' });
			items.push({ label: 'Toggle Hydra Panel', desc: 'Show/hide hydra heads', action: () => { showCommandPalette = false; }, icon: 'hydra' });
			items.push({ label: 'Share Thread', desc: 'Copy shareable link', action: () => { showCommandPalette = false; }, icon: 'share' });
			items.push({ label: 'Export Thread', desc: 'Export as markdown', action: () => { showCommandPalette = false; }, icon: 'export' });
			items.push({ label: 'Delete Thread', desc: 'Remove this thread', action: () => { showCommandPalette = false; }, icon: 'trash' });
		}

		const recentProjects = $appStore.projects.slice(0, 5);
		for (const p of recentProjects) {
			items.push({ label: `Project: ${p.name}`, desc: p.path, action: () => { selectedProjectID = p.id; loadThreads(p.id); showCommandPalette = false; viewKind = 'chat'; }, icon: 'folder' });
		}

		if (!q) return items;

		return items.filter((item) =>
			item.label.toLowerCase().includes(q) ||
			item.desc.toLowerCase().includes(q)
		);
	});

	let paletteSelectedIndex = $derived(Math.min(paletteIndex, Math.max(0, filteredPaletteItems().length - 1)));

	onMount(() => {
		const hasLaunched = localStorage.getItem('swarmai_has_launched');
		isFirstLaunch = !hasLaunched;

		document.addEventListener('keydown', handleGlobalKeydown);
	});

	onDestroy(() => {
		document.removeEventListener('keydown', handleGlobalKeydown);
	});

	function handleGlobalKeydown(e: KeyboardEvent) {
		const mod = e.metaKey || e.ctrlKey;

		if (mod && e.key === 'k') {
			e.preventDefault();
			showCommandPalette = !showCommandPalette;
			paletteQuery = '';
			paletteIndex = 0;
		}
		if (mod && e.key === 'n') {
			e.preventDefault();
			createNewThread();
		}
		if (mod && e.key === ',') {
			e.preventDefault();
			viewKind = 'settings';
		}
		if (e.key === 'Escape' && showCommandPalette) {
			showCommandPalette = false;
		}
	}

	function createNewThread() {
		const title = 'New Thread';
		const projectId = selectedProjectID;
		const thread: ChatThread = {
			id: crypto.randomUUID(),
			project_id: projectId ?? '',
			title,
			created_at: new Date().toISOString(),
			updated_at: new Date().toISOString(),
			provider: $appStore.defaultProvider ?? 'claude',
			model: $appStore.defaultModel ?? null,
			effort: $appStore.defaultEffort ?? null,
			fast_mode: false,
			runtime_mode: 'supervised',
			interaction_mode: 'build',
			worktree_path: null,
			branch: null,
			provider_session_id: null,
			is_pinned: false,
			is_archived: false,
			is_settled: false,
			settled_at: null,
			has_unread: false,
			has_custom_title: false,
			sort_order: null,
			activity_order: null,
			activity_order_day: null,
			last_status: 'idle',
			parent_thread_id: null,
			is_in_panel: false,
			folds_helpers: false,
			hydra_enabled: false,
			hydra_pair_id: null,
			hydra_spawn_count: 0,
			hydra: null
		};
		appStore.update((s) => ({
			...s,
			threads: [thread, ...s.threads]
		}));
		selectedThreadID = thread.id;
	}

	function handlePaletteKeydown(e: KeyboardEvent) {
		if (!showCommandPalette) return;
		const items = filteredPaletteItems();
		if (e.key === 'ArrowDown') {
			e.preventDefault();
			paletteIndex = Math.min(paletteIndex + 1, items.length - 1);
		} else if (e.key === 'ArrowUp') {
			e.preventDefault();
			paletteIndex = Math.max(paletteIndex - 1, 0);
		} else if (e.key === 'Enter' && items[paletteSelectedIndex]) {
			e.preventDefault();
			items[paletteSelectedIndex].action();
		}
	}

	function handleThemeChange(e: Event) {
		const target = e.target as HTMLSelectElement;
		appStore.update((s) => ({ ...s, theme: target.value as AppTheme }));
		applyTheme(target.value as AppTheme);
	}

	function applyTheme(theme: AppTheme) {
		const root = document.documentElement;
		switch (theme) {
			case ThemeEnum.System:
				root.setAttribute('data-theme', 'system');
				break;
			case ThemeEnum.Light:
				root.setAttribute('data-theme', 'light');
				break;
			case ThemeEnum.Dark:
				root.setAttribute('data-theme', 'dark');
				break;
			default:
				root.setAttribute('data-theme', 'light');
		}
	}

	function handleFinishTour() {
		isFirstLaunch = false;
		localStorage.setItem('swarmai_has_launched', 'true');
	}

	$effect(() => {
		applyTheme($appStore.theme);
	});
</script>

<svelte:window onkeydown={handlePaletteKeydown} />

<div class="app-shell" class:sidebar-collapsed={sidebarCollapsed}>
	{#if isFirstLaunch}
		<Tour onFinish={handleFinishTour} />
	{:else}
		<Sidebar
			bind:selectedThreadID
			bind:selectedProjectID
			bind:viewKind
			bind:collapsed={sidebarCollapsed}
		/>

		<main class="main-area">
			{#if viewKind === 'settings'}
				<SettingsView
					bind:selectedThreadID
					bind:selectedProjectID
					bind:viewKind
				/>
			{:else if viewKind === 'about'}
				<AboutView />
			{:else if selectedThread}
				<ChatView {selectedThread} bind:terminalVisible />
				{#if terminalVisible}
					<TerminalPanel threadId={selectedThread.id} />
				{/if}
				<Composer threadId={selectedThread.id} />
			{:else if selectedProjectID}
				<div class="empty-state">
					<h2>Project Selected</h2>
					<p>Create or select a thread to start chatting</p>
				</div>
			{:else}
				<div class="empty-state">
					<h2>Welcome to SwarmAI</h2>
					<p>Select a project from the sidebar or create a new thread to get started</p>
					<div class="shortcut-hints">
						<span class="hint"><kbd>⌘</kbd><kbd>N</kbd> New Thread</span>
						<span class="hint"><kbd>⌘</kbd><kbd>K</kbd> Command Palette</span>
						<span class="hint"><kbd>⌘</kbd><kbd>,</kbd> Settings</span>
					</div>
				</div>
			{/if}
		</main>
	{/if}

	{#if showCommandPalette}
		<CommandPalette
			bind:open={showCommandPalette}
			bind:query={paletteQuery}
			bind:selectedIndex={paletteIndex}
			items={filteredPaletteItems()}
		/>
	{/if}
</div>

<style>
	.shortcut-hints {
		display: flex;
		gap: var(--space-4);
		margin-top: var(--space-6);
	}

	.hint {
		display: flex;
		align-items: center;
		gap: var(--space-1);
		font-size: var(--font-size-xs);
		color: var(--text-tertiary);
	}

	kbd {
		padding: 2px 6px;
		border: var(--border-1) var(--border-color-1);
		border-radius: var(--radius-sm);
		font-family: var(--font-mono);
		font-size: 10px;
		background: var(--surface-2);
		color: var(--text-secondary);
	}
</style>
