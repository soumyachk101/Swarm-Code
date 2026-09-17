<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import Sidebar from '$lib/components/Sidebar.svelte';
	import ChatView from '$lib/components/ChatView.svelte';
	import Composer from '$lib/components/Composer.svelte';
	import CommandPalette from '$lib/components/CommandPalette.svelte';
	import Tour from '$lib/components/Tour.svelte';
	import TerminalPanel from '$lib/components/TerminalPanel.svelte';
	import SettingsView from '$lib/components/settings/SettingsView.svelte';
	import AboutView from '$lib/components/settings/AboutView.svelte';
	import { appStore } from '$lib/stores/appStore';
	import { loadThreads } from '$lib/stores/sidebarStore';
	import type { ViewKind, ChatThread, AppTheme } from '$lib/types';
	import { AppTheme as ThemeEnum } from '$lib/types';

	interface PaletteCommand {
		id: string;
		label: string;
		desc: string;
		action: () => void;
		icon: string;
		shortcut?: string;
		category?: string;
		keywords?: string[];
	}

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
	let isFirstLaunch = $state(false);
	let terminalVisible = $state(false);
	let sidebarCollapsed = $state(false);
	let paletteIndex = $state(0);

	let selectedThread = $derived(
		$appStore.threads.find((t) => t.id === selectedThreadID) ?? null
	);

	let paletteCommands: PaletteCommand[] = $derived.by(() => {
		const items: PaletteCommand[] = [];

		items.push({ id: 'new-thread', label: 'New Thread', desc: 'Start a new conversation', action: () => { createNewThread(); }, icon: 'plus', shortcut: '⌘N', category: 'Threads', keywords: ['create', 'new'] });
		items.push({ id: 'settings', label: 'Settings', desc: 'Open settings', action: () => { viewKind = 'settings'; }, icon: 'gear', shortcut: '⌘,', category: 'Navigation', keywords: ['preferences', 'config'] });
		items.push({ id: 'about', label: 'About SwarmAI', desc: 'Show app version and credits', action: () => { viewKind = 'about'; }, icon: 'info', category: 'Navigation', keywords: ['version', 'info'] });

		if (selectedThread) {
			items.push({ id: 'toggle-terminal', label: 'Toggle Terminal', desc: 'Show/hide terminal panel', action: () => { terminalVisible = !terminalVisible; }, icon: 'terminal', shortcut: '⌘T', category: 'Navigation', keywords: ['shell', 'bash'] });
			items.push({ id: 'toggle-hydra', label: 'Toggle Hydra Panel', desc: 'Show/hide hydra heads', action: () => {}, icon: 'hydra', category: 'Actions', keywords: ['swarm', 'parallel', 'multi'] });
			items.push({ id: 'attach-file', label: 'Attach File', desc: 'Add a file to the message', action: () => {}, icon: 'attach', category: 'Actions', keywords: ['upload', 'file'] });
			items.push({ id: 'delete-thread', label: 'Delete Thread', desc: 'Remove this thread', action: () => {}, icon: 'trash', category: 'Actions', keywords: ['remove'] });
		}

		const recentProjects = $appStore.projects.slice(0, 5);
		for (const p of recentProjects) {
			items.push({ id: 'project-' + p.id, label: `Project: ${p.name}`, desc: p.path, action: () => { selectedProjectID = p.id; loadThreads(p.id); viewKind = 'chat'; }, icon: 'folder', category: 'Projects', keywords: ['switch', 'open'] });
		}

		return items;
	});

	let filteredPaletteItems = $derived(paletteCommands);

	let paletteSelectedIndex = $derived(Math.min(paletteIndex, Math.max(0, filteredPaletteItems.length - 1)));

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
		const items = filteredPaletteItems;
		if (e.key === 'ArrowDown') {
			e.preventDefault();
			paletteIndex = Math.min(paletteIndex + 1, items.length - 1);
		} else if (e.key === 'ArrowUp') {
			e.preventDefault();
			paletteIndex = Math.max(paletteIndex - 1, 0);
		} else if (e.key === 'Enter' && items[paletteSelectedIndex]) {
			e.preventDefault();
			showCommandPalette = false;
			items[paletteSelectedIndex].action();
		}
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
					<img src="/icons/swarmai-logo.svg" alt="SwarmAI" class="welcome-glyph" width="72" height="72" />
					<h2 class="welcome-title">Welcome to SwarmAI</h2>
					<p class="welcome-desc">Multi-agent orchestration for the desktop.<br/>Select a project or create a thread to begin.</p>
					<div class="shortcut-hints">
						<span class="hint"><kbd>&#x2318;</kbd><kbd>N</kbd> New Thread</span>
						<span class="hint"><kbd>&#x2318;</kbd><kbd>K</kbd> Command Palette</span>
						<span class="hint"><kbd>&#x2318;</kbd><kbd>,</kbd> Settings</span>
					</div>
				</div>
			{/if}
		</main>
	{/if}

	{#if showCommandPalette}
		<CommandPalette
			open={showCommandPalette}
			onClose={() => { showCommandPalette = false; }}
			onSelect={(id) => {
				const cmd = paletteCommands.find(c => c.id === id);
				if (cmd) cmd.action();
			}}
			items={paletteCommands.map((c) => ({
				id: c.id,
				label: c.label,
				icon: c.icon,
				category: c.category,
				keywords: c.keywords,
				action: () => {
					showCommandPalette = false;
					c.action();
				}
			}))}
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

	.empty-state {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		flex: 1;
		padding: 40px 20px;
		text-align: center;
		color: var(--text-secondary);
	}

	.welcome-glyph {
		margin-bottom: var(--space-6);
		opacity: 0.5;
	}

	.welcome-title {
		font-size: var(--font-size-2xl);
		font-weight: 700;
		color: var(--text-primary);
		margin: 0 0 var(--space-3);
		letter-spacing: -0.3px;
	}

	.welcome-desc {
		font-size: var(--font-size-md);
		color: var(--text-secondary);
		margin: 0 0 var(--space-6);
		line-height: var(--line-height-relaxed);
	}
</style>
