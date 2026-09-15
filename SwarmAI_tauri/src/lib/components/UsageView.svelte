<script lang="ts">
	import type { Provider, ModelInfo } from '$lib/types';

	interface Props {
		providers: Provider[];
		modelUsage?: Record<string, number>;
	}

	let { providers, modelUsage = {} }: Props = $props();

	let totalTokens = $derived(
		providers.reduce((sum, p) => sum + (p.credits?.used_tokens || p.credits?.window_tokens || 0), 0)
	);

	let totalCredits = $derived(
		providers.reduce((sum, p) => sum + (p.credits?.credits_remaining ?? 0), 0)
	);

	let allModels = $derived(
		providers.flatMap(p => p.models || [])
	);

	function getUsagePercent(provider: Provider): number {
		if (!provider.credits) return 0;
		const total = provider.credits.credits_total || 1;
		return Math.round((provider.credits.used_tokens / total) * 100);
	}

	function formatNumber(n: number): string {
		if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M';
		if (n >= 1_000) return (n / 1_000).toFixed(1) + 'K';
		return n.toString();
	}

	let statusLabel = $derived((p: Provider) => {
		const ps = p.status;
		if (ps?.error) return 'Error';
		if (ps?.is_authenticated) return 'Active';
		return 'Idle';
	});

	let statusClass = $derived((p: Provider) => {
		const ps = p.status;
		if (ps?.error) return 'error';
		if (ps?.is_authenticated) return 'active';
		return 'idle';
	});
</script>

<div class="usage-view">
	<!-- Summary Cards -->
	<div class="usage-summary">
		<div class="summary-card">
			<span class="summary-value">{providers.length}</span>
			<span class="summary-label">Providers</span>
		</div>
		<div class="summary-card">
			<span class="summary-value">{allModels.length}</span>
			<span class="summary-label">Models</span>
		</div>
		<div class="summary-card">
			<span class="summary-value">{formatNumber(totalTokens)}</span>
			<span class="summary-label">Tokens Used</span>
		</div>
		<div class="summary-card">
			<span class="summary-value" class:low={totalCredits > 0 && totalCredits < 100}>
				{totalCredits > 0 ? formatNumber(totalCredits) : '—'}
			</span>
			<span class="summary-label">Credits Left</span>
		</div>
	</div>

	<!-- Provider Breakdown -->
	<div class="usage-section">
		<h3 class="section-title">Providers</h3>
		<div class="provider-list">
			{#each providers as provider (provider.id)}
				<div class="provider-row">
					<div class="provider-info">
						<span class="provider-name">{provider.name}</span>
						<span class="provider-type">
							{provider.type || provider.kind || 'unknown'}
						</span>
					</div>
					<div class="provider-stats">
						<div class="usage-bar">
							<div
								class="usage-fill"
								style="width: {getUsagePercent(provider)}%"
								class:high={getUsagePercent(provider) > 80}
							></div>
						</div>
						<span class="usage-value">
							{provider.credits ? `${formatNumber(provider.credits.used_tokens)} used` : 'No data'}
						</span>
					</div>
					<span class="provider-status {statusClass(provider.status)}">
						{statusLabel(provider.status)}
					</span>
				</div>
			{/each}
		</div>
	</div>

	<!-- Model Usage -->
	{#if Object.keys(modelUsage).length > 0}
		<div class="usage-section">
			<h3 class="section-title">Models</h3>
			<div class="model-usage-list">
				{#each Object.entries(modelUsage).sort((a, b) => b[1] - a[1]).slice(0, 10) as [model, count] (model)}
					<div class="model-usage-row">
						<span class="model-name">{model}</span>
						<div class="model-bar-wrapper">
							<div class="model-bar" style="width: {(count / (modelUsage[Object.keys(modelUsage)[0]] || 1)) * 100}%"></div>
						</div>
						<span class="model-count">{count}</span>
					</div>
				{/each}
			</div>
		</div>
	{/if}
</div>

<style>
	.usage-view {
		display: flex;
		flex-direction: column;
		gap: var(--space-5);
		padding: var(--space-4) 0;
	}

	.usage-summary {
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: var(--space-3);
	}

	.summary-card {
		display: flex;
		flex-direction: column;
		align-items: center;
		padding: var(--space-4);
		background: var(--surface-2);
		border: var(--border-1) var(--border-color-1);
		border-radius: var(--radius-md);
		text-align: center;
	}

	.summary-value {
		font-size: 24px;
		font-weight: 700;
		color: var(--text-primary);
		line-height: 1.2;
	}

	.summary-value.low {
		color: var(--danger);
	}

	.summary-label {
		font-size: 11px;
		color: var(--text-tertiary);
		margin-top: 4px;
		text-transform: uppercase;
		letter-spacing: 0.3px;
	}

	.usage-section {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}

	.section-title {
		font-size: var(--font-size-sm);
		font-weight: 600;
		color: var(--text-primary);
		margin-bottom: var(--space-1);
	}

	.provider-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}

	.provider-row {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		padding: var(--space-3);
		background: var(--surface-2);
		border: var(--border-1) var(--border-color-1);
		border-radius: var(--radius-md);
	}

	.provider-info {
		display: flex;
		flex-direction: column;
		min-width: 100px;
	}

	.provider-name {
		font-size: var(--font-size-sm);
		font-weight: 500;
		color: var(--text-primary);
	}

	.provider-type {
		font-size: 10px;
		text-transform: uppercase;
		color: var(--text-tertiary);
		font-family: var(--font-mono);
	}

	.provider-stats {
		flex: 1;
		display: flex;
		align-items: center;
		gap: var(--space-3);
		min-width: 0;
	}

	.usage-bar {
		flex: 1;
		height: 4px;
		background: var(--surface-3);
		border-radius: var(--radius-full);
		overflow: hidden;
		min-width: 60px;
	}

	.usage-fill {
		height: 100%;
		background: var(--accent-1);
		border-radius: var(--radius-full);
		transition: width var(--transition-base);
	}

	.usage-fill.high {
		background: var(--danger);
	}

	.usage-value {
		font-size: 11px;
		color: var(--text-tertiary);
		white-space: nowrap;
		font-family: var(--font-mono);
	}

	.provider-status {
		font-size: 10px;
		font-weight: 500;
		padding: 2px 8px;
		border-radius: var(--radius-full);
		text-transform: capitalize;
		white-space: nowrap;
	}

	.provider-status.active {
		background: rgba(48, 209, 88, 0.1);
		color: var(--success);
	}

	.provider-status.idle {
		background: var(--surface-3);
		color: var(--text-tertiary);
	}

	.provider-status.error {
		background: rgba(255, 59, 48, 0.1);
		color: var(--danger);
	}

	.provider-status.disabled {
		background: var(--surface-3);
		color: var(--text-tertiary);
	}

	.model-usage-list {
		display: flex;
		flex-direction: column;
		gap: var(--space-1);
	}

	.model-usage-row {
		display: flex;
		align-items: center;
		gap: var(--space-3);
		padding: 4px 0;
	}

	.model-name {
		font-size: var(--font-size-sm);
		color: var(--text-primary);
		min-width: 140px;
		font-family: var(--font-mono);
	}

	.model-bar-wrapper {
		flex: 1;
		height: 4px;
		background: var(--surface-3);
		border-radius: var(--radius-full);
		overflow: hidden;
	}

	.model-bar {
		height: 100%;
		background: var(--accent-1);
		border-radius: var(--radius-full);
	}

	.model-count {
		font-size: 11px;
		color: var(--text-tertiary);
		font-family: var(--font-mono);
		min-width: 30px;
		text-align: right;
	}
</style>
