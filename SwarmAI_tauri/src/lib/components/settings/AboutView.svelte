<script lang="ts">
	import { invoke } from '@tauri-apps/api/core';

	let version = $state('1.0.0');
	let appName = $state('SwarmAI');
	let buildChannel = $state('development');
	let rustVersion = $state('');
	let tauriVersion = $state('');
	let svelteVersion = $state('');

	$effect(() => {
		loadInfo();
	});

	async function loadInfo() {
		try {
			const info = await invoke<any>('get_app_info');
			if (info) {
				version = info.version || version;
				appName = info.name || appName;
				buildChannel = info.buildChannel || buildChannel;
				rustVersion = info.rustVersion || '';
				tauriVersion = info.tauriVersion || '';
			}
		} catch (e) {
			console.error('Failed to load app info:', e);
		}
	}

	function openUrl(url: string) {
		window.open(url, '_blank');
	}
</script>

<div class="about-view">
	<div class="about-card">
		<div class="app-glyph">
			<svg width="64" height="64" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
				<path d="M12 2l2 4 4 1-3 3 1 4-4-2-4 2 1-4-3-3 4-1z"/>
				<path d="M12 12l1.5 2 2 0.5-1.5 1.5 0.5 2-2-1-2 1 0.5-2L9.5 14.5 12 12z"/>
			</svg>
		</div>
		<h1 class="app-name">{appName}</h1>
		<p class="app-tagline">Multi-agent AI orchestration for the desktop</p>
		<p class="app-version">Version {version} <span class="channel-badge">{buildChannel}</span></p>

		<div class="info-section">
			<h2 class="section-heading">About</h2>
			<p class="about-description">
				SwarmAI is a desktop AI client that orchestrates multiple models and approaches in parallel.
				Launch a Hydra swarm to explore different strategies, manage threads with rich timeline views,
				and let the agent work autonomously across your projects.
			</p>
		</div>

		<div class="info-section">
			<h2 class="section-heading">Runtime</h2>
			<div class="info-grid">
				{#if tauriVersion}
					<div class="info-item">
						<span class="info-label">Tauri</span>
						<span class="info-value">{tauriVersion}</span>
					</div>
				{/if}
				{#if rustVersion}
					<div class="info-item">
						<span class="info-label">Rust</span>
						<span class="info-value">{rustVersion}</span>
					</div>
				{/if}
				<div class="info-item">
					<span class="info-label">Svelte</span>
					<span class="info-value">5.0</span>
				</div>
				<div class="info-item">
					<span class="info-label">TypeScript</span>
					<span class="info-value">5.x</span>
				</div>
			</div>
		</div>

		<div class="info-section">
			<h2 class="section-heading">Links</h2>
			<div class="links-grid">
				<button class="link-btn" onclick={() => openUrl('https://github.com')}>
					<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
						<path d="M9 19c-5 1.5-5-2.5-7-3m14 6v-3.87a3.37 3.37 0 0 0-.94-2.61c3.14-.35 6.44-1.54 6.44-7A5.44 5.44 0 0 0 20 4.77 5.07 5.07 0 0 0 19.91 1S18.73.65 16 2.48a13.38 13.38 0 0 0-7 0C6.27.65 5.09 1 5.09 1A5.07 5.07 0 0 0 5 4.77a5.44 5.44 0 0 0-1.5 3.78c0 5.42 3.3 6.61 6.44 7A3.37 3.37 0 0 0 9 18.13V22"/>
					</svg>
					Source Code
				</button>
				<button class="link-btn" onclick={() => openUrl('https://docs.example')}>
					<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
						<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/>
						<polyline points="14,2 14,8 20,8"/>
					</svg>
					Documentation
				</button>
				<button class="link-btn" onclick={() => openUrl('https://twitter.com')}>
					<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
						<path d="M23 3a10.9 10.9 0 0 1-3.14 1.53 4.48 4.48 0 0 0-7.86 3v1A10.66 10.66 0 0 1 3 4s-4 9 5 13a11.64 11.64 0 0 1-7 2c9 5 20 0 20-11.5a4.5 4.5 0 0 0-.08-.83A7.72 7.72 0 0 0 23 3z"/>
					</svg>
					Twitter
				</button>
			</div>
		</div>

		<div class="info-section">
			<h2 class="section-heading">License & Credits</h2>
			<p class="license-text">
				SwarmAI is open source under the MIT License. Made with care by the SwarmAI team.
			</p>
		</div>
	</div>
</div>

<style>
	.about-view {
		height: 100%;
		overflow-y: auto;
		padding: var(--space-6) var(--space-8);
		display: flex;
		justify-content: center;
	}

	.about-card {
		max-width: 540px;
		width: 100%;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-4);
		padding: var(--space-6);
	}

	.app-glyph {
		display: flex;
		align-items: center;
		justify-content: center;
		width: 96px;
		height: 96px;
		border-radius: var(--radius-xl);
		background: linear-gradient(135deg, var(--accent-1), var(--accent-2));
		color: var(--text-inverse);
		margin-bottom: var(--space-2);
	}

	.app-name {
		font-size: 28px;
		font-weight: 700;
		color: var(--text-primary);
		letter-spacing: -0.5px;
	}

	.app-tagline {
		font-size: var(--font-size-md);
		color: var(--text-secondary);
		text-align: center;
	}

	.app-version {
		font-size: var(--font-size-sm);
		color: var(--text-tertiary);
		display: flex;
		align-items: center;
		gap: var(--space-2);
	}

	.channel-badge {
		font-size: 10px;
		font-weight: 500;
		padding: 1px 8px;
		background: var(--surface-3);
		color: var(--text-secondary);
		border-radius: var(--radius-full);
		text-transform: uppercase;
		letter-spacing: 0.3px;
	}

	.info-section {
		width: 100%;
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		padding: var(--space-3) 0;
	}

	.section-heading {
		font-size: var(--font-size-sm);
		font-weight: 600;
		color: var(--text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.5px;
	}

	.about-description {
		font-size: var(--font-size-sm);
		line-height: var(--line-height-relaxed);
		color: var(--text-secondary);
		text-align: center;
	}

	.info-grid {
		display: grid;
		grid-template-columns: repeat(2, 1fr);
		gap: var(--space-3);
		width: 100%;
	}

	.info-item {
		display: flex;
		justify-content: space-between;
		padding: var(--space-2) var(--space-3);
		background: var(--surface-2);
		border: var(--border-1) var(--border-color-1);
		border-radius: var(--radius-sm);
	}

	.info-label {
		font-size: var(--font-size-xs);
		color: var(--text-tertiary);
	}

	.info-value {
		font-size: var(--font-size-xs);
		font-family: var(--font-mono);
		color: var(--text-primary);
	}

	.links-grid {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		width: 100%;
	}

	.link-btn {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		padding: 8px 14px;
		border: var(--border-1) var(--border-color-1);
		background: var(--surface-2);
		border-radius: var(--radius-sm);
		font-size: var(--font-size-sm);
		color: var(--text-primary);
		cursor: pointer;
		transition: all var(--transition-fast);
	}

	.link-btn:hover {
		background: var(--accent-3);
		border-color: var(--accent-1);
		color: var(--accent-1);
	}

	.license-text {
		font-size: var(--font-size-xs);
		color: var(--text-tertiary);
		font-style: italic;
		text-align: center;
	}
</style>
