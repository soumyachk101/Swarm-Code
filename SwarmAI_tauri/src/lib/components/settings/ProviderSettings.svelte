<script lang="ts">
	import { getProviders, testProvider, addProvider, removeProvider, updateProviderCredits } from '$lib/api/commands';
	import type { Provider, ProviderKind } from '$lib/types';

	interface Props {
		projectId: string | null;
	}

	let { projectId = null }: Props = $props();

	let providers = $state<Provider[]>([]);
	let isLoading = $state(true);
	let showAddForm = $state(false);
	let isTesting = $state<string | null>(null);
	let activeTab = $state<'all' | 'active' | 'error'>('all');

	let newProviderName = $state('');
	let newProviderKind = $state<ProviderKind>(ProviderKind.Anthropic);
	let newProviderKey = $state('');
	let newProviderModel = $state('');

	$effect(() => {
		loadProviders();
	});

	async function loadProviders() {
		try {
			providers = await getProviders();
		} catch (e) {
			console.error('Failed to load providers:', e);
		} finally {
			isLoading = false;
		}
	}

	async function handleTest(providerId: string) {
		isTesting = providerId;
		try {
			await testProvider(providerId);
			await loadProviders();
		} catch (e) {
			console.error('Provider test failed:', e);
		} finally {
			isTesting = null;
		}
	}

	async function handleAdd() {
		if (!newProviderName.trim() || !newProviderKey.trim()) return;
		try {
			await addProvider({
				name: newProviderName.trim(),
				kind: newProviderKind,
				apiKey: newProviderKey,
				model: newProviderModel || undefined,
			});
			newProviderName = '';
			newProviderKey = '';
			newProviderModel = '';
			showAddForm = false;
			await loadProviders();
		} catch (e) {
			console.error('Failed to add provider:', e);
		}
	}

	async function handleRemove(providerId: string) {
		if (!confirm('Remove this provider? This cannot be undone.')) return;
		try {
			await removeProvider(providerId);
			await loadProviders();
		} catch (e) {
			console.error('Failed to remove provider:', e);
		}
	}

	let filteredProviders = $derived(() => {
		if (activeTab === 'active') return providers.filter(p => p.status === 'active');
		if (activeTab === 'error') return providers.filter(p => p.status === 'error');
		return providers;
	});

	let providerCounts = $derived(() => ({
		all: providers.length,
		active: providers.filter(p => p.status === 'active').length,
		error: providers.filter(p => p.status === 'error').length,
	}));

	function formatCredits(provider: Provider): string {
		if (!provider.credits) return '—';
		const used = provider.credits.used_tokens || 0;
		const total = provider.credits.credits_total || 0;
		const remaining = provider.credits.credits_remaining ?? null;
		if (remaining !== null && total > 0) {
			return `${remaining.toLocaleString()} left`;
		}
		if (total > 0) {
			return `${used.toLocaleString()} / ${total.toLocaleString()} used`;
		}
		return `${used.toLocaleString()} used`;
	}

	function getProviderIcon(kind: ProviderKind): string {
		switch (kind) {
			case ProviderKind.Anthropic: return 'A';
			case ProviderKind.OpenAI: return 'O';
			case ProviderKind.Google: return 'G';
			case ProviderKind.Ollama: return 'Ω';
			case ProviderKind.Custom: return '?';
		}
	}

	let providerKindOptions: ProviderKind[] = [
		ProviderKind.Anthropic,
		ProviderKind.OpenAI,
		ProviderKind.Google,
		ProviderKind.Ollama,
		ProviderKind.Custom,
	];
</script>

<div class="provider-settings">
	<div class="settings-header">
		<h2 class="settings-title">Providers</h2>
		<button class="btn-primary" onclick={() => showAddForm = !showAddForm}>
			{showAddForm ? 'Cancel' : '+ Add Provider'}
		</button>
	</div>

	<!-- Add Provider Form -->
	{#if showAddForm}
		<div class="add-form">
			<h3 class="form-title">New Provider</h3>
			<div class="form-grid">
				<div class="form-group">
					<label class="form-label">Name</label>
					<input
						type="text"
						class="form-input"
						placeholder="My Provider"
						value={newProviderName}
						oninput={(e) => newProviderName = e.currentTarget.value}
					/>
				</div>
				<div class="form-group">
					<label class="form-label">Type</label>
					<select
						class="form-select"
						value={newProviderKind}
						onchange={(e) => newProviderKind = e.currentTarget.value as ProviderKind}
					>
						{#each providerKindOptions as kind (kind)}
							<option value={kind}>{kind}</option>
						{/each}
					</select>
				</div>
				<div class="form-group">
					<label class="form-label">API Key</label>
					<input
						type="password"
						class="form-input"
						placeholder="sk-..."
						value={newProviderKey}
						oninput={(e) => newProviderKey = e.currentTarget.value}
					/>
				</div>
				<div class="form-group">
					<label class="form-label">Model (optional)</label>
					<input
						type="text"
						class="form-input"
						placeholder="claude-3-opus"
						value={newProviderModel}
						oninput={(e) => newProviderModel = e.currentTarget.value}
					/>
				</div>
			</div>
			<div class="form-actions">
				<button class="btn-primary" onclick={handleAdd} disabled={!newProviderName.trim() || !newProviderKey.trim()}>
					Add Provider
				</button>
				<button class="btn-secondary" onclick={() => showAddForm = false}>Cancel</button>
			</div>
		</div>
	{/if}

	<!-- Tab Filter -->
	<div class="filter-tabs">
		<button class="filter-tab" class:active={activeTab === 'all'} onclick={() => activeTab = 'all'}>
			All <span class="tab-count">{providerCounts().all}</span>
		</button>
		<button class="filter-tab" class:active={activeTab === 'active'} onclick={() => activeTab = 'active'}>
			Active <span class="tab-count success">{providerCounts().active}</span>
		</button>
		<button class="filter-tab" class:active={activeTab === 'error'} onclick={() => activeTab = 'error'}>
			Errors <span class="tab-count danger">{providerCounts().error}</span>
		</button>
	</div>

	{#if isLoading}
		<div class="loading">
			<div class="spinner"></div>
		</div>
	{:else if filteredProviders().length === 0}
		<div class="empty-state">
			<p>No providers configured yet.</p>
			<span>Add a provider to connect to an AI model.</span>
		</div>
	{:else}
		<div class="provider-list">
			{#each filteredProviders() as provider (provider.id)}
				<div class="provider-card" class:error={provider.status === 'error'}>
					<div class="provider-card-header">
						<div class="provider-icon">
							{getProviderIcon(provider.kind)}
						</div>
						<div class="provider-details">
							<span class="provider-name">{provider.name}</span>
							<span class="provider-type">{provider.kind}</span>
						</div>
						<span class="status-badge {provider.status}">
							{provider.status}
						</span>
					</div>
					<div class="provider-card-body">
						<div class="provider-meta">
							{#if provider.models && provider.models.length > 0}
								<div class="models-row">
									<span class="meta-label">Models:</span>
									{#each provider.models.slice(0, 5) as model (model.id)}
										<span class="model-tag">{model.id}</span>
									{/each}
								</div>
							{/if}
							<div class="credits-row">
								<span class="meta-label">Credits:</span>
								<span class="credits-value">{formatCredits(provider)}</span>
							</div>
							{#if provider.lastError}
								<div class="error-row">
									<span class="error-msg">{provider.lastError}</span>
								</div>
							{/if}
						</div>
					</div>
					<div class="provider-card-actions">
						<button
							class="action-btn test"
							onclick={() => handleTest(provider.id)}
							disabled={isTesting === provider.id}
						>
							{#if isTesting === provider.id}
								<span class="spinner-sm"></span>
							{:else}
								Test
							{/if}
						</button>
						<button
							class="action-btn refresh"
							onclick={() => updateProviderCredits(provider.id)}
						>
							<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
								<path d="M1 4v6h6M23 20v-6h-6"/>
								<path d="M20.49 9A9 9 0 0 0 5.64 5.64L1 10m22 4l-4.64 4.36A9 9 0 0 1 3.51 15"/>
							</svg>
						</button>
						<button
							class="action-btn delete"
							onclick={() => handleRemove(provider.id)}
						>
							<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
								<path d="M3 6h18M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>
							</svg>
						</button>
					</div>
				</div>
			{/each}
		</div>
	{/if}
</div>

<style>
	.provider-settings {
		height: 100%;
		overflow-y: auto;
		padding: var(--space-6) var(--space-8);
		display: flex;
		flex-direction: column;
		gap: var(--space-5);
		max-width: 680px;
	}

	.settings-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding-bottom: var(--space-4);
		border-bottom: var(--border-1) var(--border-color-1);
	}

	.settings-title {
		font-size: var(--font-size-xl);
		font-weight: 700;
		color: var(--text-primary);
	}

	.add-form {
		background: var(--surface-3);
		border: var(--border-1) var(--border-color-1);
		border-radius: var(--radius-md);
		padding: var(--space-4);
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
	}

	.form-title {
		font-size: var(--font-size-sm);
		font-weight: 600;
		color: var(--text-primary);
	}

	.form-grid {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: var(--space-3);
	}

	.form-group {
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}

	.form-label {
		font-size: var(--font-size-xs);
		font-weight: 500;
		color: var(--text-secondary);
	}

	.form-input,
	.form-select {
		width: 100%;
		padding: 6px 10px;
		border: var(--border-1) var(--border-color-1);
		background: var(--surface-1);
		border-radius: var(--radius-sm);
		font-size: var(--font-size-sm);
		color: var(--text-primary);
		outline: none;
		font-family: var(--font-system);
	}

	.form-input:focus,
	.form-select:focus {
		border-color: var(--accent-1);
	}

	.form-select {
		appearance: none;
		-webkit-appearance: none;
		cursor: pointer;
	}

	.form-actions {
		display: flex;
		gap: var(--space-2);
	}

	.filter-tabs {
		display: flex;
		gap: 2px;
		padding: 2px;
		background: var(--surface-3);
		border-radius: var(--radius-md);
		width: fit-content;
	}

	.filter-tab {
		display: flex;
		align-items: center;
		gap: 4px;
		padding: 5px 12px;
		border: none;
		background: transparent;
		border-radius: var(--radius-sm);
		font-size: var(--font-size-xs);
		font-weight: 500;
		color: var(--text-secondary);
		cursor: pointer;
		transition: all var(--transition-fast);
	}

	.filter-tab.active {
		background: var(--surface-1);
		color: var(--text-primary);
		box-shadow: var(--shadow-sm);
	}

	.filter-tab:hover:not(.active) {
		color: var(--text-primary);
	}

	.tab-count {
		font-size: 10px;
		padding: 1px 5px;
		border-radius: var(--radius-full);
		background: var(--surface-4);
		color: var(--text-tertiary);
	}

	.tab-count.success {
		background: rgba(48, 209, 88, 0.15);
		color: var(--success);
	}

	.tab-count.danger {
		background: rgba(255, 59, 48, 0.15);
		color: var(--danger);
	}

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

	.spinner-sm {
		width: 12px;
		height: 12px;
		border: 1.5px solid var(--surface-3);
		border-top-color: var(--text-inverse);
		border-radius: 50%;
		animation: spin 0.7s linear infinite;
		display: inline-block;
	}

	.empty-state {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		padding: var(--space-8) var(--space-4);
		text-align: center;
		gap: var(--space-2);
		color: var(--text-tertiary);
	}

	.empty-state p {
		font-size: var(--font-size-sm);
		color: var(--text-secondary);
	}

	.empty-state span {
		font-size: var(--font-size-xs);
	}

	.provider-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-3);
	}

	.provider-card {
		background: var(--surface-2);
		border: var(--border-1) var(--border-color-1);
		border-radius: var(--radius-md);
		overflow: hidden;
		transition: border-color var(--transition-fast);
	}

	.provider-card.error {
		border-color: rgba(255, 59, 48, 0.2);
	}

	.provider-card-header {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		padding: var(--space-3) var(--space-4);
		border-bottom: var(--border-1) var(--border-color-2);
	}

	.provider-icon {
		width: 32px;
		height: 32px;
		border-radius: var(--radius-md);
		background: var(--accent-3);
		color: var(--accent-1);
		display: flex;
		align-items: center;
		justify-content: center;
		font-size: 14px;
		font-weight: 700;
		flex-shrink: 0;
	}

	.provider-details {
		flex: 1;
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

	.status-badge {
		font-size: 10px;
		font-weight: 500;
		padding: 2px 8px;
		border-radius: var(--radius-full);
		text-transform: capitalize;
	}

	.status-badge.active {
		background: rgba(48, 209, 88, 0.1);
		color: var(--success);
	}

	.status-badge.idle {
		background: var(--surface-3);
		color: var(--text-tertiary);
	}

	.status-badge.error {
		background: rgba(255, 59, 48, 0.1);
		color: var(--danger);
	}

	.status-badge.disabled {
		background: var(--surface-3);
		color: var(--text-tertiary);
	}

	.provider-card-body {
		padding: var(--space-3) var(--space-4);
	}

	.provider-meta {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}

	.models-row {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: var(--space-1);
	}

	.credits-row,
	.error-row {
		display: flex;
		align-items: center;
		gap: var(--space-2);
	}

	.meta-label {
		font-size: 11px;
		font-weight: 500;
		color: var(--text-tertiary);
		min-width: 50px;
	}

	.model-tag {
		padding: 1px 6px;
		background: var(--surface-3);
		border-radius: var(--radius-sm);
		font-size: 10px;
		font-family: var(--font-mono);
		color: var(--text-secondary);
	}

	.credits-value {
		font-size: var(--font-size-xs);
		color: var(--text-secondary);
	}

	.error-msg {
		font-size: var(--font-size-xs);
		color: var(--danger);
		font-style: italic;
	}

	.provider-card-actions {
		display: flex;
		align-items: center;
		gap: var(--space-1);
		padding: var(--space-2) var(--space-4);
		border-top: var(--border-1) var(--border-color-2);
	}

	.action-btn {
		padding: 4px 10px;
		border: none;
		background: transparent;
		border-radius: var(--radius-sm);
		font-size: var(--font-size-xs);
		color: var(--text-tertiary);
		cursor: pointer;
		display: flex;
		align-items: center;
		gap: 3px;
		transition: all var(--transition-fast);
		font-weight: 500;
	}

	.action-btn:hover:not(:disabled) {
		background: var(--surface-3);
		color: var(--text-primary);
	}

	.action-btn:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}

	.action-btn.test:hover {
		background: var(--accent-3);
		color: var(--accent-1);
	}

	.action-btn.refresh:hover {
		background: var(--surface-3);
		color: var(--text-primary);
	}

	.action-btn.delete:hover {
		background: rgba(255, 59, 48, 0.1);
		color: var(--danger);
	}

	.btn-primary {
		padding: 6px 16px;
		border: none;
		background: var(--accent-1);
		color: var(--text-inverse);
		border-radius: var(--radius-sm);
		font-size: var(--font-size-sm);
		font-weight: 500;
		cursor: pointer;
		transition: background var(--transition-fast);
	}

	.btn-primary:hover:not(:disabled) {
		background: var(--accent-2);
	}

	.btn-primary:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}

	.btn-secondary {
		padding: 5px 12px;
		border: var(--border-1) var(--border-color-1);
		background: transparent;
		border-radius: var(--radius-sm);
		font-size: var(--font-size-xs);
		color: var(--text-secondary);
		cursor: pointer;
	}

	.btn-secondary:hover {
		background: var(--surface-3);
	}
</style>
