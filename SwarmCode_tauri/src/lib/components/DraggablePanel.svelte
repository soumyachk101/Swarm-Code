<script lang="ts">
	// ---------------------------------------------------------------------------
	// DraggablePanel – a floating glass panel with drag handle.
	// Matches Swift's PlacedPanel + PanelDragHandle pattern.
	// ---------------------------------------------------------------------------

	import { createEventDispatcher } from 'svelte';
	import { dragMove, dragRelease, createDrag, clampPosition, nearestCorner, dockedPosition } from '$lib/utils/panelScene';

	interface Props {
		children: () => any;
		layout: { paneWidth: number; paneHeight: number; composerHeight: number; chromeHeight: number };
		corner?: 'top-leading' | 'top-trailing' | 'bottom-leading' | 'bottom-trailing';
		width?: number;
		height?: number;
	}

	let {
		children,
		layout,
		corner = $bindable('top-trailing'),
		width = 340,
		height = 280
	}: Props = $props();

	const dispatch = createEventDispatcher<{
		dragStart: void;
		dragMove: { x: number; y: number };
		dragEnd: { x: number; y: number };
	}>();

	let drag = createDrag();
	let isDragging = $state(false);
	let panelPos = $state({ x: 0, y: 0 });
	let panelEl: HTMLDivElement | undefined = $state();

	const pw = $derived(Math.min(400, Math.max(300, layout.paneWidth - 40)));
	const restPos = $derived(dockedPosition(corner, layout));

	function initPosition() {
		if (!isDragging) {
			panelPos = { ...restPos };
		}
	}

	$effect(() => {
		if (!isDragging) {
			panelPos = { ...restPos };
		}
	});

	function onPointerDown(e: PointerEvent) {
		e.preventDefault();
		isDragging = true;
		drag = createDrag();
		drag.grab = { ...panelPos };
		drag.lastMoveTime = performance.now();
		panelEl?.setPointerCapture(e.pointerId);
		dispatch('dragStart');
	}

	function onPointerMove(e: PointerEvent) {
		if (!isDragging) return;
		const now = performance.now();
		const next = dragMove(drag, { x: e.movementX, y: e.movementY }, panelPos, now);
		const clamped = clampPosition(next, layout);
		panelPos = clamped;
		dispatch('dragMove', clamped);
	}

	function onPointerUp(e: PointerEvent) {
		if (!isDragging) return;
		isDragging = false;
		const now = performance.now();
		const released = dragRelease(drag, now);
		if (released) {
			const clamped = clampPosition(released, layout);
			panelPos = clamped;
			corner = nearestCorner(clamped, layout);
		}
		panelEl?.releasePointerCapture(e.pointerId);
		dispatch('dragEnd', panelPos);
	}

	// Initialize position when layout changes
	$effect(() => {
		if (!isDragging) {
			panelPos = { ...restPos };
		}
	});
</script>

<div
	class="draggable-panel"
	class:dragging={isDragging}
	bind:this={panelEl}
	style="
		left: {panelPos.x}px;
		top: {panelPos.y}px;
		width: {pw}px;
		height: {height}px;
	"
	role="dialog"
>
	<!-- Drag handle strip -->
	<div
		class="panel-drag-handle"
		onpointerdown={onPointerDown}
		onpointermove={onPointerMove}
		onpointerup={onPointerUp}
	>
		<div class="panel-handle-bar"></div>
		<slot name="handle" />
	</div>

	<!-- Panel content -->
	<div class="panel-body">
		{@render children()}
	</div>
</div>

<style>
	.draggable-panel {
		position: absolute;
		z-index: 50;
		border-radius: 18px;
		background: color-mix(in srgb, var(--surface-0) 75%, transparent);
		backdrop-filter: blur(24px) saturate(1.5);
		-webkit-backdrop-filter: blur(24px) saturate(1.5);
		border: 1px solid var(--border-subtle);
		box-shadow:
			0 8px 32px rgba(0, 0, 0, 0.12),
			0 2px 8px rgba(0, 0, 0, 0.06);
		display: flex;
		flex-direction: column;
		overflow: hidden;
		transition: box-shadow 0.2s ease;
	}

	.draggable-panel.dragging {
		box-shadow:
			0 12px 48px rgba(0, 0, 0, 0.18),
			0 4px 12px rgba(0, 0, 0, 0.08);
		cursor: grabbing;
	}

	.panel-drag-handle {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 8px 12px 4px;
		cursor: grab;
		user-select: none;
		touch-action: none;
		flex-shrink: 0;
	}

	.panel-drag-handle:active {
		cursor: grabbing;
	}

	.panel-handle-bar {
		width: 32px;
		height: 4px;
		border-radius: 2px;
		background: var(--border-subtle);
		flex-shrink: 0;
	}

	.panel-body {
		flex: 1;
		overflow-y: auto;
		padding: 0 12px 12px;
	}
</style>
