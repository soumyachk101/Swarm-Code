<script lang="ts">
	import type { Attachment } from '$lib/types';

	// ---------------------------------------------------------------------------
	// AttachmentPreview – compact inline preview of a file attachment
	// ---------------------------------------------------------------------------

	interface Props {
		attachment: Attachment;
		readonly?: boolean;
		onRemove?: (attachment: Attachment) => void;
		onExpand?: (attachment: Attachment) => void;
	}

	let { attachment, readonly = false, onRemove, onExpand }: Props = $props();

	// ---------------------------------------------------------------------------
	// Derived
	// ---------------------------------------------------------------------------

	let isImage = $derived(attachment.mime_type.startsWith('image/'));
	let isVideo = $derived(attachment.mime_type.startsWith('video/'));
	let isAudio = $derived(attachment.mime_type.startsWith('audio/'));
	let fileExt = $derived(() => {
		const parts = attachment.name.split('.');
		return parts.length > 1 ? parts[parts.length - 1].toUpperCase() : '';
	});

	let thumbnailUrl = $derived(() => {
		if (!isImage) return null;
		// In Tauri, files are accessed via asset:// or local file:// protocol.
		// The invoker may provide a dedicated thumbnail URL; for now we use the path.
		return attachment.path;
	});

	function handleRemove() {
		if (readonly || !onRemove) return;
		onRemove(attachment);
	}

	function handleExpand() {
		if (!onExpand) return;
		onExpand(attachment);
	}
</script>

<div
	class="attachment-preview"
	class:is-image={isImage}
	role="img"
	aria-label={attachment.name}
>
	<!-- Image thumbnail -->
	{#if isImage && thumbnailUrl}
		<button
			class="image-thumb"
			onclick={handleExpand}
			type="button"
			aria-label={`Expand ${attachment.name}`}
		>
			<img
				src={thumbnailUrl}
				alt={attachment.name}
				loading="lazy"
				class="thumb-img"
			/>
		</button>
	{:else if isVideo}
		<button class="media-thumb" onclick={handleExpand} type="button" aria-label="Video attachment">
			<span class="media-icon">🎬</span>
			<span class="file-ext-badge">{fileExt()}</span>
		</button>
	{:else if isAudio}
		<button class="media-thumb" onclick={handleExpand} type="button" aria-label="Audio attachment">
			<span class="media-icon">🎵</span>
			<span class="file-ext-badge">{fileExt()}</span>
		</button>
	{:else}
		<button class="file-thumb" onclick={handleExpand} type="button" aria-label={`Open ${attachment.name}`}>
			<span class="file-icon">📄</span>
			<span class="file-ext-badge">{fileExt()}</span>
		</button>
	{/if}

	<!-- Remove -->
	{#if !readonly}
		<button
			class="remove-btn"
			onclick={handleRemove}
			type="button"
			aria-label={`Remove ${attachment.name}`}
			title="Remove attachment"
		>✕</button>
	{/if}
</div>

<style>
	.attachment-preview {
		position: relative;
		display: inline-flex;
		flex-shrink: 0;
	}

	/* ── Image ── */

	.image-thumb {
		appearance: none;
		border: none;
		background: transparent;
		padding: 0;
		cursor: pointer;
		border-radius: 10px;
		overflow: hidden;
		display: flex;
		transition: opacity 160ms ease;
	}

	.image-thumb:hover {
		opacity: 0.85;
	}

	.thumb-img {
		display: block;
		width: 72px;
		height: 72px;
		object-fit: cover;
		border-radius: 10px;
	}

	/* ── Media ── */

	.media-thumb {
		appearance: none;
		border: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.08));
		background: var(--chrome-surface, transparent);
		width: 72px;
		height: 72px;
		border-radius: 10px;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 4px;
		cursor: pointer;
		transition: all 160ms ease;
		font-family: inherit;
		position: relative;
	}

	.media-thumb:hover {
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.04));
	}

	.media-icon {
		font-size: 22px;
	}

	.file-ext-badge {
		font-size: 8px;
		font-weight: 700;
		text-transform: uppercase;
		color: var(--chrome-secondary, #6b7280);
		letter-spacing: 0.06em;
	}

	/* ── Generic file ── */

	.file-thumb {
		appearance: none;
		border: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.08));
		background: var(--chrome-surface, transparent);
		width: 72px;
		height: 72px;
		border-radius: 10px;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 4px;
		cursor: pointer;
		transition: all 160ms ease;
		font-family: inherit;
	}

	.file-thumb:hover {
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.04));
	}

	.file-icon {
		font-size: 22px;
	}

	/* ── Remove ── */

	.remove-btn {
		appearance: none;
		border: none;
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.15));
		color: var(--chrome-primary, #111827);
		width: 16px;
		height: 16px;
		border-radius: 50%;
		cursor: pointer;
		font-size: 9px;
		display: flex;
		align-items: center;
		justify-content: center;
		position: absolute;
		top: -4px;
		right: -4px;
		transition: background 120ms;
		padding: 0;
		line-height: 1;
	}

	.remove-btn:hover {
		background: #ef4444;
		color: #ffffff;
	}

	@media (prefers-reduced-motion: reduce) {
		.image-thumb,
		.media-thumb,
		.file-thumb,
		.remove-btn {
			transition: none;
		}
	}
</style>
