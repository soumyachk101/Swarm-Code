<script lang="ts">
	import { onMount } from 'svelte';

	// ---------------------------------------------------------------------------
	// Version: read from package.json
	// ---------------------------------------------------------------------------

	let appVersion = $state('1.0.0');
	let appName = $state('SwarmAI');
	let isChecking = $state(false);
	let updateStatus = $state<'idle' | 'checking' | 'up-to-date' | 'available' | 'error'>('idle');
	let updateMessage = $state('');
	let changelogExpanded = $state(false);

	onMount(async () => {
		try {
			const res = await fetch('/package.json');
			if (res.ok) {
				const pkg = await res.json<{ version: string; name: string }>();
				appVersion = pkg.version;
				appName = pkg.name;
			}
		} catch {
			// Use defaults
		}
	});

	async function handleCheckUpdate() {
		isChecking = true;
		updateStatus = 'checking';
		updateMessage = '';

		try {
			// TODO: Wire up to actual update endpoint when available
			// For now, simulate a quick check
			await new Promise((r) => setTimeout(r, 1500));
			updateStatus = 'up-to-date';
			updateMessage = `You're on the latest version (${appVersion})`;
		} catch (e) {
			updateStatus = 'error';
			updateMessage = 'Failed to check for updates';
		} finally {
			isChecking = false;
		}
	}

	const changelogEntries = [
		{ version: appVersion, date: '2025-01', changes: ['Initial Tauri port of SwarmAI', 'Hydra multi-agent support', 'Provider registry for Codex, Claude, Cursor, DeepSeek, Meta, Grok', 'Timeline and session management', 'Terminal integration', 'Keyboard shortcut customization'] },
	];
</script>

<div class="about-view">
	<div class="settings-page-header">
		<h2 class="settings-page-title">About</h2>
		<p class="settings-page-desc">Application information and updates</p>
	</div>

	<div class="settings-page">
		<!-- App Info -->
		<section class="settings-section">
			<div class="about-hero">
				<div class="about-icon">
					<img src="/icons/swarmai-logo.svg" alt="SwarmAI" width="64" height="64" />
				</div>
				<div class="about-meta">
					<h3 class="about-name">{appName}</h3>
					<span class="about-version">Version {appVersion}</span>
				</div>
			</div>

			<button
				class="update-btn"
				class:checking={isChecking}
				onclick={handleCheckUpdate}
				disabled={isChecking}
			>
				{#if isChecking}
					<div class="btn-spinner"></div>
					Checking…
				{:else}
					<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
						<polyline points="23 4 23 10 17 10"/>
						<path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/>
					</svg>
					Check for Updates
				{/if}
			</button>

			{#if updateStatus !== 'idle'}
				<div class="update-status" class:success={updateStatus === 'up-to-date'} class:error={updateStatus === 'error'}>
					<span class="update-status-icon">
						{#if updateStatus === 'up-to-date'}✓{/if}
						{#if updateStatus === 'available'}⬆️{/if}
						{#if updateStatus === 'error'}✗{/if}
						{#if updateStatus === 'checking'}⏳{/if}
					</span>
					<span class="update-status-text">{updateMessage}</span>
				</div>
			{/if}
		</section>

		<!-- Changelog -->
		<section class="settings-section">
			<h3 class="settings-section-title">Changelog</h3>
			<div class="changelog">
				{#each changelogEntries as entry (entry.version)}
					<div class="changelog-entry">
						<div class="changelog-header">
							<span class="changelog-version">v{entry.version}</span>
							<span class="changelog-date">{entry.date}</span>
						</div>
						<ul class="changelog-list">
							{#each entry.changes as change (change)}
								<li class="changelog-item">{change}</li>
							{/each}
						</ul>
					</div>
				{/each}
			</div>
		</section>

		<!-- Links -->
		<section class="settings-section">
			<h3 class="settings-section-title">Links</h3>
			<div class="about-links">
				<a href="https://github.com" target="_blank" rel="noopener" class="about-link">
					<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor">
						<path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/>
					</svg>
					GitHub Repository
				</a>
				<a href="#" class="about-link">
					<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
						<path d="M12 20h9"/>
						<path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/>
					</svg>
					Release Notes
				</a>
			</div>
		</section>
	</div>
</div>

<style>
	.about-view {
		display: flex;
		flex-direction: column;
		gap: var(--space-6);
		width: 100%;
	}

	.settings-page-header {
		margin-bottom: var(--space-2);
	}

	.settings-page-title {
		font-size: var(--font-size-xl);
		font-weight: 700;
		color: var(--text-primary);
	}

	.settings-page-desc {
		font-size: var(--font-size-sm);
		color: var(--text-tertiary);
		margin-top: var(--space-1);
	}

	/* ── Sections ── */

	.settings-page {
		display: flex;
		flex-direction: column;
		gap: var(--space-6);
	}

	.settings-section {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		padding-bottom: var(--space-4);
		border-bottom: var(--border-1) var(--border-color-2);
	}

	.settings-section:last-of-type {
		border-bottom: none;
	}

	.settings-section-title {
		font-size: var(--font-size-sm);
		font-weight: 600;
		color: var(--text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.5px;
		padding-bottom: var(--space-2);
		border-bottom: var(--border-1) var(--border-color-2);
	}

	/* ── Hero ── */

	.about-hero {
		display: flex;
		align-items: center;
		gap: var(--space-4);
		padding: var(--space-4);
		background: var(--surface-2);
		border: var(--border-1) var(--border-color-1);
		border-radius: var(--radius-lg);
	}

	.about-icon {
		width: 64px;
		height: 64px;
		flex-shrink: 0;
	}

	.about-icon svg {
		width: 100%;
		height: 100%;
	}

	.about-meta {
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}

	.about-name {
		font-size: var(--font-size-lg);
		font-weight: 700;
		color: var(--text-primary);
	}

	.about-version {
		font-size: var(--font-size-sm);
		color: var(--text-tertiary);
		font-family: var(--font-mono);
	}

	/* ── Update Button ── */

	.update-btn {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		gap: var(--space-2);
		padding: 8px 20px;
		border: var(--border-1) var(--border-color-1);
		background: var(--surface-2);
		border-radius: var(--radius-md);
		color: var(--text-primary);
		font-size: var(--font-size-sm);
		font-weight: 500;
		cursor: pointer;
		transition: all var(--transition-fast);
		font-family: var(--font-system);
	}

	.update-btn:hover:not(:disabled) {
		background: var(--surface-3);
		border-color: var(--accent-1);
	}

	.update-btn:disabled {
		opacity: 0.6;
		cursor: not-allowed;
	}

	.btn-spinner {
		width: 16px;
		height: 16px;
		border: 2px solid var(--surface-4);
		border-top-color: var(--accent-1);
		border-radius: 50%;
		animation: spin 0.7s linear infinite;
	}

	@keyframes spin {
		to { transform: rotate(360deg); }
	}

	/* ── Update Status ── */

	.update-status {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		padding: var(--space-2) var(--space-3);
		border-radius: var(--radius-md);
		font-size: var(--font-size-sm);
	}

	.update-status.success {
		background: rgba(52, 199, 89, 0.06);
		color: var(--success);
	}

	.update-status.error {
		background: rgba(255, 59, 48, 0.06);
		color: var(--danger);
	}

	.update-status-icon {
		font-weight: 700;
	}

	/* ── Changelog ── */

	.changelog {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
	}

	.changelog-entry {
		padding: var(--space-3) 0;
		border-bottom: var(--border-1) var(--border-color-2);
	}

	.changelog-entry:last-child {
		border-bottom: none;
	}

	.changelog-header {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		margin-bottom: var(--space-2);
	}

	.changelog-version {
		font-size: var(--font-size-sm);
		font-weight: 600;
		color: var(--accent-1);
		font-family: var(--font-mono);
	}

	.changelog-date {
		font-size: 11px;
		color: var(--text-tertiary);
	}

	.changelog-list {
		list-style: none;
		padding: 0;
		margin: 0;
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}

	.changelog-item {
		font-size: var(--font-size-sm);
		color: var(--text-secondary);
		padding-left: var(--space-4);
		position: relative;
		line-height: var(--line-height-normal);
	}

	.changelog-item::before {
		content: '•';
		position: absolute;
		left: 0;
		color: var(--accent-1);
		font-weight: 700;
	}

	/* ── About Links ── */

	.about-links {
		display: flex;
		gap: var(--space-3);
	}

	.about-link {
		display: inline-flex;
		align-items: center;
		gap: var(--space-2);
		padding: 6px 14px;
		background: var(--surface-2);
		border: var(--border-1) var(--border-color-1);
		border-radius: var(--radius-md);
		color: var(--text-secondary);
		font-size: var(--font-size-sm);
		text-decoration: none;
		transition: all var(--transition-fast);
	}

	.about-link:hover {
		background: var(--surface-3);
		border-color: var(--accent-3);
		color: var(--accent-1);
	}
</style>
