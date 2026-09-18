<script lang="ts">
	import type { MinimapEntry } from './ThreadTimeline.svelte';

	// ---------------------------------------------------------------------------
	// Props
	// ---------------------------------------------------------------------------

	interface Props {
		entries: MinimapEntry[];
		activeBlockId: string | null;
		onJump: (detail: { id: string }) => void;
		height: number;
	}

	let { entries = [], activeBlockId = null, onJump, height = 400 }: Props = $props();

	// ---------------------------------------------------------------------------
	// State
	// ---------------------------------------------------------------------------

	let rail: HTMLDivElement | undefined = $state();
	let hoveredIndex = $state<number | null>(null);
	let isDragging = $state(false);

	// ---------------------------------------------------------------------------
	// Metrics
	// ---------------------------------------------------------------------------

	let railMetrics = $derived(() => {
		const count = entries.length;
		if (count === 0) return { tickHeight: 0, spacing: 0, totalHeight: 0, hitArea: 0 };

		const hitAreaPadding = 8;
		const tickMinWidth = 6;
		const tickMaxWidth = 28;
		const hitAreaWidth = 36;

		const tickWeight = 0.6;
		const gap = 5;

		const totalWeight = entries.reduce((sum, e) => sum + e.weight, 0);
		const totalTicksWeight = totalWeight * tickWeight;
		const totalGaps = Math.max(0, count - 1) * gap;
		const availableHeight = Math.max(0, height - hitAreaPadding * 2 - totalGaps);
		const tickHeight = totalTicksWeight > 0 ? availableHeight / totalTicksWeight : 0;

		return {
			tickHeight: Math.max(1.5, Math.min(tickHeight, 20)),
			spacing: tickHeight + gap,
			hitArea: hitAreaWidth,
		};
	});

	// ---------------------------------------------------------------------------
	// Helpers
	// ---------------------------------------------------------------------------

	function tickY(index: number): number {
		const m = railMetrics();
		return m.tickHeight * entries[index].weight + m.spacing * index + 8;
	}

	function tickColor(index: number): string {
		return '#6366f1';
	}

	// ---------------------------------------------------------------------------
	// Pointer
	// ---------------------------------------------------------------------------

	function getTickAtY(y: number): number | null {
		const m = railMetrics();
		for (let i = 0; i < entries.length; i++) {
			const top = tickY(i);
			const bottom = top + m.tickHeight * entries[i].weight;
			if (y >= top && y <= bottom) return i;
		}
		return null;
	}

	function onPointerMove(e: PointerEvent) {
		if (!isDragging) return;
		const rect = rail?.getBoundingClientRect();
		if (!rect) return;
		const idx = getTickAtY(e.clientY - rect.top);
		if (idx !== null && idx !== hoveredIndex) {
			hoveredIndex = idx;
			onJump({ id: entries[idx].id });
		}
	}

	function onPointerUp() {
		isDragging = false;
		hoveredIndex = null;
	}

	function onPointerLeave() {
		if (!isDragging) return;
		isDragging = false;
		hoveredIndex = null;
	}

	// ---------------------------------------------------------------------------
	// Click / Tap
	// ---------------------------------------------------------------------------

	function onTickClick(index: number) {
		onJump({ id: entries[index].id });
	}

	function onRailMouseDown() {
		isDragging = true;
	}

	function onRailClick(e: MouseEvent) {
		const rect = rail?.getBoundingClientRect();
		if (!rect) return;
		const idx = getTickAtY(e.clientY - rect.top);
		if (idx !== null) {
			onJump({ id: entries[idx].id });
		}
	}
</script>

<div
	class="timeline-minimap"
	style="height: {height}px"
	role="navigation"
	aria-label="Thread timeline minimap"
>
	<div
		bind:this={rail}
		class="rail"
		onclick={onRailClick}
		onmousedown={onRailMouseDown}
		onmousemove={onPointerMove}
		onmouseup={onPointerUp}
		onmouseleave={onPointerLeave}
	>
		{#each entries as entry, index (entry.id)}
			{@const isActive = activeBlockId === entry.id}
			{@const isHovered = hoveredIndex === index}
			{@const m = railMetrics()}
			{@const y = tickY(index)}
			{@const w = 6 + entry.weight * 22}
			<div
				class="tick-wrapper"
				style="--tick-y: {y}px; --tick-w: {w}px"
			>
				<button
					class="tick"
					class:active={isActive}
					class:hovered={isHovered}
					style="width: {w}px; background: {isActive ? 'var(--chrome-accent, #6366f1)' : 'var(--chrome-overlay, rgba(0,0,0,0.25))'}"
					onclick={() => onTickClick(index)}
					aria-label={entry.label}
					title={entry.label}
				/>

				{#if isHovered || isActive}
					<div
						class="preview-bubble"
						class:active={isActive}
						style="top: calc({y}px + 14px); left: 44px;"
						role="tooltip"
					>
						<span class="preview-label">{entry.label}</span>
					</div>
				{/if}
			</div>
		{/each}
	</div>
</div>

<style>
	.timeline-minimap {
		position: relative;
		width: 100%;
		overflow: hidden;
		user-select: none;
		-webkit-user-select: none;
	}

	.rail {
		position: relative;
		height: 100%;
		display: flex;
		flex-direction: column;
		align-items: center;
		padding: 8px 4px;
		cursor: pointer;
		/* large hit target */
	}

	.tick-wrapper {
		position: relative;
		width: 100%;
		height: 0;
	}

	.tick {
		position: absolute;
		left: 50%;
		transform: translateX(-50%);
		top: 0;
		height: 6px;
		min-width: 4px;
		border-radius: 3px;
		border: none;
		padding: 0;
		cursor: pointer;
		transition:
			width 200ms ease,
			background 160ms ease,
			transform 120ms ease;
	}

	.tick:hover {
		transform: translateX(-50%) scaleX(1.4);
	}

	.tick.active {
		height: 8px;
		transform: translateX(-50%) scaleY(1.3);
		box-shadow: 0 0 6px rgba(99, 102, 241, 0.4);
	}

	.tick.hovered {
		height: 7px;
	}

	.preview-bubble {
		position: absolute;
		background: var(--chrome-surface, #1f2937);
		color: var(--chrome-primary, #f3f4f6);
		padding: 6px 10px;
		border-radius: 8px;
		font-size: 11px;
		white-space: nowrap;
		max-width: 220px;
		overflow: hidden;
		text-overflow: ellipsis;
		pointer-events: none;
		z-index: 20;
		box-shadow: 0 2px 8px rgba(0, 0, 0, 0.22);
		animation: bubbleIn 140ms ease;
		opacity: 0.95;
	}

	.preview-bubble.active {
		background: var(--chrome-accent, #6366f1);
	}

	.preview-label {
		font-weight: 500;
	}

	@keyframes bubbleIn {
		from {
			opacity: 0;
			transform: translateX(-4px);
		}
		to {
			opacity: 0.95;
			transform: translateX(0);
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.tick,
		.tick:hover,
		.preview-bubble {
			transition: none;
			animation: none;
		}
	}
</style>
