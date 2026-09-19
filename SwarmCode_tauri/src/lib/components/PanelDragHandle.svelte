<script lang="ts">
	// ---------------------------------------------------------------------------
	// PanelDragHandle – pointer-capture drag handle for floating panels.
	// Use inside a panel's header strip.
	// ---------------------------------------------------------------------------

	interface Props {
		onDrag?: (dx: number, dy: number) => void;
		onDragEnd?: () => void;
		disabled?: boolean;
		children?: () => any;
	}

	let { onDrag, onDragEnd, disabled = false, children }: Props = $props();

	let isDragging = $state(false);
	let dragStart = $state({ x: 0, y: 0 });
	let panelStart = $state({ x: 0, y: 0 });
	let panelEl: HTMLDivElement | undefined = $state();

	function onPointerDown(e: PointerEvent) {
		if (disabled) return;
		e.preventDefault();
		isDragging = true;
		dragStart = { x: e.clientX, y: e.clientY };
		// Read current position from the panel element
		if (panelEl) {
			const rect = panelEl.getBoundingClientRect();
			const parentRect = panelEl.parentElement?.getBoundingClientRect();
			if (parentRect) {
				panelStart = { x: rect.left - parentRect.left, y: rect.top - parentRect.top };
			}
		}
		panelEl?.setPointerCapture(e.pointerId);
	}

	function onPointerMove(e: PointerEvent) {
		if (!isDragging) return;
		const dx = e.clientX - dragStart.x;
		const dy = e.clientY - dragStart.y;
		onDrag?.(dx, dy);
	}

	function onPointerUp(e: PointerEvent) {
		if (!isDragging) return;
		isDragging = false;
		panelEl?.releasePointerCapture(e.pointerId);
		onDragEnd?.();
	}
</script>

<div
	class="panel-drag-handle"
	class:dragging={isDragging}
	class:disabled
	onpointerdown={onPointerDown}
	onpointermove={onPointerMove}
	onpointerup={onPointerUp}
	onpointercancel={onPointerUp}
>
	{#if children}
		{@render children()}
	{:else}
		<div class="drag-grip">
			<div class="grip-dot"></div>
			<div class="grip-dot"></div>
			<div class="grip-dot"></div>
		</div>
	{/if}
</div>

<style>
	.panel-drag-handle {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 8px;
		padding: 6px 12px;
		cursor: grab;
		user-select: none;
		touch-action: none;
		transition: background 0.15s;
	}

	.panel-drag-handle:hover {
		background: rgba(255, 255, 255, 0.04);
	}

	.panel-drag-handle.dragging {
		cursor: grabbing;
		background: rgba(255, 255, 255, 0.06);
	}

	.panel-drag-handle.disabled {
		cursor: default;
		opacity: 0.5;
	}

	.drag-grip {
		display: flex;
		gap: 3px;
		padding: 4px 0;
	}

	.grip-dot {
		width: 4px;
		height: 4px;
		border-radius: 50%;
		background: var(--text-tertiary, rgba(128, 128, 128, 0.5));
		transition: background 0.15s;
	}

	.panel-drag-handle:hover .grip-dot {
		background: var(--text-secondary, rgba(160, 160, 160, 0.7));
	}
</style>
