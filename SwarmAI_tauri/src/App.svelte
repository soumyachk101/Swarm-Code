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
		const map: Record<string, string> = {
			system: 'system',
			light: 'light',
			dark: 'dark',
			catppuccin_mocha: 'catppuccin_mocha',
			catppuccin_latte: 'catppuccin_latte',
			dracula: 'dracula',
			tokyo_night: 'tokyo_night',
			nord: 'nord',
			gruvbox: 'gruvbox',
			gruvbox_light: 'gruvbox_light',
			one_dark: 'one_dark',
			everforest: 'everforest',
			kanagawa: 'kanagawa',
			rose_pine: 'rose_pine',
			solarized_dark: 'solarized_dark',
			solarized_light: 'solarized_light',
			github_dark: 'github_dark',
			github_light: 'github_light',
			ayu: 'ayu',
			night_owl: 'night_owl',
			monokai: 'monokai',
			claude: 'claude',
			claude_light: 'claude_light',
			codex: 'codex',
			cursor: 'cursor',
			matrix: 'matrix',
		};
		root.setAttribute('data-theme', map[theme] ?? 'light');
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

<div class="app-shell">
	{#if isFirstLaunch}
		<Tour onFinish={handleFinishTour} />
	{:else}
		<Sidebar
			bind:selectedThreadID
			bind:selectedProjectID
			bind:viewKind
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
				<ChatView
					thread={selectedThread}
					terminalVisible={terminalVisible}
					onToggleTerminal={() => terminalVisible = !terminalVisible}
				/>
				{#if terminalVisible}
					<TerminalPanel threadId={selectedThread.id} />
				{/if}
				<Composer thread={selectedThread} />
				{:else if selectedProjectID}
				<div class="empty-state project-empty">
					<div class="welcome-inner" style="gap: 16px;">
						<img src="/icons/swarmai-logo.svg" alt="SwarmAI" class="welcome-glyph" width="72" height="72" />
						<h2 class="welcome-title" style="font-size: 20px; font-weight: 600;">Project Selected</h2>
						<p class="welcome-desc" style="max-width: 320px;">Pick a thread or start a new one</p>
						<button class="welcome-action-btn" onclick={() => createNewThread()}>
							<svg width="14" height="14" viewBox="0 0 14 14" fill="none" xmlns="http://www.w3.org/2000/svg">
								<path d="M7 1V13M1 7H13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>
							</svg>
							New Thread
						</button>
					</div>
				</div>
			{:else}
				<div class="empty-state">
					<div class="welcome-inner">
						<div class="welcome-header">
							<img src="/icons/swarmai-logo.svg" alt="SwarmAI" class="welcome-glyph" width="104" height="104" />
							<h2 class="welcome-title">SwarmAI</h2>
							<p class="welcome-desc">The coding app by Soumya Chakraborty. A calm, native home for your coding agents.</p>
						</div>

						<div class="welcome-actions">
							<button class="welcome-action-btn" onclick={() => createNewThread()}>
								<svg width="14" height="14" viewBox="0 0 14 14" fill="none" xmlns="http://www.w3.org/2000/svg">
									<path d="M7 1V13M1 7H13" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>
								</svg>
								New Thread
							</button>
							<span class="welcome-action-hint">Or drop a folder anywhere in this window.</span>
						</div>

						<div class="shortcut-hints">
							<span class="hint"><kbd>&#x2318;</kbd><kbd>N</kbd> New Thread</span>
							<span class="hint"><kbd>&#x2318;</kbd><kbd>K</kbd> Command Palette</span>
							<span class="hint"><kbd>&#x2318;</kbd><kbd>,</kbd> Settings</span>
						</div>

						<div class="welcome-providers">
							<div class="provider-section-title">Providers</div>
							<div class="provider-card">
								{#each ($appStore.providers ?? []) as provider, i (i)}
									<div class="provider-row">
										<div class="provider-icon">
											<svg width="18" height="18" viewBox="0 0 18 18" fill="none">
												<circle cx="9" cy="9" r="7" stroke="currentColor" stroke-width="1.4"/>
												<path d="M9 5V9L11 11" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>
											</svg>
										</div>
										<div class="provider-info">
											<div class="provider-name">{provider.name}</div>
											<div class="provider-status-text">{provider.status_message ?? (provider.installed ? 'Ready' : 'Not installed')}</div>
										</div>
										{#if provider.installed && provider.authenticated}
											<div class="provider-checkmark connected">
												<svg width="18" height="18" viewBox="0 0 18 18" fill="none">
													<path d="M4 9L7.5 12.5L14 6" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>
												</svg>
											</div>
										{:else}
											<span class="provider-status-badge disconnected">
												{provider.installed ? 'Sign in' : 'Install'}
											</span>
										{/if}
									</div>
								{/each}
							</div>
						</div>
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
	/* Welcome screen — mirrors Swift WelcomeView (RootView) */
	.empty-state {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		flex: 1;
		padding: 48px;
		text-align: center;
		color: var(--text-secondary);
		/* detailSheet glass tint background */
		background: var(--surface-1);
		overflow-y: auto;
	}

	.welcome-inner {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 30px;
		max-width: 520px;
		width: 100%;
	}

	.welcome-header {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 14px;
	}

	.welcome-glyph {
		width: 104px;
		height: 104px;
		opacity: 0.9;
	}

	.welcome-title {
		font-size: 34px;
		font-weight: 600;
		color: var(--text-primary);
		margin: 0;
		letter-spacing: -0.5px;
	}

	.welcome-desc {
		font-size: 15px;
		line-height: 1.45;
		color: var(--text-secondary);
		margin: 0;
		max-width: 400px;
	}

	.welcome-actions {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 10px;
		width: 100%;
		max-width: 360px;
	}

	.welcome-action-btn {
		width: 100%;
		display: flex;
		align-items: center;
		justify-content: center;
		gap: var(--space-3);
		padding: 12px var(--space-6);
		/* Chrome glass capsule — mirrors Swift .glassProminent / chromeGlassCapsule() */
		backdrop-filter: blur(20px);
		-webkit-backdrop-filter: blur(20px);
		background: var(--accent-1);
		color: white;
		border: none;
		border-radius: var(--radius-lg);
		font-size: var(--font-size-md);
		font-weight: 500;
		cursor: pointer;
		transition: all var(--transition-fast);
		font-family: var(--font-system);
	}

	.welcome-action-btn:hover {
		background: var(--accent-2);
		transform: scale(1.02);
	}

	.welcome-action-btn:active {
		transform: scale(0.98);
	}

	.welcome-action-hint {
		font-size: 12px;
		color: var(--text-tertiary);
		margin-top: -4px;
	}

	/* Provider checklist card — mirrors Swift ChromeCard + ProviderChecklist */
	.welcome-providers {
		width: 100%;
		max-width: 480px;
	}

	.provider-section-title {
		font-size: 13px;
		font-weight: 600;
		color: var(--text-primary);
		text-align: left;
		margin-bottom: 10px;
	}

	.provider-card {
		display: flex;
		flex-direction: column;
		background: var(--surface-2);
		border: var(--border-1) var(--border-color-1);
		border-radius: var(--radius-lg);
		overflow: hidden;
	}

	.provider-row {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 11px 16px;
	}

	.provider-row + .provider-row {
		border-top: var(--border-1) var(--border-color-2);
	}

	.provider-icon {
		width: 22px;
		height: 22px;
		display: flex;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
		color: var(--text-primary);
	}

	.provider-info {
		flex: 1;
		min-width: 0;
	}

	.provider-name {
		font-size: 13px;
		font-weight: 400;
		color: var(--text-primary);
	}

	.provider-status-text {
		font-size: 11px;
		color: var(--text-tertiary);
		margin-top: 1px;
	}

	.provider-status-badge {
		font-size: 10px;
		font-weight: 500;
		padding: 2px 10px;
		border-radius: var(--radius-full);
		display: inline-flex;
		align-items: center;
		gap: 4px;
		flex-shrink: 0;
	}

	.provider-status-badge.connected {
		background: rgba(52, 199, 89, 0.12);
		color: var(--success);
	}

	.provider-status-badge.disconnected {
		background: rgba(255, 149, 0, 0.12);
		color: var(--warning);
	}

	.provider-checkmark {
		width: 18px;
		height: 18px;
		display: flex;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
	}

	.provider-checkmark.connected {
		color: var(--success);
	}

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
