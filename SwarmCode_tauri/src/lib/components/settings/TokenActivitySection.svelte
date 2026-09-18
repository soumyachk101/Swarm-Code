<script lang="ts">
	import { getTimeline, type Thread } from '$lib/api/commands';
	import type { TokenUsage, ModelInfo } from '$lib/types';
	import { TimelineGlyph } from '$lib/components/TimelineGlyph.svelte';

	// ---------------------------------------------------------------------------
	// State
	// ---------------------------------------------------------------------------

	let thread = $state<Thread | null>(null);
	let isLoading = $state(true);

	$effect(() => {
		loadThread();
	});

	async function loadThread() {
		try {
			const result = await getTimeline(undefined, 'current');
			thread = result;
		} catch (e) {
			console.error('Failed to load thread:', e);
		} finally {
			isLoading = false;
		}
	}

	// Derive usage info from the thread
	let tokenUsage = $derived.by((): TokenUsage | null => {
		if (!thread) return null;
		// Build from thread info
		const totalTokens = thread.token_usage?.total_tokens ?? 0;
		const maxTokens = thread.token_usage?.max_tokens ?? 0;
		const promptTokens = thread.token_usage?.prompt_tokens ?? 0;
		const completionTokens = thread.token_usage?.completion_tokens ?? 0;
		return {
			prompt_tokens: promptTokens,
			completion_tokens: completionTokens,
			total_tokens: totalTokens,
			max_tokens: maxTokens,
			percentage_used: maxTokens > 0 ? (totalTokens / maxTokens) * 100 : 0,
		};
	});

	let modelInfo = $derived.by((): ModelInfo | null => {
		if (!thread?.model_info) return null;
		return thread.model_info;
	});

	// Estimate: ~4 chars per token average
	let estimatedChars = $derived(tokenUsage ? Math.round(tokenUsage.total_tokens * 4) : 0);
</script>

<div class="token-activity">
	<h3 class="section-title">Token Usage</h3>

	{#if isLoading}
		<div class="loading">
			<div class="spinner"></div>
		</div>
	{:else if tokenUsage}
		<!-- Context Window -->
		<div class="usage-block">
			<div class="usage-header">
				<span class="usage-label">Context Window</span>
				<span class="usage-model">
					{#if modelInfo}
						{modelInfo.display_name ?? modelInfo.id ?? 'Unknown'}
					{:else}
						Current model
					{/if}
				</span>
			</div>

			<!-- Progress Bar -->
			<div class="usage-bar-track">
				<div
					class="usage-bar-fill"
					style="width: {Math.min(100, tokenUsage.percentage_used)}%"
					class:warning={tokenUsage.percentage_used > 70}
					class:critical={tokenUsage.percentage_used > 90}
				></div>
			</div>

			<div class="usage-stats">
				<span class="usage-tokens">{tokenUsage.total_tokens.toLocaleString()} / {tokenUsage.max_tokens.toLocaleString()}</span>
				<span class="usage-percent">{tokenUsage.percentage_used.toFixed(1)}%</span>
			</div>
		</div>

		<!-- Breakdown -->
		<div class="breakdown">
			<div class="breakdown-item">
				<span class="breakdown-label">Input</span>
				<span class="breakdown-value">{tokenUsage.prompt_tokens.toLocaleString()}</span>
			</div>
			<div class="breakdown-item">
				<span class="breakdown-label">Output</span>
				<span class="breakdown-value">{tokenUsage.completion_tokens.toLocaleString()}</span>
			</div>
			<div class="breakdown-item">
				<span class="breakdown-label">Est. chars</span>
				<span class="breakdown-value">{estimatedChars.toLocaleString()}</span>
			</div>
		</div>

		<!-- Context Size Info -->
		<div class="context-info">
			<div class="context-row">
				<span class="context-label">Window size</span>
				<span class="context-value">{tokenUsage.max_tokens.toLocaleString()} tokens</span>
			</div>
			<div class="context-row">
				<span class="context-label">Remaining</span>
				<span class="context-value">
					{((tokenUsage.max_tokens - tokenUsage.total_tokens) / 1000).toFixed(1)}k tokens
				</span>
			</div>
		</div>
	{:else}
		<div class="empty-state">
			<TimelineGlyph size={24} state="idle" />
			<p>No active thread</p>
		</div>
	{/if}
</div>

<style>
	.token-activity {
		display: flex;
		flex-direction: column;
		gap: var(--space-5);
		width: 100%;
	}

	.section-title {
		font-size: var(--font-size-sm);
		font-weight: 600;
		color: var(--text-secondary);
		text-transform: uppercase;
		letter-spacing: 0.5px;
	}

	/* ── Loading ── */

	.loading {
		display: flex;
		justify-content: center;
		padding: var(--space-6);
	}

	.spinner {
		width: 20px;
		height: 20px;
		border: 2px solid var(--surface-3);
		border-top-color: var(--accent-1);
		border-radius: 50%;
		animation: spin 0.7s linear infinite;
	}

	@keyframes spin {
		to { transform: rotate(360deg); }
	}

	/* ── Usage Block ── */

	.usage-block {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}

	.usage-header {
		display: flex;
		justify-content: space-between;
		align-items: center;
	}

	.usage-label {
		font-size: var(--font-size-xs);
		font-weight: 500;
		color: var(--text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.3px;
	}

	.usage-model {
		font-size: var(--font-size-xs);
		font-family: var(--font-mono);
		color: var(--text-secondary);
	}

	.usage-bar-track {
		height: 8px;
		border-radius: 4px;
		background: var(--surface-3);
		overflow: hidden;
	}

	.usage-bar-fill {
		height: 100%;
		border-radius: 4px;
		background: var(--accent-1);
		transition: width var(--transition-slow), background var(--transition-fast);
	}

	.usage-bar-fill.warning {
		background: var(--warning);
	}

	.usage-bar-fill.critical {
		background: var(--danger);
	}

	.usage-stats {
		display: flex;
		justify-content: space-between;
		align-items: center;
	}

	.usage-tokens {
		font-size: var(--font-size-xs);
		font-family: var(--font-mono);
		color: var(--text-secondary);
	}

	.usage-percent {
		font-size: var(--font-size-xs);
		font-weight: 600;
		color: var(--text-primary);
		font-family: var(--font-mono);
	}

	/* ── Breakdown ── */

	.breakdown {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: var(--space-2);
	}

	.breakdown-item {
		background: var(--surface-2);
		border: var(--border-1) var(--border-color-1);
		border-radius: var(--radius-md);
		padding: var(--space-3);
		display: flex;
		flex-direction: column;
		gap: 2px;
	}

	.breakdown-label {
		font-size: 10px;
		color: var(--text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.3px;
	}

	.breakdown-value {
		font-size: var(--font-size-sm);
		font-weight: 500;
		color: var(--text-primary);
		font-family: var(--font-mono);
	}

	/* ── Context Info ── */

	.context-info {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
	}

	.context-row {
		display: flex;
		justify-content: space-between;
		align-items: center;
		padding: var(--space-2) 0;
	}

	.context-label {
		font-size: var(--font-size-xs);
		color: var(--text-tertiary);
	}

	.context-value {
		font-size: var(--font-size-xs);
		font-family: var(--font-mono);
		color: var(--text-secondary);
	}

	/* ── Empty State ── */

	.empty-state {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--space-3);
		padding: var(--space-8);
		color: var(--text-tertiary);
		font-size: var(--font-size-sm);
	}
</style>
