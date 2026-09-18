<script lang="ts">
	import type { Attachment, AttachmentInfo } from '$lib/types';
	import AttachmentPreview from './AttachmentPreview.svelte';

	interface Props {
		attachments: AttachmentInfo[];
		readonly?: boolean;
		maxItems?: number;
		accept?: string;
		onAdd: (files: AttachmentInfo[]) => void;
		onRemove: (attachment: AttachmentInfo) => void;
		onClick?: (attachment: AttachmentInfo) => void;
	}

	let { attachments, readonly = false, maxItems = 10, accept = '*/*', onAdd, onRemove, onClick }: Props = $props();

	let isDragOver = $state(false);
	let fileInput: HTMLInputElement | undefined = $state();
	let dropzoneRef: HTMLDivElement | undefined = $state();

	function pickFiles() {
		if (readonly) return;
		fileInput?.click();
	}

	async function handleFileChange(e: Event) {
		const target = e.target as HTMLInputElement;
		if (!target.files) return;
		await processFiles(Array.from(target.files));
		target.value = '';
	}

	async function processFiles(fileList: File[]) {
		const remaining = Math.max(0, maxItems - attachments.length);
		const sliced = fileList.slice(0, remaining);
		const newItems: AttachmentInfo[] = sliced.map((f) => ({
			id: crypto.randomUUID(),
			name: f.name,
			path: (f as any).path ?? f.name,
			mime_type: f.type || 'application/octet-stream'
		}));
		if (newItems.length > 0) onAdd(newItems);
	}

	function handleDragOver(e: DragEvent) {
		if (readonly) return;
		e.preventDefault();
		isDragOver = true;
	}

	function handleDragLeave(e: DragEvent) {
		e.preventDefault();
		if (dropzoneRef && e.target === dropzoneRef) {
			isDragOver = false;
		} else if (!dropzoneRef?.contains(e.relatedTarget as Node)) {
			isDragOver = false;
		}
	}

	async function handleDrop(e: DragEvent) {
		if (readonly) return;
		e.preventDefault();
		isDragOver = false;
		const files = e.dataTransfer?.files;
		if (files && files.length > 0) {
			await processFiles(Array.from(files));
		}
	}

	function handleRemove(a: AttachmentInfo) {
		if (readonly) return;
		onRemove(a);
	}

	function handleClick(a: AttachmentInfo) {
		onClick?.(a);
	}

	function handleKeyDown(e: KeyboardEvent) {
		if (readonly) return;
		if (e.key === 'Enter' || e.key === ' ') {
			e.preventDefault();
			pickFiles();
		}
	}

	$effect(() => {
		if (!isDragOver) return;
		const reset = () => { isDragOver = false; };
		window.addEventListener('dragend', reset);
		return () => window.removeEventListener('dragend', reset);
	});
</script>

<div
	bind:this={dropzoneRef}
	class="attachment-panel"
	class:readonly
	class:drag-over={isDragOver}
	ondragover={handleDragOver}
	ondragleave={handleDragLeave}
	ondrop={handleDrop}
	role="region"
	aria-label="Attachments"
>
	{#if attachments.length === 0 && !isDragOver}
		<button
			type="button"
			class="empty-upload"
			onclick={pickFiles}
			onkeydown={handleKeyDown}
			disabled={readonly}
			aria-label="Add attachments"
		>
			<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8">
				<path d="M21.44 11.05l-9.19 9.19a6 6 0 0 1-8.49-8.49l9.19-9.19a4 4 0 0 1 5.66 5.66l-9.2 9.19a2 2 0 0 1-2.83-2.83l8.49-8.48"/>
			</svg>
			<span class="empty-text">
				<strong>Drop files here</strong>
				<small>or click to browse</small>
			</span>
		</button>
	{:else}
		<div class="attachment-grid">
			{#each attachments as att (att.id)}
				<div class="grid-cell">
					<AttachmentPreview
						attachment={att}
						readonly={readonly}
						onRemove={() => handleRemove(att)}
						onExpand={() => handleClick(att)}
					/>
				</div>
			{/each}

			{#if !readonly && attachments.length < maxItems}
				<button
					type="button"
					class="upload-cell"
					onclick={pickFiles}
					onkeydown={handleKeyDown}
					aria-label="Add more attachments"
				>
					<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
						<path d="M12 5v14M5 12h14"/>
					</svg>
					<span class="upload-cell-label">Add</span>
				</button>
			{/if}
		</div>

		{#if isDragOver}
			<div class="drop-overlay">
				<svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
					<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
					<polyline points="17 8 12 3 7 8"/>
					<line x1="12" y1="3" x2="12" y2="15"/>
				</svg>
				<span>Drop files to add</span>
			</div>
		{/if}
	{/if}

	<input
		bind:this={fileInput}
		type="file"
		multiple
		accept={accept}
		onchange={handleFileChange}
		class="hidden-input"
		aria-hidden="true"
	/>
</div>

<style>
	.attachment-panel {
		position: relative;
		padding: var(--space-3);
		background: var(--surface-2);
		border: var(--border-1) var(--border-color-2);
		border-radius: var(--radius-md);
		min-height: 80px;
		transition: all var(--transition-fast);
	}

	.attachment-panel.drag-over {
		border-color: var(--accent-1);
		background: var(--accent-4);
	}

	.attachment-panel.readonly {
		background: transparent;
		border-style: dashed;
	}

	.empty-upload {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: var(--space-2);
		width: 100%;
		padding: var(--space-6) var(--space-4);
		border: 1px dashed var(--border-color-1);
		background: transparent;
		border-radius: var(--radius-md);
		color: var(--text-tertiary);
		cursor: pointer;
		font-family: inherit;
		transition: all var(--transition-fast);
	}

	.empty-upload:hover:not(:disabled) {
		border-color: var(--accent-1);
		color: var(--accent-1);
		background: var(--accent-4);
	}

	.empty-upload:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}

	.empty-text {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 2px;
	}

	.empty-text strong {
		font-size: var(--font-size-sm);
		font-weight: 600;
		color: var(--text-secondary);
	}

	.empty-text small {
		font-size: 11px;
		color: var(--text-tertiary);
	}

	.attachment-grid {
		display: flex;
		flex-wrap: wrap;
		gap: var(--space-2);
		align-items: flex-start;
	}

	.grid-cell {
		display: inline-flex;
	}

	.upload-cell {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 2px;
		width: 72px;
		height: 72px;
		border: 1px dashed var(--border-color-1);
		background: transparent;
		border-radius: 10px;
		color: var(--text-tertiary);
		cursor: pointer;
		font-family: inherit;
		font-size: 10px;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.3px;
		transition: all var(--transition-fast);
	}

	.upload-cell:hover {
		border-color: var(--accent-1);
		color: var(--accent-1);
		background: var(--accent-4);
	}

	.upload-cell-label {
		font-size: 9px;
	}

	.drop-overlay {
		position: absolute;
		inset: 0;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: var(--space-2);
		background: var(--accent-3);
		border-radius: var(--radius-md);
		color: var(--accent-1);
		font-size: var(--font-size-sm);
		font-weight: 600;
		pointer-events: none;
		animation: fade-in 120ms ease;
	}

	@keyframes fade-in {
		from { opacity: 0; }
		to { opacity: 1; }
	}

	.hidden-input {
		display: none;
	}
</style>
