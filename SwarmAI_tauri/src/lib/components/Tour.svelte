<script lang="ts">
	import { onMount } from 'svelte';
	import HydraGlyph from './HydraGlyph.svelte';

	interface Props {
		onFinish: () => void;
	}

	let { onFinish }: Props = $props();

	type TourStep =
		| 'welcome'
		| 'threads'
		| 'composer'
		| 'hydra'
		| 'providers'
		| 'themes'
		| 'shortcuts'
		| 'complete';

	let currentStep = $state<TourStep>('welcome');
	let isAnimating = $state(false);

	const totalSteps = 7;

	const steps: { id: TourStep; title: string; subtitle: string; description: string; icon: string; accent: string }[] = [
		{
			id: 'welcome',
			title: 'Welcome to SwarmAI',
			subtitle: 'Multi-agent AI orchestration for the desktop',
			description: 'SwarmAI lets you chat with multiple AI providers, orchestrate parallel agent swarms with Hydra, and manage all your conversations in one place.',
			icon: 'sparkle',
			accent: 'var(--accent-1)',
		},
		{
			id: 'threads',
			title: 'Conversation Threads',
			subtitle: 'Organize your chats by project',
			description: 'Each conversation lives in a thread. Threads are grouped by project, can be pinned, archived, and searched. Use Cmd+N to start a new one instantly.',
			icon: 'threads',
			accent: '#3D8BFF',
		},
		{
			id: 'composer',
			title: 'The Composer',
			subtitle: 'Compose, review, and control',
			description: 'Write messages with auto-resizing text input. Adjust effort levels from Minimal to Maximum, attach files, and switch between Compose, Follow-ups, Approvals, and Questions tabs.',
			icon: 'compose',
			accent: '#34C46A',
		},
		{
			id: 'hydra',
			title: 'Hydra Swarms',
			subtitle: 'Multiple heads, multiple perspectives',
			description: 'Launch Hydra to spawn multiple AI agents that explore different approaches simultaneously. Each head works independently, then results merge for the best outcome.',
			icon: 'hydra',
			accent: '#A35BE0',
		},
		{
			id: 'providers',
			title: 'AI Providers',
			subtitle: 'Claude, Codex, GPT, and more',
			description: 'Connect to multiple AI providers including Anthropic, OpenAI, Google, and local models. Configure API keys, select models, and test connections right from settings.',
			icon: 'providers',
			accent: '#F25C9A',
		},
		{
			id: 'themes',
			title: 'Themes & Appearance',
			subtitle: 'Make it yours',
			description: 'Choose from Light, Dark, System, and a curated collection of developer themes like Tokyo Night, Dracula, Nord, and Catppuccin. Customize accent colors and font sizes too.',
			icon: 'theme',
			accent: '#E8B430',
		},
		{
			id: 'shortcuts',
			title: 'Keyboard Shortcuts',
			subtitle: 'Power user essentials',
			description: 'Navigate fast with Cmd+N for new threads, Cmd+K for the command palette, Cmd+, for settings, and Cmd+Enter to send. All shortcuts are customizable in settings.',
			icon: 'keys',
			accent: '#2BB5B0',
		},
	];

	let currentIndex = $derived(steps.findIndex((s) => s.id === currentStep));
	let progress = $derived(((currentIndex + 1) / totalSteps) * 100);
	let stepData = $derived(steps[currentIndex]);

	function next() {
		if (currentIndex < steps.length - 1) {
			isAnimating = true;
			setTimeout(() => {
				currentStep = steps[currentIndex + 1].id;
				isAnimating = false;
			}, 150);
		}
	}

	function prev() {
		if (currentIndex > 0) {
			isAnimating = true;
			setTimeout(() => {
				currentStep = steps[currentIndex - 1].id;
				isAnimating = false;
			}, 150);
		}
	}

	function skip() {
		onFinish();
	}

	function getIcon(type: string): string {
		switch (type) {
			case 'sparkle':
				return '<svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M12 2l2 4 4 1-3 3 1 4-4-2-4 2 1-4-3-3 4-1z"/><path d="M12 12l1.5 2 2 0.5-1.5 1.5 0.5 2-2-1-2 1 0.5-2L9.5 14.5 12 12z"/></svg>';
			case 'threads':
				return '<svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>';
			case 'compose':
				return '<svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/></svg>';
			case 'hydra':
				return '<svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M12 2l2 4 4 1-3 3 1 4-4-2-4 2 1-4-3-3 4-1z"/><path d="M12 12l1.5 2 2 0.5-1.5 1.5 0.5 2-2-1-2 1 0.5-2L9.5 14.5 12 12z"/></svg>';
			case 'providers':
				return '<svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>';
			case 'theme':
				return '<svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="12" cy="12" r="5"/><path d="M12 1v2m0 18v2M4.22 4.22l1.42 1.42m12.72 12.72 1.42 1.42M1 12h2m18 0h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"/></svg>';
			case 'keys':
				return '<svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="2" y="4" width="20" height="16" rx="2"/><path d="M6 8h.01M10 8h.01M14 8h.01M18 8h.01M8 12h.01M12 12h.01M16 12h.01M8 16h8"/></svg>';
			default:
				return '';
		}
	}

	function handleKeyDown(e: KeyboardEvent) {
		if (e.key === 'Escape') {
			onFinish();
		} else if (e.key === 'ArrowRight' || e.key === 'Enter') {
			next();
		} else if (e.key === 'ArrowLeft') {
			prev();
		}
	}

	onMount(() => {
		document.addEventListener('keydown', handleKeyDown);
		return () => document.removeEventListener('keydown', handleKeyDown);
	});
</script>

<div class="tour-overlay" class:animating={isAnimating}>
	<div class="tour-dialog" class:animating={isAnimating}>
		<!-- Progress bar -->
		<div class="progress-track">
			<div class="progress-fill" style="width: {progress}%"></div>
		</div>

		<!-- Step indicator dots -->
		<div class="step-dots">
			{#each steps as step, idx (step.id)}
				<button
					class="step-dot"
					class:active={idx === currentIndex}
					class:visited={idx < currentIndex}
					onclick={() => {
						if (idx <= currentIndex) {
							isAnimating = true;
							setTimeout(() => {
								currentStep = step.id;
								isAnimating = false;
							}, 100);
						}
					}}
					type="button"
				></button>
			{/each}
		</div>

		<!-- Content -->
		<div class="tour-content" class:animating={isAnimating}>
			<div class="icon-wrapper" style="background: {stepData.accent}20; color: {stepData.accent}">
				{@html getIcon(stepData.icon)}
			</div>

			<h2 class="tour-title">{stepData.title}</h2>
			<p class="tour-subtitle">{stepData.subtitle}</p>
			<p class="tour-description">{stepData.description}</p>

			<!-- Hydra demo for hydra step -->
			{#if currentStep === 'hydra'}
				<div class="hydra-demo">
					<HydraGlyph size={40} state="running" animating={true} />
					<div class="hydra-heads-preview">
						{#each [0, 1, 2] as i}
							{@const names = ['Hank', 'Ada', 'Remy']}
							{@const colors = ['#FF8A3D', '#34C46A', '#2BB5B0']}
							<div class="demo-head" style="border-color: {colors[i]}">
								<span class="demo-head-name">{names[i]}</span>
								<span class="demo-head-status">thinking…</span>
							</div>
						{/each}
					</div>
				</div>
			{/if}

			<!-- Theme preview for themes step -->
			{#if currentStep === 'themes'}
				<div class="theme-demo">
					{#each [
						{ name: 'Dark', bg: '1a1a2e', accent: '#007aff' },
						{ name: 'Light', bg: 'f5f5f7', accent: '#007aff' },
						{ name: 'Tokyo', bg: '1a1b26', accent: '#7aa2f7' },
						{ name: 'Mocha', bg: '1e1e2e', accent: '#cba6f7' },
					] as theme}
						<div class="theme-chip" style="background: {theme.bg}; --chip-accent: {theme.accent}">
							<span class="chip-dot"></span>
							<span class="chip-name">{theme.name}</span>
						</div>
					{/each}
				</div>
			{/if}

			<!-- Shortcut preview -->
			{#if currentStep === 'shortcuts'}
				<div class="shortcuts-demo">
					{#each [
						{ keys: ['⌘', 'N'], label: 'New Thread' },
						{ keys: ['⌘', 'K'], label: 'Command Palette' },
						{ keys: ['⌘', ','], label: 'Settings' },
						{ keys: ['⌘', 'Enter'], label: 'Send Message' },
					] as sc}
						<div class="shortcut-row">
							<div class="shortcut-keys">
								{#each sc.keys as key}
									<kbd>{key}</kbd>
								{/each}
							</div>
							<span class="shortcut-label">{sc.label}</span>
						</div>
					{/each}
				</div>
			{/if}
		</div>

		<!-- Actions -->
		<div class="tour-actions">
			<button class="skip-btn" onclick={skip} type="button">
				Skip tour
			</button>

			<div class="nav-buttons">
				<button
					class="nav-btn prev"
					onclick={prev}
					disabled={currentIndex === 0}
					type="button"
				>
					<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
						<path d="M15 18l-6-6 6-6"/>
					</svg>
					Back
				</button>

				{#if currentIndex === steps.length - 1}
					<button class="nav-btn next primary" onclick={onFinish} type="button">
						Get Started
						<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
							<path d="M5 12h14M12 5l7 7-7 7"/>
						</svg>
					</button>
				{:else}
					<button class="nav-btn next" onclick={next} type="button">
						Next
						<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
							<path d="M9 18l6-6-6-6"/>
						</svg>
					</button>
				{/if}
			</div>
		</div>
	</div>
</div>

<style>
	.tour-overlay {
		position: fixed;
		inset: 0;
		background: rgba(0, 0, 0, 0.6);
		backdrop-filter: blur(8px);
		display: flex;
		align-items: center;
		justify-content: center;
		z-index: 2000;
		animation: fade-in 0.2s ease-out;
	}

	@keyframes fade-in {
		from { opacity: 0; }
		to { opacity: 1; }
	}

	.tour-dialog {
		width: 480px;
		max-width: calc(100vw - 32px);
		background: var(--surface-2);
		border: var(--border-1) var(--border-color-1);
		border-radius: var(--radius-xl);
		box-shadow: 0 24px 80px rgba(0, 0, 0, 0.4);
		display: flex;
		flex-direction: column;
		overflow: hidden;
		animation: dialog-in 0.3s cubic-bezier(0.16, 1, 0.3, 1);
	}

	@keyframes dialog-in {
		from { transform: scale(0.92) translateY(20px); opacity: 0; }
		to { transform: scale(1) translateY(0); opacity: 1; }
	}

	/* Progress */
	.progress-track {
		height: 3px;
		background: var(--surface-3);
		flex-shrink: 0;
	}

	.progress-fill {
		height: 100%;
		background: linear-gradient(90deg, var(--accent-1), var(--accent-2));
		border-radius: var(--radius-full);
		transition: width 0.4s cubic-bezier(0.16, 1, 0.3, 1);
	}

	.step-dots {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 6px;
		padding: var(--space-3) var(--space-4) 0;
	}

	.step-dot {
		width: 8px;
		height: 8px;
		border-radius: 50%;
		border: none;
		background: var(--surface-3);
		cursor: pointer;
		transition: all 0.3s ease;
		padding: 0;
	}

	.step-dot.active {
		width: 24px;
		border-radius: 4px;
		background: var(--accent-1);
	}

	.step-dot.visited {
		background: var(--accent-3);
	}

	.step-dot:not(.active):hover {
		background: var(--surface-4);
	}

	/* Content */
	.tour-content {
		padding: var(--space-6) var(--space-8);
		display: flex;
		flex-direction: column;
		align-items: center;
		text-align: center;
		gap: var(--space-4);
	}

	.icon-wrapper {
		width: 64px;
		height: 64px;
		border-radius: var(--radius-xl);
		display: flex;
		align-items: center;
		justify-content: center;
	}

	.tour-title {
		font-size: 22px;
		font-weight: 700;
		color: var(--text-primary);
		margin: 0;
		letter-spacing: -0.3px;
	}

	.tour-subtitle {
		font-size: var(--font-size-md);
		color: var(--accent-1);
		font-weight: 500;
		margin: 0;
	}

	.tour-description {
		font-size: var(--font-size-sm);
		line-height: 1.6;
		color: var(--text-secondary);
		margin: 0;
		max-width: 380px;
	}

	/* Hydra demo */
	.hydra-demo {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-4);
		padding: var(--space-4);
		background: var(--surface-3);
		border-radius: var(--radius-lg);
		width: 100%;
	}

	.hydra-heads-preview {
		display: flex;
		gap: var(--space-2);
	}

	.demo-head {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 4px;
		padding: 8px 12px;
		background: var(--surface-2);
		border: var(--border-1) var(--border-color-1);
		border-radius: var(--radius-md);
		min-width: 70px;
	}

	.demo-head-name {
		font-size: 11px;
		font-weight: 600;
	}

	.demo-head-status {
		font-size: 10px;
		color: var(--text-tertiary);
		font-family: var(--font-mono);
	}

	/* Theme demo */
	.theme-demo {
		display: flex;
		gap: var(--space-3);
		flex-wrap: wrap;
		justify-content: center;
	}

	.theme-chip {
		display: flex;
		align-items: center;
		gap: 6px;
		padding: 6px 12px;
		border-radius: var(--radius-full);
		border: 1.5px solid var(--border-color-1);
	}

	.chip-dot {
		width: 10px;
		height: 10px;
		border-radius: 50%;
		background: var(--chip-accent);
	}

	.chip-name {
		font-size: 11px;
		font-weight: 500;
		color: var(--text-secondary);
	}

	/* Shortcut demo */
	.shortcuts-demo {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		width: 100%;
		max-width: 320px;
	}

	.shortcut-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 8px 14px;
		background: var(--surface-3);
		border-radius: var(--radius-sm);
	}

	.shortcut-keys {
		display: flex;
		align-items: center;
		gap: 4px;
	}

	.shortcut-keys kbd {
		padding: 2px 8px;
		border: var(--border-1) var(--border-color-1);
		border-radius: var(--radius-sm);
		font-family: var(--font-mono);
		font-size: 11px;
		background: var(--surface-2);
		color: var(--text-primary);
		min-width: 22px;
		text-align: center;
	}

	.shortcut-label {
		font-size: var(--font-size-xs);
		color: var(--text-secondary);
	}

	/* Actions */
	.tour-actions {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: var(--space-4) var(--space-8) var(--space-6);
		border-top: var(--border-1) var(--border-color-2);
	}

	.skip-btn {
		border: none;
		background: none;
		color: var(--text-tertiary);
		font-size: var(--font-size-sm);
		cursor: pointer;
		padding: 4px 8px;
		border-radius: var(--radius-sm);
		transition: color var(--transition-fast);
	}

	.skip-btn:hover {
		color: var(--text-primary);
	}

	.nav-buttons {
		display: flex;
		align-items: center;
		gap: var(--space-2);
	}

	.nav-btn {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		padding: 8px 16px;
		border: var(--border-1) var(--border-color-1);
		background: transparent;
		border-radius: var(--radius-md);
		font-size: var(--font-size-sm);
		font-weight: 500;
		color: var(--text-secondary);
		cursor: pointer;
		transition: all var(--transition-fast);
	}

	.nav-btn:hover:not(:disabled) {
		background: var(--surface-3);
		color: var(--text-primary);
	}

	.nav-btn:disabled {
		opacity: 0.3;
		cursor: not-allowed;
	}

	.nav-btn.primary {
		background: var(--accent-1);
		color: var(--text-inverse);
		border-color: var(--accent-1);
	}

	.nav-btn.primary:hover {
		background: var(--accent-2);
		border-color: var(--accent-2);
	}
</style>
