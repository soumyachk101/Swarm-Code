<script lang="ts">
	import { onMount } from 'svelte';
	import { appStore, updateSettings } from '$lib/stores/appStore';

	let settings = $derived($appStore.settings);
	let canvasInfinite = $state(false);
	let defaultEffort = $state<'minimal' | 'low' | 'medium' | 'high' | 'maximal'>('medium');
	let allowEmptyCommits = $state(false);
	let commitSigning = $state(false);
	let pruneOnFetch = $state(true);
	let pushAutoSetupRemote = $state(false);
	let statusBarVisible = $state(false);
	let onboardingStep = $state(0);
	let onboardingComplete = $state(false);
	let onboardingStepIndex = $derived(onboardingComplete ? 3 : Math.max(0, onboardingStep));

	onMount(() => {
		if (settings) {
			canvasInfinite = settings.canvasInfinite ?? false;
			defaultEffort = settings.defaultEffort ?? 'medium';
			allowEmptyCommits = settings.allowEmptyCommits ?? false;
			commitSigning = settings.commitSigning ?? false;
			pruneOnFetch = settings.pruneOnFetch ?? true;
			pushAutoSetupRemote = settings.pushAutoSetupRemote ?? false;
			statusBarVisible = settings.statusBarVisible ?? false;
			onboardingComplete = settings.onboardingComplete ?? false;
			onboardingStep = settings.onboardingStep ?? 0;
		}
	});

	function handleSave() {
		if (!settings) return;
		updateSettings({
			canvasInfinite,
			defaultEffort,
			allowEmptyCommits,
			commitSigning,
			pruneOnFetch,
			pushAutoSetupRemote,
			statusBarVisible,
			onboardingComplete,
			onboardingStep
		});
	}
</script>

<div class="settings-page">
	<h2 class="page-title">Source Control</h2>
	<p class="page-description">Configure Git and version control behavior.</p>

	<div class="settings-section">
		<h3 class="section-title">Git Commits</h3>
		<div class="settings-group">
			<div class="setting-item">
				<div class="setting-info">
					<label class="setting-label">Allow Empty Commits</label>
					<p class="setting-description">Allow creating commits with no changes</p>
				</div>
				<button
					class="toggle {allowEmptyCommits ? 'active' : ''}"
					onclick={() => allowEmptyCommits = !allowEmptyCommits}
					aria-label="Toggle allow empty commits"
				>
					<div class="toggle-thumb"></div>
				</button>
			</div>

			<div class="setting-item">
				<div class="setting-info">
					<label class="setting-label">Commit Signing</label>
					<p class="setting-description">Sign commits with GPG key</p>
				</div>
				<button
					class="toggle {commitSigning ? 'active' : ''}"
					onclick={() => commitSigning = !commitSigning}
					aria-label="Toggle commit signing"
				>
					<div class="toggle-thumb"></div>
				</button>
			</div>
		</div>
	</div>

	<div class="settings-section">
		<h3 class="section-title">Fetch & Push</h3>
		<div class="settings-group">
			<div class="setting-item">
				<div class="setting-info">
					<label class="setting-label">Prune on Fetch</label>
					<p class="setting-description">Remove remote-tracking branches that no longer exist</p>
				</div>
				<button
					class="toggle {pruneOnFetch ? 'active' : ''}"
					onclick={() => pruneOnFetch = !pruneOnFetch}
					aria-label="Toggle prune on fetch"
				>
					<div class="toggle-thumb"></div>
				</button>
			</div>

			<div class="setting-item">
				<div class="setting-info">
					<label class="setting-label">Push Auto Setup Remote</label>
					<p class="setting-description">Automatically set upstream on first push</p>
				</div>
				<button
					class="toggle {pushAutoSetupRemote ? 'active' : ''}"
					onclick={() => pushAutoSetupRemote = !pushAutoSetupRemote}
					aria-label="Toggle push auto setup remote"
				>
					<div class="toggle-thumb"></div>
				</button>
			</div>
		</div>
	</div>

	<div class="settings-section">
		<h3 class="section-title">Pull Request Titles</h3>
		<div class="settings-group">
			<div class="setting-item">
				<div class="setting-info">
					<label class="setting-label">Auto-generate PR Titles</label>
					<p class="setting-description">Use AI to suggest pull request titles</p>
				</div>
				<button
					class="toggle {statusBarVisible ? 'active' : ''}"
					onclick={() => statusBarVisible = !statusBarVisible}
					aria-label="Toggle auto-generate PR titles"
				>
					<div class="toggle-thumb"></div>
				</button>
			</div>
		</div>
	</div>
</div>

<style>
	.settings-page {
		display: flex;
		flex-direction: column;
		gap: 1.5rem;
		padding: 2rem;
		max-width: 720px;
	}
	.page-title {
		font-size: 1.5rem;
		font-weight: 600;
		margin: 0;
	}
	.page-description {
		color: var(--text-secondary);
		margin: 0;
		font-size: 0.875rem;
	}
	.settings-section {
		display: flex;
		flex-direction: column;
		gap: 0.75rem;
	}
	.section-title {
		font-size: 0.75rem;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--text-secondary);
		margin: 0;
	}
	.settings-group {
		display: flex;
		flex-direction: column;
		gap: 1px;
		background: var(--border);
		border-radius: 8px;
		overflow: hidden;
		border: 1px solid var(--border);
	}
	.setting-item {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 0.875rem 1rem;
		background: var(--surface-2);
		gap: 1rem;
	}
	.setting-info {
		display: flex;
		flex-direction: column;
		gap: 0.125rem;
	}
	.setting-label {
		font-size: 0.8125rem;
		font-weight: 500;
	}
	.setting-description {
		font-size: 0.75rem;
		color: var(--text-secondary);
		margin: 0;
	}
	.toggle {
		position: relative;
		width: 36px;
		height: 20px;
		border-radius: 10px;
		border: none;
		cursor: pointer;
		background: var(--border);
		padding: 0;
		flex-shrink: 0;
		transition: background 0.2s;
	}
	.toggle.active {
		background: var(--accent, #007aff);
	}
	.toggle-thumb {
		position: absolute;
		top: 2px;
		left: 2px;
		width: 16px;
		height: 16px;
		border-radius: 50%;
		background: white;
		box-shadow: 0 1px 3px rgba(0,0,0,0.2);
		transition: transform 0.2s;
	}
	.toggle.active .toggle-thumb {
		transform: translateX(16px);
	}
</style>
