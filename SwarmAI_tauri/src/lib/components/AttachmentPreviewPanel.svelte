<script lang="ts">
	// ---------------------------------------------------------------------------
	// AttachmentPreviewPanel – expanded preview for a single attachment
	// Matches AttachmentPreviewPanel.swift: image zoom, file info, actions.
	// ---------------------------------------------------------------------------

	import type { Attachment } from '$lib/types';

	// ---------------------------------------------------------------------------
	// Props
	// ---------------------------------------------------------------------------

	interface Props {
		attachment: Attachment;
		open: boolean;
		readonly?: boolean;
		onClose: () => void;
		onOpenFile: (attachment: Attachment) => void;
		onReveal: (attachment: Attachment) => void;
		onRemove: (attachment: Attachment) => void;
	}

	let { attachment, open, readonly = false, onClose, onOpenFile, onReveal, onRemove }: Props = $props();

	// ---------------------------------------------------------------------------
	// State
	// ---------------------------------------------------------------------------

	let scale = $state(1);
	let translateX = $state(0);
	let translateY = $state(0);
	let modalRef: HTMLDivElement | undefined = $state();
	let imageRef: HTMLImageElement | undefined = $state();
	let imageContainerRef: HTMLDivElement | undefined = $state();

	// ---------------------------------------------------------------------------
	// Derived
	// ---------------------------------------------------------------------------

	let isImage = $derived(attachment.mime_type.startsWith('image/'));
	let fileSize = $derived(() => {
		const match = attachment.path.match(/\/(\d+(?:\.\d+)?)([KMGTP]?B?)$/i);
		return match ? match[0] : 'Unknown';
	});
	let zoomPercent = $derived(Math.round(scale * 100));

	// ---------------------------------------------------------------------------
	// Reset transform
	// ---------------------------------------------------------------------------

	function resetTransform() {
		scale = 1;
		translateX = 0;
		translateY = 0;
	}

	$effect(() => {
		if (!open) resetTransform();
	});

	// ---------------------------------------------------------------------------
	// Image zoom (wheel)
	// ---------------------------------------------------------------------------

	function onWheel(event: WheelEvent) {
		if (!isImage) return;
		event.preventDefault();
		const delta = event.deltaY > 0 ? -0.08 : 0.08;
		scale = Math.min(4, Math.max(0.25, scale + delta));
		if (scale === 1) {
			translateX = 0;
			translateY = 0;
		}
	}

	// ---------------------------------------------------------------------------
	// Image pan (drag)
	// ---------------------------------------------------------------------------

	let dragging = $state(false);
	let dragStartX = $state(0);
	let dragStartY = $state(0);
	let dragTransX = $state(0);
	let dragTransY = $state(0);

	function onMouseDown(e: MouseEvent) {
		if (!isImage || scale <= 1) return;
		dragging = true;
		dragStartX = e.clientX;
		dragStartY = e.clientY;
		dragTransX = translateX;
		dragTransY = translateY;
	}

	function onMouseMove(e: MouseEvent) {
		if (!dragging) return;
		translateX = dragTransX + (e.clientX - dragStartX) / scale;
		translateY = dragTransY + (e.clientY - dragStartY) / scale;
	}

	function onMouseUp() {
		dragging = false;
	}

	// ---------------------------------------------------------------------------
	// Keyboard
	// ---------------------------------------------------------------------------

	function onKeydown(e: KeyboardEvent) {
		if (e.key === 'Escape') {
			onClose();
		} else if (e.key === '=' || e.key === '+') {
			scale = Math.min(4, scale + 0.25);
		} else if (e.key === '-') {
			scale = Math.max(0.25, scale - 0.25);
			if (scale <= 1) resetTransform();
		} else if (e.key === '0') {
			resetTransform();
		}
	}

	// ---------------------------------------------------------------------------
	// Actions
	// ---------------------------------------------------------------------------

	function openFile() {
		onOpenFile(attachment);
	}

	function reveal() {
		onReveal(attachment);
	}

	function remove() {
		onRemove(attachment);
	}

	// Close on backdrop click
	function onBackdropClick(e: MouseEvent) {
		if (e.target === modalRef) {
			onClose();
		}
	}
</script>

{#if open}
	<div
		bind:this={modalRef}
		class="preview-panel"
		onclick={onBackdropClick}
		onkeydown={onKeydown}
		role="dialog"
		aria-label={`Previewing ${attachment.name}`}
	>
		<!-- Header -->
		<header class="panel-header">
			<span class="file-name">{attachment.name}</span>
			<div class="header-actions">
				<span class="mime-type">{attachment.mime_type}</span>
				{#if isImage}
					<span class="zoom-label">{zoomPercent}%</span>
				{/if}
				<button class="icon-btn" onclick={reveal} type="button" title="Reveal in Finder">⤴</button>
				<button class="icon-btn" onclick={openFile} type="button" title="Open file">⏵</button>
				{#if !readonly}
					<button class="icon-btn danger" onclick={remove} type="button" title="Remove">✕</button>
				{/if}
				<button class="icon-btn" onclick={onClose} type="button" aria-label="Close">✕</button>
			</div>
		</header>

		<!-- Body -->
		<div class="panel-body">
			<!-- Image viewer -->
			{#if isImage}
				<div
					bind:this={imageContainerRef}
					class="image-container"
					onwheel={onWheel}
					onmousedown={onMouseDown}
					onmousemove={onMouseMove}
					onmouseup={onMouseUp}
					onmouseleave={onMouseUp}
				>
					<img
						bind:this={imageRef}
						src={attachment.path}
						alt={attachment.name}
						class="preview-image"
						style="transform: scale({scale}) translate({translateX}px, {translateY}px); cursor: {scale > 1 ? 'grab' : 'zoom-in'};"
						draggable={false}
					/>
				</div>
			{:else}
				<div class="fallback-viewer">
					<span class="fallback-icon">📄</span>
					<p class="fallback-text">Preview not available for this file type.</p>
					<button class="fallback-action" onclick={openFile} type="button">
						Open externally
					</button>
				</div>
			{/if}
		</div>

		<!-- Footer / zoom controls -->
		{#if isImage}
			<footer class="panel-footer">
				<div class="zoom-controls">
					<button class="zoom-btn" onclick={() => { scale = Math.max(0.25, scale - 0.25); if (scale <= 1) resetTransform(); }} type="button">−</button>
					<input
						type="range"
						class="zoom-range"
						min="0.25"
						max="4"
						step="0.25"
						value={scale}
						oninput={(e) => {
							const v = parseFloat((e.target as HTMLInputElement).value);
							if (!isNaN(v)) {
								scale = v;
								if (v === 1) resetTransform();
							}
						}}
					/>
					<button class="zoom-btn" onclick={() => { scale = Math.min(4, scale + 0.25); }} type="button">+</button>
					<button class="zoom-reset-btn" onclick={resetTransform} type="button">Reset</button>
				</div>
				<div class="file-info">
					<span>{attachment.name}</span>
					<span>{attachment.mime_type}</span>
					<span>{attachment.path}</span>
				</div>
			</footer>
		{/if}
	</div>
{/if}

<style>
	.preview-panel {
		position: fixed;
		inset: 0;
		z-index: 200;
		background: rgba(0, 0, 0, 0.82);
		backdrop-filter: blur(8px);
		display: flex;
		flex-direction: column;
		animation: fadeIn 150ms ease;
		font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', sans-serif;
	}

	@keyframes fadeIn {
		from { opacity: 0; }
		to { opacity: 1; }
	}

	.panel-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 12px;
		padding: 12px 16px;
		border-bottom: 1px solid rgba(255, 255, 255, 0.08);
		flex-wrap: wrap;
	}

	.file-name {
		font-size: 13px;
		font-weight: 500;
		color: #e5e7eb;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		flex: 1;
		min-width: 120px;
	}

	.header-actions {
		display: flex;
		align-items: center;
		gap: 8px;
	}

	.mime-type {
		font-size: 11px;
		color: #9ca3af;
		font-family: 'SF Mono', monospace;
	}

	.zoom-label {
		font-size: 11px;
		color: #6b7280;
		font-variant-numeric: tabular-nums;
		min-width: 40px;
		text-align: center;
	}

	.icon-btn {
		appearance: none;
		border: 1px solid rgba(255, 255, 255, 0.1);
		background: transparent;
		color: #d1d5db;
		width: 28px;
		height: 28px;
		border-radius: 7px;
		cursor: pointer;
		font-size: 12px;
		display: flex;
		align-items: center;
		justify-content: center;
		transition: all 140ms ease;
		font-family: inherit;
		line-height: 1;
	}

	.icon-btn:hover {
		background: rgba(255, 255, 255, 0.08);
		color: #ffffff;
	}

	.icon-btn.danger:hover {
		background: #ef444430;
		color: #ef4444;
		border-color: #ef444450;
	}

	/* ── Body ── */

	.panel-body {
		flex: 1;
		display: flex;
		align-items: center;
		justify-content: center;
		overflow: hidden;
		padding: 20px;
	}

	.image-container {
		max-width: 100%;
		max-height: 100%;
		overflow: auto;
		display: flex;
		align-items: center;
		justify-content: center;
		cursor: zoom-in;
	}

	.preview-image {
		max-width: 100%;
		max-height: calc(100vh - 180px);
		object-fit: contain;
		border-radius: 8px;
		user-select: none;
		transform-origin: center center;
		transition: transform 100ms ease;
		box-shadow: 0 4px 20px rgba(0, 0, 0, 0.4);
	}

	.fallback-viewer {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 16px;
		color: #9ca3af;
	}

	.fallback-icon {
		font-size: 48px;
		opacity: 0.5;
	}

	.fallback-text {
		font-size: 14px;
		margin: 0;
	}

	.fallback-action {
		appearance: none;
		border: 1px solid rgba(255, 255, 255, 0.15);
		background: transparent;
		color: #d1d5db;
		font-size: 13px;
		font-weight: 500;
		padding: 8px 16px;
		border-radius: 8px;
		cursor: pointer;
		transition: all 140ms;
		font-family: inherit;
	}

	.fallback-action:hover {
		background: rgba(255, 255, 255, 0.08);
	}

	/* ── Footer ── */

	.panel-footer {
		padding: 10px 16px;
		border-top: 1px solid rgba(255, 255, 255, 0.08);
		display: flex;
		flex-direction: column;
		gap: 6px;
	}

	.zoom-controls {
		display: flex;
		align-items: center;
		gap: 8px;
	}

	.zoom-btn {
		appearance: none;
		border: 1px solid rgba(255, 255, 255, 0.12);
		background: transparent;
		color: #d1d5db;
		width: 28px;
		height: 28px;
		border-radius: 7px;
		cursor: pointer;
		font-size: 16px;
		display: flex;
		align-items: center;
		justify-content: center;
		transition: all 140ms;
		font-family: inherit;
		line-height: 1;
	}

	.zoom-btn:hover {
		background: rgba(255, 255, 255, 0.08);
	}

	.zoom-range {
		flex: 1;
		accent-color: #6366f1;
	}

	.zoom-reset-btn {
		appearance: none;
		border: 1px solid rgba(255, 255, 255, 0.1);
		background: transparent;
		color: #9ca3af;
		font-size: 11px;
		padding: 4px 10px;
		border-radius: 6px;
		cursor: pointer;
		transition: all 140ms;
		font-family: inherit;
	}

	.zoom-reset-btn:hover {
		background: rgba(255, 255, 255, 0.08);
		color: #d1d5db;
	}

	.file-info {
		display: flex;
		gap: 12px;
		font-size: 10px;
		color: #6b7280;
		overflow: hidden;
	}

	.file-info span {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	@media (prefers-reduced-motion: reduce) {
		.preview-panel,
		.preview-image {
			animation: none;
			transition: none;
		}
	}

	@media (max-width: 480px) {
		.panel-header {
			padding: 10px 12px;
		}
		.preview-image {
			max-height: calc(100vh - 220px);
		}
	}
</style>
