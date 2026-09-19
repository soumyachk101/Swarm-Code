<script lang="ts">
	// ---------------------------------------------------------------------------
	// FollowUpQueueTab – queued steering prompts above the composer.
	// Uses project types: FollowUpPrompt, Attachment.
	// ---------------------------------------------------------------------------

	import type { FollowUpPrompt, Attachment } from '$lib/types';

	interface Props {
		prompts: FollowUpPrompt[];
		isRunning: boolean;
		onSendNow: (id: string) => void;
		onEdit: (id: string, text: string, attachments: Attachment[]) => void;
		onDelete: (id: string) => void;
		onMove: (id: string, beforeId: string | null) => void;
	}

	let { prompts, isRunning, onSendNow, onEdit, onDelete, onMove }: Props = $props();

	let isCollapsed = $state(false);

	// Edit popover state
	let editingId = $state<string | null>(null);
	let editText = $state('');
	let editAttachments = $state<Attachment[]>([]);
	let editAnchor: HTMLElement | null = $state(null);
	let showAddFiles = $state(false);

	// Reorder state
	let draggedId: string | null = $state(null);
	let dragOverId: string | null = $state(null);
	let dropBefore = $state(true);

	function startEdit(prompt: FollowUpPrompt, anchorEl: HTMLElement) {
		editingId = prompt.id;
		editText = prompt.text;
		editAttachments = [...prompt.attachments];
		editAnchor = anchorEl;
		showAddFiles = false;
	}

	function closeEdit() {
		if (editingId) {
			const text = editText.trim();
			const atts = editAttachments.filter(a => !a._removed);
			if (text || atts.length > 0) {
				onEdit(editingId, editText, atts);
			}
		}
		editingId = null;
		editText = '';
		editAttachments = [];
		editAnchor = null;
	}

	function saveEdit() {
		if (editingId) {
			const atts = editAttachments.filter(a => !a._removed);
			onEdit(editingId, editText, atts);
		}
		editingId = null;
		editText = '';
		editAttachments = [];
		editAnchor = null;
	}

	function addEditAttachment() {
		const input = document.createElement('input');
		input.type = 'file';
		input.multiple = true;
		input.onchange = () => {
			const files = input.files;
			if (!files) return;
			for (const file of files) {
				const id = crypto.randomUUID();
				editAttachments = [
					...editAttachments,
					{ id, name: file.name, path: file.name, size: file.size, kind: file.type.startsWith('image/') ? 'image' : 'file' }
				];
			}
		};
		input.click();
	}

	function removeEditAttachment(id: string) {
		editAttachments = editAttachments.map(a => a.id === id ? { ...a, _removed: true } : a);
	}

	function handleDragStart(id: string) {
		draggedId = id;
	}

	function handleDragOver(id: string, before: boolean) {
		dragOverId = id;
		dropBefore = before;
	}

	function handleDrop(targetId: string) {
		if (draggedId && draggedId !== targetId) {
			onMove(draggedId, dropBefore ? targetId : null);
		}
		draggedId = null;
		dragOverId = null;
	}

	function handleDragEnd() {
		draggedId = null;
		dragOverId = null;
	}

	function getAttachmentLabel(p: FollowUpPrompt): string {
		const imgs = p.attachments.filter(a => a.is_image).length;
		const files = p.attachments.length - imgs;
		const parts: string[] = [];
		if (imgs === 1) parts.push('1 image');
		else if (imgs > 1) parts.push(`${imgs} images`);
		if (files === 1) parts.push('1 file');
		else if (files > 1) parts.push(`${files} files`);
		return parts.length > 0 ? parts.join(', ') : 'Empty follow-up';
	}

	let countLabel = $derived(prompts.length === 1 ? '1 follow-up' : `${prompts.length} follow-ups`);
</script>

<div class="followup-tab" role="region" aria-label="Follow-up queue">
	<header class="fq-header">
		<span class="fq-icon" aria-hidden="true">
			<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
				<path d="M7 7h10v3l4-4-4-4v3H5v6h4v4H7z"/>
				<line x1="12" y1="14" x2="12" y2="21"/>
			</svg>
		</span>
		<span class="fq-count">{countLabel}</span>
		<span class="fq-suffix">queued</span>
		<button
			type="button"
			class="fq-collapse-btn"
			onclick={() => isCollapsed = !isCollapsed}
			aria-label={isCollapsed ? 'Expand queued follow-ups' : 'Collapse queued follow-ups'}
			title={isCollapsed ? 'Expand' : 'Collapse'}
		>
			<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" class:rotated={isCollapsed}>
				<polyline points="6 9 12 15 18 9"/>
			</svg>
		</button>
	</header>

	<div class="fq-body" class:collapsed={isCollapsed} class:animating={isCollapsed}>
		<div class="fq-divider"></div>
		<div class="fq-rows">
			{#each prompts as prompt, i (prompt.id)}
				{@const isDragged = draggedId === prompt.id}
				{@const isEdit = editingId === prompt.id}
				{@const isLast = i === prompts.length - 1}
				{@const isDragOver = dragOverId === prompt.id && dropBefore}

				{#if !isEdit}
					<div
						class="fq-row"
						class:is-dragged
						class:drag-over-before={isDragOver}
						draggable="true"
						ondragstart={() => handleDragStart(prompt.id)}
						ondragover={(e) => { e.preventDefault(); handleDragOver(prompt.id, true); }}
						ondragleave={() => { if (dragOverId === prompt.id) dragOverId = null; }}
						ondrop={() => handleDrop(prompt.id)}
						ondragend={handleDragEnd}
					>
						<span class="fq-row-num">{i + 1}</span>

						<span
							class="fq-drag-handle"
							title="Drag to reorder"
							aria-label="Drag to reorder"
						>
							<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor" opacity="0.6">
								<circle cx="8" cy="5" r="1.8"/><circle cx="16" cy="5" r="1.8"/>
								<circle cx="8" cy="12" r="1.8"/><circle cx="16" cy="12" r="1.8"/>
								<circle cx="8" cy="19" r="1.8"/><circle cx="16" cy="19" r="1.8"/>
							</svg>
						</span>

						{#if prompt.attachments.length > 0}
							<div class="fq-attach-strip">
								{#each prompt.attachments as att (att.id)}
									<span class="fq-attach-chip" class:is-image={att.is_image}>
										{#if att.is_image}
											<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
												<rect x="3" y="3" width="18" height="18" rx="2"/>
												<circle cx="8.5" cy="8.5" r="1.5"/>
												<polyline points="21 15 16 10 5 21"/>
											</svg>
										{:else}
											<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
												<path d="M13 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/>
												<polyline points="13 2 13 9 20 9"/>
											</svg>
										{/if}
										<span class="fq-attach-name">{att.name}</span>
									</span>
								{/each}
							</div>
						{/if}

						<span class="fq-row-text">
							{prompt.text.trim() || getAttachmentLabel(prompt)}
						</span>

						<span class="fq-actions">
							<button
								type="button"
								class="fq-action-btn"
								title={isRunning ? 'Send now (stops the running turn)' : 'Send now'}
								aria-label={isRunning ? 'Send now (stops the running turn)' : 'Send now'}
								onclick={() => onSendNow(prompt.id)}
							>
								<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
									<line x1="22" y1="2" x2="11" y2="13"/>
									<polygon points="22 2 15 22 11 13 2 9 22 2"/>
								</svg>
							</button>
							<button
								type="button"
								class="fq-action-btn"
								title="Edit follow-up"
								aria-label="Edit follow-up"
								bind:this={(el) => { if (isEdit) editAnchor = el; }}
								onclick={(e) => startEdit(prompt, e.currentTarget)}
							>
								<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
									<path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/>
									<path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/>
								</svg>
							</button>
							<button
								type="button"
								class="fq-action-btn"
								title="Delete follow-up"
								aria-label="Delete follow-up"
								onclick={() => onDelete(prompt.id)}
							>
								<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
									<polyline points="3 6 5 6 21 6"/>
									<path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>
								</svg>
							</button>
						</span>
					</div>
					{#if !isLast}<div class="fq-row-rule"></div>{/if}
				{/if}
			{/each}
		</div>
	</div>

	<!-- Edit popover -->
	{#if editingId}
		<div class="fq-popover" role="dialog" aria-label="Edit follow-up">
			<header class="fq-pop-header">
				<span class="fq-pop-title">Edit follow-up</span>
			</header>
			<textarea
				class="fq-pop-editor"
				placeholder="Steer the agent..."
				bind:value={editText}
				rows="5"
			></textarea>
			<div class="fq-pop-strip">
				<div class="fq-pop-attaches">
					{#each editAttachments as att (att.id)}
						{#if !att._removed}
							<span class="fq-pop-attach">
								{att.name}
								<button type="button" class="fq-pop-attach-remove" onclick={() => removeEditAttachment(att.id)} title="Remove">
									<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
										<line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
									</svg>
								</button>
							</span>
						{/if}
					{/each}
					<button type="button" class="fq-pop-add" onclick={addEditAttachment} title="Add files">
						<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
							<line x1="12" y1="5" x2="12" y2="19"/>
							<line x1="5" y1="12" x2="19" y2="12"/>
						</svg>
					</button>
				</div>
				<div class="fq-pop-actions">
					<button type="button" class="fq-pop-btn fq-pop-btn-secondary" onclick={closeEdit}>Cancel</button>
					<button type="button" class="fq-pop-btn fq-pop-btn-primary" onclick={saveEdit} disabled={!editText.trim() && editAttachments.filter(a => !a._removed).length === 0}>Save</button>
				</div>
			</div>
		</div>
	{/if}
</div>

<style>
	.followup-tab {
		display: flex;
		flex-direction: column;
		background: var(--surface-2, #1f1f24);
		border: 1px solid var(--border-color-1, #2a2a30);
		border-radius: 12px;
		max-width: 560px;
		margin: 0 auto 6px;
		overflow: hidden;
	}

	.fq-header {
		display: flex;
		align-items: center;
		gap: 7px;
		padding: 7px 12px;
		font-size: 12px;
		font-weight: 500;
		font-variant-numeric: tabular-nums;
		height: 22px;
	}

	.fq-icon {
		color: var(--text-tertiary, #999);
		display: inline-flex;
		align-items: center;
	}

	.fq-count {
		color: var(--text-primary, #eee);
		opacity: 0.9;
	}

	.fq-suffix {
		color: var(--text-tertiary, #999);
	}

	.fq-collapse-btn {
		margin-left: auto;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 22px;
		height: 22px;
		border: none;
		background: none;
		color: var(--text-tertiary, #999);
		cursor: pointer;
		border-radius: 4px;
		padding: 0;
	}

	.fq-collapse-btn:hover {
		background: var(--surface-3, #25252b);
	}

	.fq-collapse-btn .rotated {
		transform: rotate(180deg);
	}

	.fq-body {
		overflow: hidden;
		transition: max-height 0.25s ease, opacity 0.2s ease;
	}

	.fq-body.collapsed {
		max-height: 0 !important;
		opacity: 0;
	}

	.fq-divider {
		height: 1px;
		background: var(--border-color-2, #2a2a30);
		opacity: 0.5;
	}

	.fq-rows {
		padding: 6px 12px 8px;
		display: flex;
		flex-direction: column;
		gap: 0;
	}

	.fq-row {
		display: flex;
		align-items: center;
		gap: 6px;
		padding: 5px 0;
		border-radius: 6px;
		cursor: grab;
		transition: background 120ms ease, box-shadow 0.2s ease;
		position: relative;
	}

	.fq-row:active {
		cursor: grabbing;
	}

	.fq-row.drag-over-before {
		border-top: 2px solid var(--accent-1, #6366f1);
		margin-top: -1px;
	}

	.fq-row.is-dragged {
		opacity: 0.5;
	}

	.fq-row-num {
		font: 500 11px/1 var(--font-mono, 'SF Mono', Menlo, monospace);
		color: var(--text-tertiary, #999);
		width: 14px;
		text-align: right;
		flex-shrink: 0;
	}

	.fq-drag-handle {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 22px;
		height: 22px;
		color: var(--text-tertiary, #999);
		flex-shrink: 0;
		cursor: grab;
		border-radius: 4px;
	}

	.fq-drag-handle:hover {
		background: var(--surface-3, #25252b);
	}

	.fq-attach-strip {
		display: flex;
		flex-wrap: nowrap;
		gap: 4px;
		overflow-x: auto;
		flex-shrink: 0;
		padding-right: 4px;
	}

	.fq-attach-chip {
		display: inline-flex;
		align-items: center;
		gap: 3px;
		padding: 2px 7px;
		border-radius: 999px;
		font-size: 10px;
		white-space: nowrap;
		max-width: 120px;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.fq-attach-chip {
		background: var(--surface-3, #25252b);
		color: var(--text-secondary, #bbb);
	}

	.fq-attach-chip.is-image {
		background: rgba(99, 102, 241, 0.1);
		color: var(--accent-1, #6366f1);
	}

	.fq-attach-name {
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.fq-row-text {
		flex: 1;
		min-width: 0;
		font-size: 12px;
		color: var(--text-primary, #eee);
		opacity: 0.9;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		user-select: text;
	}

	.fq-row-rule {
		height: 1px;
		background: var(--border-color-2, #2a2a30);
		opacity: 0.35;
		margin: 0 0 2px;
	}

	.fq-actions {
		display: flex;
		align-items: center;
		gap: 2px;
		flex-shrink: 0;
		opacity: 0;
		transition: opacity 150ms ease;
	}

	.fq-row:hover .fq-actions {
		opacity: 1;
	}

	.fq-action-btn {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 22px;
		height: 22px;
		border: none;
		background: none;
		color: var(--text-tertiary, #999);
		cursor: pointer;
		border-radius: 4px;
		padding: 0;
		transition: all 120ms ease;
	}

	.fq-action-btn:hover {
		background: var(--surface-3, #25252b);
		color: var(--text-primary, #eee);
	}

	/* ---- Edit popover ---- */
	.fq-popover {
		position: absolute;
		z-index: 100;
		background: var(--surface-2, #1f1f24);
		border: 1px solid var(--border-color-1, #2a2a30);
		border-radius: 14px;
		box-shadow: 0 12px 40px rgba(0, 0, 0, 0.5);
		width: 520px;
		max-width: calc(100vw - 32px);
		display: flex;
		flex-direction: column;
		animation: pop-in 0.15s ease;
	}

	@keyframes pop-in {
		from { opacity: 0; transform: scale(0.96) translateY(-4px); }
		to   { opacity: 1; transform: scale(1) translateY(0); }
	}

	.fq-pop-header {
		padding: 12px 16px 4px;
		font-size: 15px;
		font-weight: 600;
		color: var(--text-primary, #eee);
	}

	.fq-pop-editor {
		margin: 0 16px;
		padding: 8px 12px;
		background: var(--surface-3, #25252b);
		border: 1px solid var(--border-color-1, #2a2a30);
		border-radius: 10px;
		color: var(--text-primary, #eee);
		font: inherit;
		font-size: 13px;
		resize: vertical;
		min-height: 110px;
		outline: none;
	}

	.fq-pop-editor:focus {
		border-color: var(--accent-1, #6366f1);
	}

	.fq-pop-editor::placeholder {
		color: var(--text-tertiary, #777);
	}

	.fq-pop-strip {
		margin: 12px 16px 16px;
		display: flex;
		flex-direction: column;
		gap: 10px;
	}

	.fq-pop-attaches {
		display: flex;
		flex-wrap: wrap;
		gap: 6px;
	}

	.fq-pop-attach {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		padding: 3px 8px 3px 10px;
		border-radius: 999px;
		font-size: 11px;
		background: var(--surface-3, #25252b);
		color: var(--text-secondary, #bbb);
		max-width: 160px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.fq-pop-attach-remove {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 14px;
		height: 14px;
		border: none;
		background: none;
		color: var(--text-tertiary, #999);
		cursor: pointer;
		border-radius: 50%;
		padding: 0;
		flex-shrink: 0;
	}

	.fq-pop-attach-remove:hover {
		color: var(--danger, #ff3b30);
		background: var(--surface-4, #2c2c34);
	}

	.fq-pop-add {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 30px;
		height: 30px;
		border: none;
		background: var(--surface-3, #25252b);
		border-radius: 8px;
		color: var(--text-tertiary, #999);
		cursor: pointer;
		padding: 0;
	}

	.fq-pop-add:hover {
		background: var(--surface-4, #2c2c34);
		color: var(--text-primary, #eee);
	}

	.fq-pop-actions {
		display: flex;
		justify-content: flex-end;
		gap: 8px;
		margin-top: 4px;
	}

	.fq-pop-btn {
		appearance: none;
		border: none;
		padding: 5px 14px;
		border-radius: 8px;
		font: inherit;
		font-size: 12px;
		font-weight: 500;
		cursor: pointer;
		transition: all 120ms ease;
	}

	.fq-pop-btn-secondary {
		background: var(--surface-3, #25252b);
		border: 1px solid var(--border-color-1, #2a2a30);
		color: var(--text-primary, #eee);
	}

	.fq-pop-btn-secondary:hover:not(:disabled) {
		background: var(--surface-4, #2c2c34);
	}

	.fq-pop-btn-primary {
		background: var(--accent-1, #6366f1);
		color: #fff;
	}

	.fq-pop-btn-primary:hover:not(:disabled) {
		background: var(--accent-2, #5158d8);
	}

	.fq-pop-btn:disabled {
		opacity: 0.4;
		cursor: not-allowed;
	}

	@media (prefers-reduced-motion: reduce) {
		.fq-popover { animation: none; }
		.fq-body { transition: none; }
	}
</style>
