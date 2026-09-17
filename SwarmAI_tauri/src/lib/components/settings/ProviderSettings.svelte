<script lang="ts">
	import { onMount } from 'svelte';
	import {
		getProviders,
		getModelsForProvider,
		testProvider,
		saveProvider,
		deleteProvider,
		getProviderCredits,
		refreshProviderStatus,
	} from '$lib/api/commands';
	import { providerIcon, providerShortName } from '$lib/icons';
	import type {
		Provider,
		ProviderKind,
		ProviderType,
		ModelInfo,
		ProviderTestResult,
		ProviderCredits,
		ProviderStatus,
	} from '$lib/types';
	import { ProviderKind as PK, PROVIDER_LABELS } from '$lib/types';

	// ---------------------------------------------------------------------------
	// All supported provider kinds
	// ---------------------------------------------------------------------------

	const ALL_PROVIDER_KINDS: { kind: ProviderKind; label: string; hasApiKey: boolean }[] = [
		{ kind: PK.Codex, label: 'Codex', hasApiKey: false },
		{ kind: PK.Claude, label: 'Claude', hasApiKey: false },
		{ kind: PK.Cursor, label: 'Cursor', hasApiKey: false },
		{ kind: PK.Opencode, label: 'OpenCode', hasApiKey: false },
		{ kind: PK.Grok, label: 'Grok', hasApiKey: true },
		{ kind: PK.Deepseek, label: 'DeepSeek', hasApiKey: true },
		{ kind: PK.Meta, label: 'Meta', hasApiKey: true },
		{ kind: PK.Devin, label: 'Devin', hasApiKey: false },
		{ kind: PK.Antigravity, label: 'Antigravity', hasApiKey: false },
		{ kind: PK.Copilot, label: 'Copilot', hasApiKey: false },
	];

	// ---------------------------------------------------------------------------
	// State
	// ---------------------------------------------------------------------------

	let providers = $state<Provider[]>([]);
	let isLoading = $state(true);
	let testingId = $state<string | null>(null);
	let expandingId = $state<string | null>(null);
	let expandedModels = $state<ModelInfo[]>([]);
	let expandedCredits = $state<ProviderCredits | null>(null);
	let expandedStatus = $state<ProviderStatus | null>(null);
	let isRefreshing = $state(false);

	// API key editing state
	let editingApiKeyId = $state<string | null>(null);
	let apiKeyInput = $state('');

	// Default provider state
	let selectedDefault = $state<string | null>(null);

	// ---------------------------------------------------------------------------
	// Load
	// ---------------------------------------------------------------------------

	onMount(() => {
		loadProviders();
	});

	async function loadProviders() {
		try {
			providers = await getProviders();
			selectedDefault = providers.find((p) => p.is_default)?.id ?? null;
		} catch (e) {
			console.error('Failed to load providers:', e);
		} finally {
			isLoading = false;
		}
	}

	// ---------------------------------------------------------------------------
	// Actions
	// ---------------------------------------------------------------------------

	async function handleTest(providerId: string) {
		testingId = providerId;
		try {
			const result: ProviderTestResult = await testProvider(providerId);
			// Update the provider in the list with any new model info
			if (result.models && result.models.length > 0) {
				providers = providers.map((p) =>
					p.id === providerId ? { ...p, models: result.models, status_message: result.message } : p,
				);
			}
			// Refresh status
			const status = await refreshProviderStatus(providerId);
			providers = providers.map((p) =>
				p.id === providerId ? { ...p, installed: true, authenticated: result.success, version: status.version ?? p.version } : p,
			);
		} catch (e) {
			console.error('Provider test failed:', e);
		} finally {
			testingId = null;
		}
	}

	async function handleExpand(providerId: string) {
		if (expandingId === providerId) {
			expandingId = null;
			expandedModels = [];
			expandedCredits = null;
			expandedStatus = null;
			return;
		}

		expandingId = providerId;
		expandedModels = [];
		expandedCredits = null;
		expandedStatus = null;

		try {
			const [models, credits, status] = await Promise.all([
				getModelsForProvider(providerId).catch(() => []),
				getProviderCredits(providerId).catch(() => null),
				refreshProviderStatus(providerId).catch(() => null),
			]);
			expandedModels = models;
			expandedCredits = credits;
			expandedStatus = status;
		} catch (e) {
			console.error('Failed to load provider details:', e);
		}
	}

	async function handleSaveApiKey(providerId: string) {
		try {
			await saveProvider({ id: providerId, api_key: apiKeyInput });
			providers = providers.map((p) =>
				p.id === providerId ? { ...p, api_key: apiKeyInput || null } : p,
			);
			editingApiKeyId = null;
			apiKeyInput = '';
		} catch (e) {
			console.error('Failed to save API key:', e);
		}
	}

	async function handleDelete(providerId: string) {
		if (!confirm('Remove this provider?')) return;
		try {
			await deleteProvider(providerId);
			providers = providers.filter((p) => p.id !== providerId);
			if (selectedDefault === providerId) {
				selectedDefault = providers[0]?.id ?? null;
			}
		} catch (e) {
			console.error('Failed to delete provider:', e);
		}
	}

	async function handleSetDefault(providerId: string) {
		selectedDefault = providerId;
		try {
			await saveProvider({ id: providerId, is_default: true });
			providers = providers.map((p) => ({
				...p,
				is_default: p.id === providerId,
			}));
		} catch (e) {
			console.error('Failed to set default provider:', e);
			// Revert
			selectedDefault = providers.find((p) => p.is_default)?.id ?? null;
		}
	}

	async function handleInstallProvider(kind: ProviderKind) {
		try {
			const saved = await saveProvider({
				kind,
				name: PROVIDER_LABELS[kind],
				provider_type: kind === PK.Deepseek || kind === PK.Grok || kind === PK.Meta
					? ProviderType.ApiKey
					: ProviderType.Cli,
				enabled: true,
			});
			providers = [...providers, saved];
		} catch (e) {
			console.error('Failed to install provider:', e);
		}
	}

	// ---------------------------------------------------------------------------
	// Helpers
	// ---------------------------------------------------------------------------

	function getProviderByKind(kind: ProviderKind): Provider | undefined {
		return providers.find((p) => p.kind === kind);
	}

	function statusLabel(p: Provider): string {
		if (p.authenticated) return 'Connected';
		if (p.installed) return 'Installed';
		return 'Not Set Up';
	}

	function statusClass(p: Provider): string {
		if (p.authenticated) return 'connected';
		if (p.installed) return 'installed';
		return 'disconnected';
	}

	function maskApiKey(key: string | null): string {
		if (!key) return '';
		if (key.length <= 8) return '••••••••';
		return key.slice(0, 4) + '••••' + key.slice(-4);
	}
</script>

<div class="provider-settings">
	<div class="settings-page-header">
		<h2 class="settings-page-title">Providers</h2>
		<p class="settings-page-desc">Manage your AI providers and model connections</p>
	</div>

	{#if isLoading}
		<div class="loading">
			<div class="spinner"></div>
		</div>
	{:else}
		<!-- Provider Cards Grid -->
		<div class="provider-grid">
			{#each ALL_PROVIDER_KINDS as item (item.kind)}
				{@const provider = getProviderByKind(item.kind)}
				<div class="provider-card">
					<div class="provider-card-top">
						<div class="provider-icon-wrap">
							{#if provider}
								<img
									src={providerIcon(item.kind)}
									alt={item.label}
									class="provider-icon-img"
								/>
							{:else}
								<span class="provider-icon-placeholder">{providerShortName(item.kind)}</span>
							{/if}
						</div>
						<div class="provider-info">
							<span class="provider-name">{item.label}</span>
							<span class="provider-type">
								{#if provider}
									{provider.provider_type}
								{:else}
									Not configured
								{/if}
							</span>
						</div>
						{#if provider}
							<span class="status-badge {statusClass(provider)}">
								{statusLabel(provider)}
							</span>
						{:else}
							<span class="status-badge not-configured">Not configured</span>
						{/if}
					</div>

					{#if provider}
						<!-- Model List (collapsed preview) -->
						<div class="provider-models-preview">
							{#if provider.models && provider.models.length > 0}
								<div class="model-tags">
									{#each provider.models.slice(0, 4) as model (model.id)}
										<span class="model-tag">{model.name ?? model.id}</span>
									{/each}
									{#if provider.models.length > 4}
										<span class="model-tag more">+{provider.models.length - 4}</span>
									{/if}
								</div>
							{:else}
								<span class="no-models">No models loaded</span>
							{/if}
						</div>

						<!-- Expanded Detail -->
						{#if expandingId === provider.id}
							<div class="provider-detail-panel">
								{#if expandedModels.length > 0}
									<div class="detail-section">
										<span class="detail-label">Models</span>
										<div class="model-list">
											{#each expandedModels as model (model.id)}
												<div class="model-item" class:default={model.is_default}>
													<span class="model-name">{model.name ?? model.id}</span>
													<span class="model-detail">{model.detail ?? ''}</span>
													{#if model.is_default}
														<span class="model-default-badge">default</span>
													{/if}
												</div>
											{/each}
										</div>
									</div>
								{/if}

								{#if expandedCredits}
									<div class="detail-section">
										<span class="detail-label">Credits</span>
										<span class="credits-value">
											{#if expandedCredits.is_unlimited}
												Unlimited
											{:else if expandedCredits.remaining !== null}
												{expandedCredits.remaining?.toLocaleString()} {expandedCredits.unit ?? 'tokens'} remaining
											{:else}
												No credit data
											{/if}
										</span>
										{#if expandedCredits.resets_at}
											<span class="credits-reset">Resets: {new Date(expandedCredits.resets_at).toLocaleDateString()}</span>
										{/if}
									</div>
								{/if}

								{#if provider.status_message}
									<div class="detail-section">
										<span class="detail-label">Status</span>
										<span class="status-message">{provider.status_message}</span>
									</div>
								{/if}
							</div>
						{/if}

						<!-- Actions -->
						<div class="provider-actions">
							{#if item.hasApiKey}
								{#if editingApiKeyId === provider.id}
									<div class="api-key-edit">
										<input
											type="password"
											class="api-key-input"
											placeholder="Enter API key…"
											value={apiKeyInput}
											oninput={(e) => apiKeyInput = e.currentTarget.value}
											onkeydown={(e) => { if (e.key === 'Enter') handleSaveApiKey(provider.id); if (e.key === 'Escape') { editingApiKeyId = null; apiKeyInput = ''; } }}
										/>
										<button class="btn btn-xs btn-primary" onclick={() => handleSaveApiKey(provider.id)}>Save</button>
										<button class="btn btn-xs btn-secondary" onclick={() => { editingApiKeyId = null; apiKeyInput = ''; }}>Cancel</button>
									</div>
								{:else}
									<button class="btn btn-xs btn-secondary" onclick={() => { editingApiKeyId = provider.id; apiKeyInput = provider.api_key ?? ''; }}>
										{provider.api_key ? 'Update Key' : 'Add Key'}
									</button>
								{/if}
							{/if}

							<button class="btn btn-xs btn-secondary" onclick={() => handleExpand(provider.id)}>
								{expandingId === provider.id ? 'Collapse' : 'Details'}
							</button>
							<button
								class="btn btn-xs btn-secondary"
								onclick={() => handleTest(provider.id)}
								disabled={testingId === provider.id}
							>
								{testingId === provider.id ? 'Testing…' : 'Test'}
							</button>
							<button
								class="btn btn-xs"
								class:btn-primary={selectedDefault === provider.id}
								class:btn-secondary={selectedDefault !== provider.id}
								onclick={() => handleSetDefault(provider.id)}
							>
								{selectedDefault === provider.id ? 'Default' : 'Set Default'}
							</button>
							<button class="btn btn-xs btn-danger" onclick={() => handleDelete(provider.id)}>Remove</button>
						</div>
					{:else}
						<div class="provider-actions">
							<button
								class="btn btn-xs btn-primary"
								onclick={() => handleInstallProvider(item.kind)}
							>
								{item.hasApiKey ? 'Add API Key' : 'Install'}
							</button>
						</div>
					{/if}
				</div>
			{/each}
		</div>
	{/if}
</div>

<style>
	.provider-settings {
		display: flex;
		flex-direction: column;
		gap: var(--space-5);
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

	/* ── Loading ── */

	.loading {
		display: flex;
		justify-content: center;
		padding: var(--space-8);
	}

	.spinner {
		width: 28px;
		height: 28px;
		border: 2px solid var(--surface-3);
		border-top-color: var(--accent-1);
		border-radius: 50%;
		animation: spin 0.7s linear infinite;
	}

	@keyframes spin {
		to { transform: rotate(360deg); }
	}

	/* ── Provider Grid ── */

	.provider-grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
		gap: var(--space-3);
	}

	.provider-card {
		background: var(--surface-2);
		border: var(--border-1) var(--border-color-1);
		border-radius: var(--radius-lg);
		padding: var(--space-4);
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
		transition: border-color var(--transition-fast);
	}

	.provider-card:hover {
		border-color: var(--surface-5);
	}

	.provider-card-top {
		display: flex;
		align-items: center;
		gap: var(--space-3);
	}

	.provider-icon-wrap {
		width: 36px;
		height: 36px;
		border-radius: var(--radius-md);
		background: var(--surface-3);
		display: flex;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
		overflow: hidden;
	}

	.provider-icon-img {
		width: 24px;
		height: 24px;
		object-fit: contain;
	}

	.provider-icon-placeholder {
		font-size: var(--font-size-xs);
		font-weight: 700;
		color: var(--text-secondary);
		font-family: var(--font-mono);
	}

	.provider-info {
		flex: 1;
		min-width: 0;
		display: flex;
		flex-direction: column;
		gap: 1px;
	}

	.provider-name {
		font-size: var(--font-size-sm);
		font-weight: 600;
		color: var(--text-primary);
	}

	.provider-type {
		font-size: 10px;
		text-transform: uppercase;
		color: var(--text-tertiary);
		font-family: var(--font-mono);
		letter-spacing: 0.3px;
	}

	/* ── Status Badge ── */

	.status-badge {
		font-size: 10px;
		font-weight: 500;
		padding: 2px 10px;
		border-radius: var(--radius-full);
		text-transform: capitalize;
		white-space: nowrap;
		flex-shrink: 0;
	}

	.status-badge.connected {
		background: rgba(52, 199, 89, 0.1);
		color: var(--success);
	}

	.status-badge.installed {
		background: rgba(255, 149, 0, 0.1);
		color: var(--warning);
	}

	.status-badge.disconnected {
		background: rgba(255, 149, 0, 0.06);
		color: var(--text-tertiary);
	}

	.status-badge.not-configured {
		background: var(--surface-3);
		color: var(--text-tertiary);
	}

	/* ── Models Preview ── */

	.provider-models-preview {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: var(--space-1);
	}

	.model-tags {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: 4px;
	}

	.model-tag {
		padding: 1px 8px;
		background: var(--surface-3);
		border-radius: var(--radius-sm);
		font-size: 10px;
		font-family: var(--font-mono);
		color: var(--text-secondary);
	}

	.model-tag.more {
		background: var(--accent-3);
		color: var(--accent-1);
	}

	.no-models {
		font-size: var(--font-size-xs);
		color: var(--text-tertiary);
		font-style: italic;
	}

	/* ── Expanded Detail Panel ── */

	.provider-detail-panel {
		border-top: var(--border-1) var(--border-color-2);
		padding-top: var(--space-3);
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}

	.detail-section {
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}

	.detail-label {
		font-size: 10px;
		font-weight: 600;
		color: var(--text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.5px;
	}

	.model-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}

	.model-item {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		padding: 3px var(--space-2);
		border-radius: var(--radius-sm);
		background: var(--surface-1);
	}

	.model-item.default {
		border: var(--border-1) var(--accent-3);
	}

	.model-name {
		font-size: var(--font-size-xs);
		font-weight: 500;
		color: var(--text-primary);
		font-family: var(--font-mono);
	}

	.model-detail {
		font-size: 10px;
		color: var(--text-tertiary);
		flex: 1;
	}

	.model-default-badge {
		font-size: 9px;
		font-weight: 600;
		text-transform: uppercase;
		padding: 1px 6px;
		border-radius: var(--radius-full);
		background: var(--accent-3);
		color: var(--accent-1);
		letter-spacing: 0.3px;
	}

	.credits-value {
		font-size: var(--font-size-sm);
		color: var(--text-secondary);
	}

	.credits-reset {
		font-size: 10px;
		color: var(--text-tertiary);
	}

	.status-message {
		font-size: var(--font-size-xs);
		color: var(--text-secondary);
	}

	/* ── Actions ── */

	.provider-actions {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: var(--space-1);
		padding-top: var(--space-2);
		border-top: var(--border-1) var(--border-color-2);
	}

	.api-key-edit {
		display: flex;
		align-items: center;
		gap: var(--space-1);
		width: 100%;
	}

	.api-key-input {
		flex: 1;
		padding: 4px 8px;
		border: var(--border-1) var(--accent-1);
		background: var(--surface-1);
		border-radius: var(--radius-sm);
		font-size: var(--font-size-xs);
		color: var(--text-primary);
		outline: none;
		font-family: var(--font-mono);
	}

	/* ── Buttons ── */

	.btn {
		padding: 4px 10px;
		border: none;
		border-radius: var(--radius-sm);
		font-size: var(--font-size-xs);
		font-weight: 500;
		cursor: pointer;
		transition: all var(--transition-fast);
		font-family: var(--font-system);
		white-space: nowrap;
	}

	.btn-xs {
		padding: 3px 8px;
		font-size: 10px;
	}

	.btn-primary {
		background: var(--accent-1);
		color: white;
	}

	.btn-primary:hover:not(:disabled) {
		background: var(--accent-2);
	}

	.btn-secondary {
		background: var(--surface-3);
		color: var(--text-primary);
	}

	.btn-secondary:hover:not(:disabled) {
		background: var(--surface-4);
	}

	.btn-danger {
		background: rgba(255, 59, 48, 0.08);
		color: var(--danger);
	}

	.btn-danger:hover {
		background: rgba(255, 59, 48, 0.15);
	}

	.btn:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}
</style>
