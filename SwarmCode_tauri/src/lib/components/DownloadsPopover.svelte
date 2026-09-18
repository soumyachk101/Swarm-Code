<script lang="ts">
	// ---------------------------------------------------------------------------
	// DownloadsPopover – popover listing downloaded files from AI responses
	// Matches DownloadsPopover.swift
	// ---------------------------------------------------------------------------

	export interface Download {
		id: string;
		path: string;
		name: string;
		size: number;
		mime_type: string;
		created_at: string;
	}

	// ---------------------------------------------------------------------------
	// Props
	// ---------------------------------------------------------------------------

	interface Props {
		downloads: Download[];
		readonly?: boolean;
		onClear: () => void;
		onOpen: (download: Download) => void;
		onReveal: (download: Download) => void;
		onRemove: (download: Download) => void;
	}

	let { downloads = [], readonly = false, onClear, onOpen, onReveal, onRemove }: Props = $props();

	// ---------------------------------------------------------------------------
	// State
	// ---------------------------------------------------------------------------

	let triggerRef: HTMLDivElement | undefined = $state();
	let popoverRef: HTMLDivElement | undefined = $state();
	let open = $state(false);

	// Close on outside click
	$effect(() => {
		if (!open) return;
		const handler = (e: MouseEvent) => {
			const t = e.target as Node;
			if (triggerRef?.contains(t) || popoverRef?.contains(t)) return;
			open = false;
		};
		document.addEventListener('mousedown', handler);
		return () => document.removeEventListener('mousedown', handler);
	});

	// ---------------------------------------------------------------------------
	// Derived
	// ---------------------------------------------------------------------------

	let totalSize = $derived(downloads.reduce((s, d) => s + d.size, 0));

	let iconForMime = $derived((mime: string) => {
		if (mime.startsWith('image/')) return '🖼️';
		if (mime.startsWith('video/')) return '🎬';
		if (mime.startsWith('audio/')) return '🎵';
		if (mime.startsWith('text/')) return '📄';
		if (mime.includes('zip') || mime.includes('tar') || mime.includes('gzip')) return '🗜️';
		if (mime.includes('json')) return '📋';
		if (mime.includes('pdf')) return '📕';
		return '📁';
	});

	function formatSize(bytes: number): string {
		if (bytes < 1024) return `${bytes} B`;
		if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
		if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
		return `${(bytes / 1024 / 1024 / 1024).toFixed(2)} GB`;
	}

	function formatTime(iso: string): string {
		const date = new Date(iso);
		const now = new Date();
		const diffMs = now.getTime() - date.getTime();
		const diffMin = Math.floor(diffMs / 60000);
		if (diffMin < 1) return 'just now';
		if (diffMin < 60) return `${diffMin}m ago`;
		const diffHr = Math.floor(diffMin / 60);
		if (diffHr < 24) return `${diffHr}h ago`;
		return date.toLocaleDateString();
	}
</script>

<div class="popover-root">
	<div bind:this={triggerRef}>
		<button
			class="trigger"
			class:active={open}
			onclick={() => (open = !open)}
			type="button"
			aria-haspopup="dialog"
			aria-expanded={open}
		>
			<span class="trigger-icon">⬇</span>
			{#if downloads.length > 0}
				<span class="trigger-badge">{downloads.length}</span>
			{/if}
		</button>
	</div>

	{#if open}
		<div bind:this={popoverRef} class="popover" role="dialog" aria-label="Downloads">
			<header class="popover-header">
				<span class="popover-title">Downloads</span>
				<span class="popover-meta">
					{downloads.length}
					{#if downloads.length > 0}
						· {formatSize(totalSize)}
					{/if}
				</span>
			</header>

			<div class="list">
				{#if downloads.length === 0}
					<div class="empty">
						<span class="empty-icon">📭</span>
						<p class="empty-text">No files have been downloaded yet.</p>
					</div>
				{:else}
					{#each downloads as d (d.id)}
						<div class="item">
							<span class="file-icon">{iconForMime(d.mime_type)}</span>
							<div class="info">
								<span class="name" title={d.path}>{d.name}</span>
								<span class="meta">
									{formatSize(d.size)} · {formatTime(d.created_at)}
								</span>
							</div>
							{#if !readonly}
								<div class="actions">
									<button class="action" onclick={() => onOpen(d)} type="button" title="Open file">⏵</button>
									<button class="action" onclick={() => onReveal(d)} type="button" title="Reveal in Finder">⤴</button>
									<button class="action danger" onclick={() => onRemove(d)} type="button" title="Remove">✕</button>
								</div>
							{/if}
						</div>
					{/each}
				{/if}
			</div>

			{#if downloads.length > 0 && !readonly}
				<footer class="popover-footer">
					<button class="clear-btn" onclick={onClear} type="button">Clear all</button>
				</footer>
			{/if}
		</div>
	{/if}
</div>

<style>
	.popover-root {
		position: relative;
		display: inline-flex;
	}

	.trigger {
		appearance: none;
		border: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.1));
		background: var(--chrome-surface, transparent);
		color: var(--chrome-secondary, #6b7280);
		width: 32px;
		height: 32px;
		border-radius: 8px;
		cursor: pointer;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		position: relative;
		transition: all 140ms ease;
		font-family: inherit;
		font-size: 14px;
	}

	.trigger:hover {
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.04));
	}

	.trigger.active {
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.06));
	}

	.trigger-badge {
		position: absolute;
		top: -3px;
		right: -3px;
		min-width: 16px;
		height: 16px;
		padding: 0 4px;
		background: var(--chrome-accent, #6366f1);
		color: #ffffff;
		font-size: 10px;
		font-weight: 700;
		border-radius: 8px;
		display: flex;
		align-items: center;
		justify-content: center;
		line-height: 1;
	}

	/* ── Popover ── */

	.popover {
		position: absolute;
		top: calc(100% + 8px);
		right: 0;
		width: 360px;
		max-height: 460px;
		background: var(--chrome-surface, #ffffff);
		border: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.1));
		border-radius: 12px;
		box-shadow: 0 8px 30px rgba(0, 0, 0, 0.14), 0 2px 6px rgba(0, 0, 0, 0.06);
		z-index: 50;
		overflow: hidden;
		display: flex;
		flex-direction: column;
		font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', sans-serif;
		animation: popoverIn 160ms ease;
	}

	@keyframes popoverIn {
		from {
			opacity: 0;
			transform: translateY(-4px) scale(0.97);
		}
		to {
			opacity: 1;
			transform: translateY(0) scale(1);
		}
	}

	.popover-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 10px 14px;
		border-bottom: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.06));
	}

	.popover-title {
		font-size: 13px;
		font-weight: 600;
		color: var(--chrome-primary, #111827);
	}

	.popover-meta {
		font-size: 11px;
		color: var(--chrome-secondary, #6b7280);
	}

	.list {
		overflow-y: auto;
		padding: 4px;
		flex: 1;
		min-height: 80px;
	}

	.item {
		display: grid;
		grid-template-columns: 28px 1fr auto;
		align-items: center;
		gap: 10px;
		padding: 8px 10px;
		border-radius: 8px;
		transition: background 120ms;
	}

	.item:hover {
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.04));
	}

	.file-icon {
		font-size: 20px;
		text-align: center;
	}

	.info {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}

	.name {
		font-size: 12px;
		font-weight: 500;
		color: var(--chrome-primary, #111827);
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.meta {
		font-size: 10px;
		color: var(--chrome-secondary, #9ca3af);
	}

	.actions {
		display: flex;
		gap: 2px;
	}

	.action {
		appearance: none;
		border: none;
		background: transparent;
		color: var(--chrome-secondary, #6b7280);
		font-size: 12px;
		padding: 4px 6px;
		border-radius: 6px;
		cursor: pointer;
		transition: all 120ms;
		font-family: inherit;
		line-height: 1;
	}

	.action:hover {
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.08));
		color: var(--chrome-primary, #111827);
	}

	.action.danger:hover {
		background: #ef444415;
		color: #ef4444;
	}

	.empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 8px;
		padding: 28px 16px;
		color: var(--chrome-secondary, #6b7280);
	}

	.empty-icon {
		font-size: 24px;
		opacity: 0.5;
	}

	.empty-text {
		font-size: 12px;
		text-align: center;
		margin: 0;
	}

	.popover-footer {
		border-top: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.06));
		padding: 8px;
		display: flex;
		justify-content: center;
	}

	.clear-btn {
		appearance: none;
		border: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.08));
		background: transparent;
		color: var(--chrome-secondary, #6b7280);
		font-size: 11px;
		font-weight: 500;
		padding: 5px 12px;
		border-radius: 8px;
		cursor: pointer;
		transition: all 140ms;
		font-family: inherit;
	}

	.clear-btn:hover {
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.04));
		color: var(--chrome-primary, #111827);
	}

	@media (prefers-reduced-motion: reduce) {
		.popover {
			animation: none;
		}
	}
</style>
