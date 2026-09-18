<script lang="ts">
	import { v4 as uuidv4 } from 'uuid';
	import type { TimelineItem, AssistantMessage, ToolCall, TurnSummary, Notice } from '$lib/types';
	import { ToolStatus, hydraPersonaAt } from '$lib/types';

	// ---------------------------------------------------------------------------
	// Local timeline domain types
	// ---------------------------------------------------------------------------

	export type TimelineEventType =
		| 'message'
		| 'hydra_start'
		| 'hydra_complete'
		| 'provider_switch'
		| 'file_attached'
		| 'tool_call'
		| 'turn_end';

	export interface TimelineEvent {
		id: string;
		type: TimelineEventType;
		timestamp: string;
		description: string;
		icon: string;
		color: string;
		details?: string;
		metadata?: Record<string, unknown>;
	}

	export interface Block {
		id: string;
		type: 'user' | 'assistant' | 'reasoning' | 'tool' | 'plan' | 'notice' | 'turn_end';
		label: string;
		time: string;
		events: TimelineEvent[];
	}

	export interface MinimapEntry {
		id: string;
		label: string;
		weight: number;
	}

	// ---------------------------------------------------------------------------
	// Helpers
	// ---------------------------------------------------------------------------

	function formatTimestamp(iso: string): string {
		const date = new Date(iso);
		const now = new Date();
		const diffMs = now.getTime() - date.getTime();
		const diffSec = Math.floor(diffMs / 1000);
		if (diffSec < 60) return 'now';
		const diffMin = Math.floor(diffSec / 60);
		if (diffMin < 60) return `${diffMin}m ago`;
		const diffHr = Math.floor(diffMin / 60);
		if (diffHr < 24) return `${diffHr}h ago`;
		return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
	}

	function buildBlocksFromItems(items: TimelineItem[]): Block[] {
		const blocks: Block[] = [];

		for (const item of items) {
			const date = new Date(item.date);
			const timeStr = date.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' });
			const events: TimelineEvent[] = [];

			switch (item.content.type) {
				case 'user': {
					const msg = item.content.value;
					events.push({
						id: uuidv4(),
						type: 'message',
						timestamp: item.date,
						description: msg.text.slice(0, 120) || 'Message with attachments',
						icon: 'message',
						color: '#6366f1',
					});
					if (msg.hydra_heads && msg.hydra_heads.length > 0) {
						events.push({
							id: uuidv4(),
							type: 'hydra_start',
							timestamp: item.date,
							description: `Hydra: ${msg.hydra_heads.length} head(s) sent`,
							icon: 'bot',
							color: '#8b5cf6',
						});
					}
					for (const att of msg.attachments) {
						events.push({
							id: uuidv4(),
							type: 'file_attached',
							timestamp: item.date,
							description: att.name,
							icon: 'paperclip',
							color: '#f59e0b',
						});
					}
					break;
				}
				case 'assistant': {
					const msg = item.content.value as AssistantMessage;
					events.push({
						id: uuidv4(),
						type: 'message',
						timestamp: item.date,
						description: msg.text.slice(0, 120) || 'Assistant reply',
						icon: 'bot',
						color: '#10b981',
					});
					break;
				}
				case 'tool': {
					const tool = item.content.value as ToolCall;
					events.push({
						id: uuidv4(),
						type: 'tool_call',
						timestamp: item.date,
						description: tool.title,
						icon: 'terminal',
						color: tool.status === ToolStatus.Failed ? '#ef4444' : '#3b82f6',
						details: tool.detail ?? undefined,
						metadata: { kind: tool.kind, status: tool.status, exit_code: tool.exit_code },
					});
					break;
				}
				case 'turn_end': {
					const summary = item.content.value as TurnSummary;
					events.push({
						id: uuidv4(),
						type: 'turn_end',
						timestamp: item.date,
						description: `Turn complete · ${summary.files_changed} files · +${summary.additions} −${summary.deletions}`,
						icon: 'check-circle',
						color: '#10b981',
					});
					break;
				}
				case 'reasoning': {
					events.push({
						id: uuidv4(),
						type: 'message',
						timestamp: item.date,
						description: 'Reasoning stream',
						icon: 'brain',
						color: '#8b5cf6',
					});
					break;
				}
				case 'plan': {
					events.push({
						id: uuidv4(),
						type: 'message',
						timestamp: item.date,
						description: 'Proposed plan',
						icon: 'list-checks',
						color: '#06b6d4',
					});
					break;
				}
				case 'notice': {
					const notice = item.content.value as Notice;
					const levelColors: Record<string, string> = {
						info: '#3b82f6',
						warning: '#f59e0b',
						error: '#ef4444',
					};
					events.push({
						id: uuidv4(),
						type: 'message',
						timestamp: item.date,
						description: notice.message,
						icon: notice.level === 'error' ? 'alert-triangle' : 'info',
						color: levelColors[notice.level] ?? '#6b7280',
					});
					break;
				}
			}

			if (events.length > 0) {
				blocks.push({
					id: item.id,
					type: item.content.type,
					label: events[0]?.description.slice(0, 40) ?? 'Event',
					time: timeStr,
					events,
				});
			}
		}

		return blocks;
	}

	function buildMinimapEntries(blocks: Block[]): MinimapEntry[] {
		return blocks
			.filter((b) => b.type === 'user')
			.map((b) => ({
				id: b.id,
				label: b.label,
				weight: Math.min(1, Math.max(0.15, b.label.length / 420)),
			}));
	}

	// ---------------------------------------------------------------------------
	// Props
	// ---------------------------------------------------------------------------

	interface Props {
		items: TimelineItem[];
		readonly?: boolean;
	}

	let { items = [], readonly = false }: Props = $props();

	// ---------------------------------------------------------------------------
	// State
	// ---------------------------------------------------------------------------

	let blocks = $derived<Block[]>(buildBlocksFromItems(items));
	let minimapEntries = $derived<MinimapEntry[]>(buildMinimapEntries(blocks));
	let activeBlockId = $state<string | null>(null);
	let visibleCount = $state<number>(50);
	let position = $state<number>(0);

	// ---------------------------------------------------------------------------
	// Geometry & visibility — needed for the "active block" highlight
	// ---------------------------------------------------------------------------

	let scrollRoot: HTMLDivElement | undefined = $state();
	let viewportHeight = $state(0);

	$effect(() => {
		if (!scrollRoot) return;
		const root = scrollRoot;
		const observer = new ResizeObserver(() => {
			viewportHeight = root.clientHeight;
		});
		observer.observe(root);
		viewportHeight = root.clientHeight;
		return () => observer.disconnect();
	});

	function onScroll(event: Event) {
		const target = event.currentTarget as HTMLDivElement;
		const max = target.scrollHeight - target.clientHeight;
		position = max > 0 ? target.scrollTop / max : 0;
		// Find the closest block whose top sits within the viewport
		const roots = target.querySelectorAll<HTMLElement>('[data-block-id]');
		let bestId: string | null = null;
		let bestDist = Infinity;
		for (const el of roots) {
			const id = el.dataset.blockId;
			if (!id) continue;
			const rect = el.getBoundingClientRect();
			const dist = Math.abs(rect.top - target.getBoundingClientRect().top);
			if (dist < bestDist) {
				bestDist = dist;
				bestId = id;
			}
		}
		if (bestId) activeBlockId = bestId;
	}

	// ---------------------------------------------------------------------------
	// Actions
	// ---------------------------------------------------------------------------

	function jumpToBlock(id: string) {
		activeBlockId = id;
		const target = scrollRoot?.querySelector<HTMLElement>(`[data-block-id="${id}"]`);
		target?.scrollIntoView({ behavior: 'smooth', block: 'start' });
	}

	function onMinimapJump(detail: { id: string }) {
		jumpToBlock(detail.id);
	}

	function loadEarlier() {
		visibleCount = visibleCount + 50;
	}
</script>

<div class="thread-timeline-root">
	<!-- The minimap rail rides on the leading edge. -->
	{#if !readonly && blocks.length > 1}
		<TimelineMinimap
			entries={minimapEntries}
			{activeBlockId}
			onJump={onMinimapJump}
			height={viewportHeight}
		/>
	{/if}

	<!-- The actual timeline column. -->
	<div class="timeline-column">
		<div bind:this={scrollRoot} class="timeline-scroll" onscroll={onScroll}>
			{#if blocks.length === 0}
				<div class="empty">
					<span class="empty-text">No events yet. Start the conversation in the composer below.</span>
				</div>
			{:else}
				{#each blocks as block, index (block.id)}
					{#if index < blocks.length - visibleCount}
						<button class="load-earlier" onclick={loadEarlier}>Load earlier</button>
					{:else}
						<article
							class="timeline-block"
							class:active={activeBlockId === block.id}
							data-block-id={block.id}
							aria-label={block.label}
						>
							<header class="block-header">
								<span class="block-time">{block.time}</span>
								<span class="block-label">{block.label}</span>
								<span class="block-type">{block.type}</span>
							</header>
							<TimelineRows {block} {readonly} />
						</article>
					{/if}
				{/each}
			{/if}
		</div>
	</div>
</div>

<style>
	.thread-timeline-root {
		display: grid;
		grid-template-columns: 30px 1fr;
		gap: 0;
		width: 100%;
		height: 100%;
	}

	.timeline-column {
		min-width: 0;
		height: 100%;
		overflow: hidden;
	}

	.timeline-scroll {
		height: 100%;
		overflow-y: auto;
		padding: 16px 24px 64px;
		background: transparent;
	}

	.timeline-scroll::-webkit-scrollbar {
		width: 8px;
	}
	.timeline-scroll::-webkit-scrollbar-thumb {
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.15));
		border-radius: 4px;
	}

	.timeline-block {
		padding: 10px 0 20px;
		border-left: 2px solid transparent;
		margin-left: 4px;
		transition: border-color 160ms ease;
	}

	.timeline-block.active {
		border-left-color: var(--chrome-accent, #6366f1);
	}

	.block-header {
		display: flex;
		align-items: baseline;
		gap: 8px;
		margin-bottom: 6px;
		font-size: 11px;
		color: var(--chrome-secondary, #6b7280);
		font-family: 'SF Mono', monospace;
	}

	.block-time {
		font-variant-numeric: tabular-nums;
		opacity: 0.8;
	}

	.block-label {
		color: var(--chrome-primary, #111827);
		font-size: 12px;
		flex: 1;
		min-width: 0;
		text-overflow: ellipsis;
		overflow: hidden;
		white-space: nowrap;
	}

	.block-type {
		text-transform: uppercase;
		font-size: 9px;
		letter-spacing: 0.06em;
		padding: 2px 5px;
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.06));
		border-radius: 4px;
	}

	.empty {
		display: flex;
		align-items: center;
		justify-content: center;
		height: 70%;
		padding: 32px;
	}

	.empty-text {
		color: var(--chrome-secondary, #6b7280);
		font-size: 13px;
	}

	.load-earlier {
		appearance: none;
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.04));
		border: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.08));
		color: var(--chrome-secondary, #6b7280);
		border-radius: 8px;
		padding: 8px 12px;
		margin: 12px auto;
		font-size: 12px;
		cursor: pointer;
		transition: background 160ms ease;
	}

	.load-earlier:hover {
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.08));
	}
</style>
