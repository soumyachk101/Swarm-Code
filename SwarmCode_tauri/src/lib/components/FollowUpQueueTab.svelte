<script lang="ts">
	// ---------------------------------------------------------------------------
	// FollowUpQueueTab – tab showing queued follow-up questions
	// Matches FollowUpQueueTab.swift: an ordered list with add/remove/reorder.
	// ---------------------------------------------------------------------------

	import { v4 as uuidv4 } from 'uuid';

	// ---------------------------------------------------------------------------
	// Props
	// ---------------------------------------------------------------------------

	export interface FollowUpItem {
		id: string;
		text: string;
		attachments: Array<{ name: string; path: string; mime_type: string }>;
		created_at: string;
	}

	interface Props {
		items: FollowUpItem[];
		readonly?: boolean;
		onChange: (items: FollowUpItem[]) => void;
		onSend?: () => void;
	}

	let { items = $bindable([]), readonly = false, onChange, onSend }: Props = $props();

	// ---------------------------------------------------------------------------
	// State
	// ---------------------------------------------------------------------------

	let draft = $state('');
	let dragIndex = $state<number | null>(null);
	let dropTarget = $state<number | null>(null);

	// ---------------------------------------------------------------------------
	// Derived
	// ---------------------------------------------------------------------------

	let sortedItems = $derived(items);
	let canSend = $derived(items.length > 0 && !readonly);

	// ---------------------------------------------------------------------------
	// Actions
	// ---------------------------------------------------------------------------

	function emit(next: FollowUpItem[]) {
		items = next;
		onChange(next);
	}

	function add() {
		const trimmed = draft.trim();
		if (!trimmed || readonly) return;
		const next: FollowUpItem[] = [
			...items,
			{
				id: uuidv4(),
				text: trimmed,
				attachments: [],
				created_at: new Date().toISOString(),
			},
		];
		draft = '';
		emit(next);
	}

	function remove(id: string) {
		if (readonly) return;
		emit(items.filter((it) => it.id !== id));
	}

	function edit(id: string, value: string) {
		if (readonly) return;
		emit(items.map((it) => (it.id === id ? { ...it, text: value } : it)));
	}

	function move(from: number, to: number) {
		if (readonly) return;
		if (from === to) return;
		const arr = [...items];
		const [item] = arr.splice(from, 1);
		arr.splice(to, 0, item);
		emit(arr);
	}

	function moveUp(index: number) {
		if (index <= 0 || readonly) return;
		move(index, index - 1);
	}

	function moveDown(index: number) {
		if (index >= items.length - 1 || readonly) return;
		move(index, index + 1);
	}

	function clearAll() {
		if (readonly) return;
		emit([]);
	}

	function handleSend() {
		if (!canSend) return;
		onSend?.();
	}

	// ---------------------------------------------------------------------------
	// Drag & Drop
	// ---------------------------------------------------------------------------

	function onDragStart(index: number, e: DragEvent) {
		dragIndex = index;
		e.dataTransfer?.setData('text/plain', items[index].id);
		if (e.dataTransfer) e.dataTransfer.effectAllowed = 'move';
	}

	function onDragOver(index: number, e: DragEvent) {
		e.preventDefault();
		dropTarget = index;
	}

	function onDrop(target: number, e: DragEvent) {
		e.preventDefault();
		if (dragIndex === null) return;
		move(dragIndex, target);
		dragIndex = null;
		dropTarget = null;
	}

	function onDragEnd() {
		dragIndex = null;
		dropTarget = null;
	}

	// ---------------------------------------------------------------------------
	// Keyboard
	// ---------------------------------------------------------------------------

	function onInputKey(e: KeyboardEvent) {
		if (e.key === 'Enter' && !e.shiftKey) {
			e.preventDefault();
			add();
		}
	}
</script>

<div class="follow-up-root">
	<!-- Header -->
	<header class="header">
		<div class="title-row">
			<span class="title">Follow-up Queue</span>
			<span class="counter">{items.length} queued</span>
		</div>
		{#if items.length > 0 && !readonly}
			<button class="clear-btn" onclick={clearAll} type="button">Clear all</button>
		{/if}
	</header>

	<!-- Add row -->
	{#if !readonly}
		<div class="add-row">
			<textarea
				class="add-input"
				bind:value={draft}
				placeholder="Queue a follow-up question… (Enter to add, Shift+Enter for newline)"
				onkeydown={onInputKey}
				rows="2"
			/>
			<button
				class="add-btn"
				onclick={add}
				disabled={!draft.trim()}
				type="button"
				aria-label="Add to queue"
			>
				Add
			</button>
		</div>
	{/if}

	<!-- Queue -->
	<div class="queue" role="list">
		{#if sortedItems.length === 0}
			<div class="empty">
				<span class="empty-icon">⏳</span>
				<p class="empty-text">No queued follow-ups. Add one above to keep the conversation going.</p>
			</div>
		{:else}
			{#each sortedItems as item, index (item.id)}
				<div
					class="queue-item"
					class:dragging={dragIndex === index}
					class:drop-target={dropTarget === index && dragIndex !== index}
					draggable={!readonly}
					role="listitem"
					ondragstart={(e) => onDragStart(index, e)}
					ondragover={(e) => onDragOver(index, e)}
					ondrop={(e) => onDrop(index, e)}
					ondragend={onDragEnd}
				>
					<!-- Drag handle -->
					<span class="handle" aria-hidden="true">⋮⋮</span>

					<!-- Position -->
					<span class="position">{index + 1}</span>

					<!-- Text -->
					<div class="content">
						{#if readonly}
							<p class="text">{item.text}</p>
						{:else}
							<textarea
								class="text-input"
								value={item.text}
								oninput={(e) => edit(item.id, (e.target as HTMLTextAreaElement).value)}
								rows="2"
							/>
						{/if}

						{#if item.attachments.length > 0}
							<div class="attachment-row">
								{#each item.attachments as att}
									<span class="attachment-pill">📎 {att.name}</span>
								{/each}
							</div>
						{/if}

						<time class="time">{new Date(item.created_at).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' })}</time>
					</div>

					<!-- Actions -->
					{#if !readonly}
						<div class="actions">
							<button
								class="action-btn"
								onclick={() => moveUp(index)}
								disabled={index === 0}
								type="button"
								aria-label="Move up"
								title="Move up"
							>↑</button>
							<button
								class="action-btn"
								onclick={() => moveDown(index)}
								disabled={index === items.length - 1}
								type="button"
								aria-label="Move down"
								title="Move down"
							>↓</button>
							<button
								class="action-btn danger"
								onclick={() => remove(item.id)}
								type="button"
								aria-label="Remove"
								title="Remove"
							>✕</button>
						</div>
					{/if}
				</div>
			{/each}
		{/if}
	</div>

	<!-- Send -->
	{#if items.length > 0}
		<footer class="footer">
			<button
				class="send-btn"
				disabled={!canSend}
				onclick={handleSend}
				type="button"
			>
				Send all {items.length}
			</button>
		</footer>
	{/if}
</div>

<style>
	.follow-up-root {
		display: flex;
		flex-direction: column;
		gap: 12px;
		padding: 12px;
		font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', sans-serif;
	}

	.header {
		display: flex;
		align-items: center;
		justify-content: space-between;
	}

	.title-row {
		display: flex;
		align-items: baseline;
		gap: 8px;
	}

	.title {
		font-size: 13px;
		font-weight: 600;
		color: var(--chrome-primary, #111827);
	}

	.counter {
		font-size: 11px;
		color: var(--chrome-secondary, #6b7280);
	}

	.clear-btn {
		appearance: none;
		border: none;
		background: transparent;
		color: var(--chrome-secondary, #6b7280);
		font-size: 11px;
		cursor: pointer;
		padding: 4px 8px;
		border-radius: 6px;
		transition: background 120ms;
		font-family: inherit;
	}

	.clear-btn:hover {
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.06));
	}

	.add-row {
		display: flex;
		gap: 8px;
		align-items: flex-start;
	}

	.add-input {
		flex: 1;
		appearance: none;
		border: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.1));
		background: var(--chrome-surface, transparent);
		border-radius: 8px;
		padding: 8px 10px;
		font-size: 12px;
		font-family: inherit;
		color: var(--chrome-primary, #111827);
		resize: vertical;
		min-height: 36px;
		max-height: 120px;
		transition: border-color 140ms;
	}

	.add-input:focus {
		outline: none;
		border-color: var(--chrome-accent, #6366f1);
	}

	.add-btn {
		appearance: none;
		border: none;
		background: var(--chrome-accent, #6366f1);
		color: #ffffff;
		font-size: 12px;
		font-weight: 600;
		padding: 8px 14px;
		border-radius: 8px;
		cursor: pointer;
		transition: background 140ms;
		font-family: inherit;
		align-self: stretch;
	}

	.add-btn:hover:not(:disabled) {
		background: #4f46e5;
	}

	.add-btn:disabled {
		opacity: 0.4;
		cursor: not-allowed;
	}

	.queue {
		display: flex;
		flex-direction: column;
		gap: 6px;
		max-height: 400px;
		overflow-y: auto;
	}

	.queue-item {
		display: grid;
		grid-template-columns: 16px 22px 1fr auto;
		gap: 8px;
		align-items: flex-start;
		padding: 8px 10px;
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.03));
		border: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.06));
		border-radius: 8px;
		transition: all 140ms ease;
	}

	.queue-item:hover {
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.05));
	}

	.queue-item.dragging {
		opacity: 0.4;
	}

	.queue-item.drop-target {
		border-color: var(--chrome-accent, #6366f1);
		background: #6366f110;
	}

	.handle {
		font-size: 12px;
		color: var(--chrome-secondary, #9ca3af);
		cursor: grab;
		padding-top: 2px;
		letter-spacing: -2px;
		user-select: none;
	}

	.handle:active {
		cursor: grabbing;
	}

	.position {
		font-size: 10px;
		font-weight: 700;
		color: var(--chrome-secondary, #9ca3af);
		font-family: 'SF Mono', monospace;
		padding-top: 3px;
		text-align: right;
	}

	.content {
		display: flex;
		flex-direction: column;
		gap: 4px;
		min-width: 0;
	}

	.text,
	.text-input {
		font-size: 12px;
		line-height: 1.5;
		color: var(--chrome-primary, #111827);
		margin: 0;
		padding: 0;
		border: none;
		background: transparent;
		font-family: inherit;
		width: 100%;
		resize: vertical;
		min-height: 1.5em;
	}

	.text-input:focus {
		outline: none;
	}

	.attachment-row {
		display: flex;
		gap: 4px;
		flex-wrap: wrap;
	}

	.attachment-pill {
		font-size: 10px;
		padding: 2px 6px;
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.06));
		border-radius: 4px;
		color: var(--chrome-secondary, #6b7280);
	}

	.time {
		font-size: 10px;
		color: var(--chrome-secondary, #9ca3af);
		font-family: 'SF Mono', monospace;
	}

	.actions {
		display: flex;
		flex-direction: column;
		gap: 2px;
	}

	.action-btn {
		appearance: none;
		border: none;
		background: transparent;
		color: var(--chrome-secondary, #6b7280);
		font-size: 11px;
		padding: 2px 6px;
		border-radius: 4px;
		cursor: pointer;
		transition: background 120ms;
		font-family: inherit;
		line-height: 1.3;
	}

	.action-btn:hover:not(:disabled) {
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.08));
		color: var(--chrome-primary, #111827);
	}

	.action-btn:disabled {
		opacity: 0.3;
		cursor: not-allowed;
	}

	.action-btn.danger:hover:not(:disabled) {
		background: #ef444415;
		color: #ef4444;
	}

	.empty {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 8px;
		padding: 32px 16px;
		color: var(--chrome-secondary, #6b7280);
	}

	.empty-icon {
		font-size: 28px;
		opacity: 0.6;
	}

	.empty-text {
		font-size: 12px;
		text-align: center;
		margin: 0;
		max-width: 280px;
	}

	.footer {
		display: flex;
		justify-content: flex-end;
	}

	.send-btn {
		appearance: none;
		border: none;
		background: var(--chrome-accent, #6366f1);
		color: #ffffff;
		font-size: 12px;
		font-weight: 600;
		padding: 8px 16px;
		border-radius: 8px;
		cursor: pointer;
		transition: background 140ms;
		font-family: inherit;
	}

	.send-btn:hover:not(:disabled) {
		background: #4f46e5;
	}

	.send-btn:disabled {
		opacity: 0.4;
		cursor: not-allowed;
	}

	@media (max-width: 480px) {
		.queue-item {
			grid-template-columns: 16px 1fr;
			grid-template-areas:
				'handle content'
				'handle actions';
		}
		.position {
			display: none;
		}
	}
</style>
