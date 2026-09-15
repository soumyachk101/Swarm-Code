<script lang="ts">
	import type { TimelineItem, AssistantMessage, ToolCall, TurnSummary, Notice } from '$lib/types';
	import { ToolStatus, HydraHeadStatus, ProviderKind } from '$lib/types';
	import { HYDRA_PERSONAS, hydraPersonaAt } from '$lib/types';

	// ---------------------------------------------------------------------------
	// Props
	// ---------------------------------------------------------------------------

	interface Props {
		block: {
			id: string;
			type: string;
			label: string;
			time: string;
			events: Array<{
				id: string;
				type: string;
				timestamp: string;
				description: string;
				icon: string;
				color: string;
				details?: string;
				metadata?: Record<string, unknown>;
			}>;
		};
		readonly?: boolean;
	}

	let { block }: Props = $props();

	// ---------------------------------------------------------------------------
	// State
	// ---------------------------------------------------------------------------

	let expanded = $state<Set<string>>(new Set());

	function toggle(id: string) {
		const next = new Set(expanded);
		next.has(id) ? next.delete(id) : next.add(id);
		expanded = next;
	}

	// ---------------------------------------------------------------------------
	// Renderers
	// ---------------------------------------------------------------------------

	function eventIcon(name: string): string {
		const map: Record<string, string> = {
			message: '✉',
			bot: '⚡',
			code: '〉',
			brain: '◈',
			'list-checks': '☰',
			info: 'ℹ',
			'alert-triangle': '⚠',
			'check-circle': '✓',
			paperclip: '⤴',
			terminal: '⌨',
			'cpu': '◆',
		};
		return map[name] ?? '●';
	}

	function statusBadge(status: string): { label: string; color: string } {
		switch (status) {
			case 'completed':
				return { label: 'Done', color: '#10b981' };
			case 'failed':
				return { label: 'Failed', color: '#ef4444' };
			case 'running':
				return { label: 'Running', color: '#3b82f6' };
			case 'stopped':
				return { label: 'Stopped', color: '#f59e0b' };
			default:
				return { label: status, color: '#6b7280' };
		}
	}

	function hydraBadge(headIndex: number): string {
		if (headIndex >= 0 && headIndex < HYDRA_PERSONAS.length) {
			return hydraPersonaAt(headIndex).name;
		}
		return `Head #${headIndex}`;
	}
</script>

<div class="timeline-rows">
	{#each block.events as event (event.id)}
		{@const isExpanded = expanded.has(event.id)}
		<div
			class="event-row"
			class:expanded={isExpanded}
		>
			<button
				class="event-header"
				onclick={() => toggle(event.id)}
				aria-expanded={isExpanded}
				type="button"
			>
				<span class="event-icon" style="color: {event.color}">
					{eventIcon(event.icon)}
				</span>
				<span class="event-desc">{event.description}</span>
				{#if event.details}
					<span class="event-details-hint">{event.details}</span>
				{/if}
				<span class="expand-chevron" class:open={isExpanded}>▾</span>
			</button>

			{#if isExpanded && event.metadata}
				<div class="event-detail">
					{#if event.type === 'tool_call'}
						{#if event.details}
							<div class="detail-section">
								<span class="detail-label">Output</span>
								<pre class="detail-pre">{event.details}</pre>
							</div>
						{/if}
						<div class="detail-tags">
							{#if event.metadata.kind}
								<span class="tag tag-kind">{event.metadata.kind}</span>
							{/if}
							{#if event.metadata.status}
								{@const badge = statusBadge(event.metadata.status)}
								<span class="tag tag-status" style="background: {badge.color}22; color: {badge.color}; border-color: {badge.color}44;">
									{badge.label}
								</span>
							{/if}
							{#if event.metadata.exit_code !== undefined && event.metadata.exit_code !== null}
								<span class="tag">exit: {event.metadata.exit_code}</span>
							{/if}
						</div>
					{:else if event.type === 'hydra_start' || event.type === 'hydra_complete'}
						<div class="detail-tags">
							{#each [0, 1, 2, 3] as headIndex}
								{@const persona = hydraPersonaAt(headIndex)}
								<span
									class="hydra-head-tag"
									style="background: #{persona.hex.toString(16).padStart(6, '0')}22; color: #{persona.hex.toString(16).padStart(6, '0')}; border-color: #{persona.hex.toString(16).padStart(6, '0')}44;"
								>
									{persona.name}
								</span>
							{/each}
						</div>
					{:else if event.type === 'file_attached'}
						<div class="detail-section">
							<span class="detail-label">File attached</span>
							<div class="file-thumb">
								<span class="file-icon">📎</span>
								<span class="file-name">{event.description}</span>
							</div>
						</div>
					{/if}
				</div>
			{/if}
		</div>
	{/each}
</div>

<style>
	.timeline-rows {
		display: flex;
		flex-direction: column;
		gap: 4px;
	}

	.event-row {
		border-radius: 6px;
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.03));
		transition: background 160ms ease;
		overflow: hidden;
	}

	.event-row:hover {
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.07));
	}

	.event-row.expanded {
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.06));
	}

	.event-header {
		appearance: none;
		border: none;
		background: transparent;
		display: flex;
		align-items: center;
		gap: 8px;
		width: 100%;
		padding: 7px 10px;
		cursor: pointer;
		text-align: left;
		font-family: inherit;
		color: var(--chrome-primary, #111827);
		transition: background 120ms ease;
		border-radius: 6px;
	}

	.event-header:hover {
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.04));
	}

	.event-icon {
		font-size: 12px;
		flex-shrink: 0;
		width: 18px;
		text-align: center;
	}

	.event-desc {
		font-size: 12px;
		line-height: 1.4;
		flex: 1;
		min-width: 0;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.event-details-hint {
		font-size: 10px;
		color: var(--chrome-secondary, #6b7280);
		flex-shrink: 0;
	}

	.expand-chevron {
		font-size: 10px;
		color: var(--chrome-secondary, #6b7280);
		transition: transform 160ms ease;
		flex-shrink: 0;
	}

	.expand-chevron.open {
		transform: rotate(180deg);
	}

	.event-detail {
		padding: 0 10px 10px;
		border-top: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.06));
		margin-top: 2px;
		padding-top: 8px;
	}

	.detail-section {
		margin-bottom: 6px;
	}

	.detail-label {
		display: block;
		font-size: 10px;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--chrome-secondary, #6b7280);
		margin-bottom: 4px;
	}

	.detail-pre {
		font-family: 'SF Mono', 'Menlo', 'Consolas', monospace;
		font-size: 11px;
		line-height: 1.5;
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.05));
		border-radius: 6px;
		padding: 8px 10px;
		margin: 0;
		overflow-x: auto;
		white-space: pre-wrap;
		word-break: break-word;
		max-height: 200px;
		color: var(--chrome-primary, #111827);
	}

	.detail-tags {
		display: flex;
		flex-wrap: wrap;
		gap: 6px;
	}

	.tag {
		font-size: 10px;
		font-family: 'SF Mono', monospace;
		padding: 3px 7px;
		border-radius: 4px;
		border: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.1));
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.04));
		color: var(--chrome-secondary, #6b7280);
		text-transform: capitalize;
	}

	.tag-kind {
		font-weight: 500;
	}

	.tag-status {
		font-weight: 600;
		text-transform: uppercase;
	}

	.hydra-head-tag {
		font-size: 10px;
		font-weight: 600;
		padding: 3px 8px;
		border-radius: 10px;
		border: 1px solid;
		line-height: 1.2;
	}

	.file-thumb {
		display: flex;
		align-items: center;
		gap: 6px;
	}

	.file-icon {
		font-size: 16px;
	}

	.file-name {
		font-size: 12px;
		font-weight: 500;
	}
</style>
