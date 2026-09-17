<script lang="ts">
	import { onMount } from 'svelte';
	import { getSettings, updateSettings } from '$lib/api/commands';
	import { getRegisteredShortcuts, registerShortcut, unregisterShortcut } from '$lib/api/commands';
	import type { Shortcut } from '$lib/types';

	// ---------------------------------------------------------------------------
	// Default shortcuts matching macOS conventions
	// ---------------------------------------------------------------------------

	const DEFAULT_SHORTCUTS: Shortcut[] = [
		{ action: 'new_thread', key: 'N', modifiers: ['cmd'], display: 'Cmd+N' },
		{ action: 'toggle_sidebar', key: 'S', modifiers: ['cmd', 'shift'], display: 'Cmd+Shift+S' },
		{ action: 'send_message', key: 'Enter', modifiers: ['cmd'], display: 'Cmd+Enter' },
		{ action: 'open_settings', key: ',', modifiers: ['cmd'], display: 'Cmd+,' },
		{ action: 'open_palette', key: 'K', modifiers: ['cmd', 'shift'], display: 'Cmd+Shift+K' },
		{ action: 'clear_thread', key: 'K', modifiers: ['cmd'], display: 'Cmd+K' },
		{ action: 'toggle_terminal', key: 'T', modifiers: ['cmd', 'shift'], display: 'Cmd+Shift+T' },
		{ action: 'toggle_hydra', key: 'H', modifiers: ['cmd', 'shift'], display: 'Cmd+Shift+H' },
		{ action: 'focus_input', key: 'I', modifiers: ['cmd'], display: 'Cmd+I' },
		{ action: 'search_threads', key: 'F', modifiers: ['cmd'], display: 'Cmd+F' },
		{ action: 'archive_thread', key: 'E', modifiers: ['cmd', 'shift'], display: 'Cmd+Shift+E' },
		{ action: 'delete_thread', key: 'Backspace', modifiers: ['cmd', 'shift'], display: 'Cmd+Shift+Backspace' },
	];

	// ---------------------------------------------------------------------------
	// State
	// ---------------------------------------------------------------------------

	let shortcuts = $state<Shortcut[]>([]);
	let isLoading = $state(true);
	let editingIndex = $state<number | null>(null);
	let editKey = $state('');
	let editModifiers = $state<string[]>([]);
	let isListening = $state(false);
	let hasChanges = $state(false);

	// ---------------------------------------------------------------------------
	// Load
	// ---------------------------------------------------------------------------

	onMount(() => {
		loadShortcuts();
	});

	async function loadShortcuts() {
		try {
			shortcuts = await getRegisteredShortcuts();
		} catch (e) {
			console.error('Failed to load shortcuts:', e);
			shortcuts = [...DEFAULT_SHORTCUTS];
		} finally {
			isLoading = false;
		}
	}

	// ---------------------------------------------------------------------------
	// Actions
	// ---------------------------------------------------------------------------

	function startEdit(index: number) {
		const s = shortcuts[index];
		editingIndex = index;
		editKey = s.key;
		editModifiers = [...s.modifiers];
		isListening = false;
	}

	function cancelEdit() {
		editingIndex = null;
		editKey = '';
		editModifiers = [];
		isListening = false;
	}

	function startListening() {
		isListening = true;
		editKey = '';
		editModifiers = [];
	}

	async function captureShortcut(e: KeyboardEvent) {
		e.preventDefault();
		e.stopPropagation();

		const capturedModifiers: string[] = [];
		if (e.metaKey || e.ctrlKey) capturedModifiers.push('cmd');
		if (e.shiftKey) capturedModifiers.push('shift');
		if (e.altKey) capturedModifiers.push('alt');

		// Determine key
		let key = e.key;
		if (key === ' ') key = 'Space';
		if (key === 'Escape') {
			cancelEdit();
			return;
		}

		editKey = key;
		editModifiers = capturedModifiers;

		// Build the shortcut entry
		if (editingIndex !== null && editKey) {
			const modifierStr = editModifiers.join('+');
			const display = modifierStr ? `${modifierStr}+${editKey}` : editKey;

			const updated: Shortcut = {
				action: shortcuts[editingIndex].action,
				key: editKey,
				modifiers: editModifiers,
				display,
			};

			shortcuts[editingIndex] = updated;

			try {
				// Unregister old, register new
				await unregisterShortcut(shortcuts[editingIndex].action);
				await registerShortcut(updated);
				hasChanges = true;
			} catch (e) {
				console.error('Failed to update shortcut:', e);
			}

			// Exit listening mode briefly to let the key event through
			isListening = false;
			// Stay in edit mode so user can confirm
		}
	}

	async function confirmEdit() {
		if (editingIndex === null || !editKey) return;

		const updated: Shortcut = {
			action: shortcuts[editingIndex].action,
			key: editKey,
			modifiers: editModifiers,
			display: buildDisplay(editKey, editModifiers),
		};

		shortcuts[editingIndex] = updated;

		try {
			await unregisterShortcut(shortcuts[editingIndex].action);
			await registerShortcut(updated);
			hasChanges = true;
		} catch (e) {
			console.error('Failed to register shortcut:', e);
		}

		editingIndex = null;
		editKey = '';
		editModifiers = [];
		isListening = false;
	}

	async function handleReset() {
		// Unregister current shortcuts and revert to defaults
		for (const s of shortcuts) {
			try {
				await unregisterShortcut(s.action);
			} catch { /* ignore */ }
		}

		for (const s of DEFAULT_SHORTCUTS) {
			try {
				await registerShortcut(s);
			} catch { /* ignore */ }
		}

		shortcuts = [...DEFAULT_SHORTCUTS];
		hasChanges = false;
	}

	function buildDisplay(key: string, modifiers: string[]): string {
		const parts: string[] = [];
		for (const m of modifiers) {
			if (m === 'cmd') parts.push('Cmd');
			else if (m === 'shift') parts.push('Shift');
			else if (m === 'alt') parts.push('Alt');
			else if (m === 'ctrl') parts.push('Ctrl');
			else parts.push(m);
		}
		parts.push(key);
		return parts.join('+');
	}

	function actionLabel(action: string): string {
		const map: Record<string, string> = {
			new_thread: 'New Thread',
			toggle_sidebar: 'Toggle Sidebar',
			send_message: 'Send Message',
			open_settings: 'Open Settings',
			open_palette: 'Command Palette',
			clear_thread: 'Clear Thread',
			toggle_terminal: 'Toggle Terminal',
			toggle_hydra: 'Toggle Hydra Panel',
			focus_input: 'Focus Input',
			search_threads: 'Search Threads',
			archive_thread: 'Archive Thread',
			delete_thread: 'Delete Thread',
		};
		return map[action] ?? action;
	}

	// ---------------------------------------------------------------------------
	// Keyboard listener for shortcut capture
	// ---------------------------------------------------------------------------

	function handleKeydown(e: KeyboardEvent) {
		if (!isListening || editingIndex === null) return;
		captureShortcut(e);
	}
</script>

<svelte:window onkeydown={handleKeydown} />

<div class="shortcuts-settings">
	<div class="settings-page-header">
		<h2 class="settings-page-title">Keyboard Shortcuts</h2>
		<p class="settings-page-desc">Customize keyboard bindings for common actions</p>
	</div>

	{#if isLoading}
		<div class="loading">
			<div class="spinner"></div>
		</div>
	{:else}
		<div class="shortcuts-content">
			<div class="shortcuts-list">
				{#each shortcuts as shortcut, i (shortcut.action)}
					<div class="shortcut-row" class:editing={editingIndex === i}>
						<span class="shortcut-label">{actionLabel(shortcut.action)}</span>

						{#if editingIndex === i}
							<div class="shortcut-edit-row">
								<button
									class="listen-btn"
									class:listening={isListening}
									onclick={startListening}
								>
									{isListening ? 'Press keys…' : (editKey ? buildDisplay(editKey, editModifiers) : 'Click to rebind')}
								</button>
								<button class="btn btn-xs btn-primary" onclick={confirmEdit} disabled={!editKey}>Save</button>
								<button class="btn btn-xs btn-secondary" onclick={cancelEdit}>Cancel</button>
							</div>
						{:else}
							<div class="shortcut-keys">
								{#each shortcut.modifiers as mod}
									<span class="key-chip">{mod}</span>
								{/each}
								<span class="key-chip main-key">{shortcut.key}</span>
							</div>
							<button class="edit-btn" onclick={() => startEdit(i)} title="Rebind">
								<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
									<path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/>
									<path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/>
								</svg>
							</button>
						{/if}
					</div>
				{/each}
			</div>

			<div class="shortcuts-footer">
				<button class="btn btn-secondary" onclick={handleReset}>
					Reset to Defaults
				</button>
			</div>
		</div>
	{/if}
</div>

<style>
	.shortcuts-settings {
		display: flex;
		flex-direction: column;
		gap: var(--space-6);
		width: 100%;
	}

	.settings-page-header {
		margin-bottom: var(--space-2);
	}

	.settings-page-title {
		font-size: var(--font-size-xl);
		font-weight: 700;
		color: var(--text-primary);
	}

	.settings-page-desc {
		font-size: var(--font-size-sm);
		color: var(--text-tertiary);
		margin-top: var(--space-1);
	}

	/* ── Loading ── */

	.loading {
		display: flex;
		justify-content: center;
		padding: var(--space-8);
	}

	.spinner {
		width: 28px;
		height: 28px;
		border: 2px solid var(--surface-3);
		border-top-color: var(--accent-1);
		border-radius: 50%;
		animation: spin 0.7s linear infinite;
	}

	@keyframes spin {
		to { transform: rotate(360deg); }
	}

	/* ── Shortcuts List ── */

	.shortcuts-content {
		display: flex;
		flex-direction: column;
		gap: var(--space-4);
	}

	.shortcuts-list {
		display: flex;
		flex-direction: column;
		gap: 1px;
	}

	.shortcut-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: var(--space-3) var(--space-4);
		border-radius: var(--radius-md);
		transition: background var(--transition-fast);
		gap: var(--space-4);
	}

	.shortcut-row:hover {
		background: var(--surface-2);
	}

	.shortcut-row.editing {
		background: var(--accent-4);
		border: var(--border-1) var(--accent-3);
	}

	.shortcut-label {
		font-size: var(--font-size-sm);
		color: var(--text-primary);
		flex: 1;
	}

	.shortcut-keys {
		display: flex;
		align-items: center;
		gap: 4px;
	}

	.key-chip {
		padding: 3px 8px;
		border: var(--border-1) var(--border-color-1);
		border-radius: var(--radius-sm);
		font-size: 11px;
		font-family: var(--font-mono);
		color: var(--text-secondary);
		background: var(--surface-2);
		text-transform: capitalize;
		min-width: 24px;
		text-align: center;
	}

	.key-chip.main-key {
		background: var(--surface-3);
		color: var(--text-primary);
		font-weight: 500;
	}

	.edit-btn {
		width: 28px;
		height: 28px;
		border: none;
		background: transparent;
		border-radius: var(--radius-sm);
		color: var(--text-tertiary);
		cursor: pointer;
		display: flex;
		align-items: center;
		justify-content: center;
		transition: all var(--transition-fast);
		opacity: 0;
	}

	.shortcut-row:hover .edit-btn {
		opacity: 1;
	}

	.edit-btn:hover {
		background: var(--surface-3);
		color: var(--accent-1);
	}

	/* ── Editing State ── */

	.shortcut-edit-row {
		display: flex;
		align-items: center;
		gap: var(--space-2);
	}

	.listen-btn {
		padding: 4px 12px;
		border: var(--border-1) var(--accent-1);
		background: var(--accent-3);
		border-radius: var(--radius-sm);
		font-size: var(--font-size-xs);
		color: var(--accent-1);
		cursor: pointer;
		transition: all var(--transition-fast);
		font-family: var(--font-system);
		min-width: 120px;
		text-align: center;
	}

	.listen-btn.listening {
		background: var(--accent-1);
		color: white;
		animation: pulse-border 1.5s ease-in-out infinite;
	}

	@keyframes pulse-border {
		0%, 100% { box-shadow: 0 0 0 0 rgba(10, 132, 255, 0.4); }
		50% { box-shadow: 0 0 0 4px rgba(10, 132, 255, 0); }
	}

	/* ── Buttons ── */

	.btn {
		padding: 4px 10px;
		border: none;
		border-radius: var(--radius-sm);
		font-size: 10px;
		font-weight: 500;
		cursor: pointer;
		transition: all var(--transition-fast);
		font-family: var(--font-system);
	}

	.btn-xs {
		padding: 3px 8px;
		font-size: 10px;
	}

	.btn-primary {
		background: var(--accent-1);
		color: white;
	}

	.btn-primary:hover:not(:disabled) {
		background: var(--accent-2);
	}

	.btn-primary:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}

	.btn-secondary {
		background: var(--surface-3);
		color: var(--text-primary);
	}

	.btn-secondary:hover {
		background: var(--surface-4);
	}

	/* ── Footer ── */

	.shortcuts-footer {
		padding-top: var(--space-4);
		border-top: var(--border-1) var(--border-color-2);
	}
</style>
