<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { invoke } from '@tauri-apps/api/core';
	import type { TerminalSession } from '$lib/types';

	interface Props {
		open: boolean;
		onClose: () => void;
		projectId?: string | null;
	}

	let { open = false, onClose, projectId = null }: Props = $props();

	let sessions = $state<TerminalSession[]>([]);
	let activeSessionId = $state<string | null>(null);
	let commandInput = $state('');
	let commandHistory: string[] = $state([]);
	let historyIndex = $state(-1);

	let sessionContainer: HTMLDivElement | null = $state(null);

	$effect(() => {
		if (open) loadSessions();
	});

	async function loadSessions() {
		try {
			const result = await invoke<TerminalSession[]>('list_terminal_sessions');
			sessions = result;
			if (sessions.length > 0 && !activeSessionId) {
				selectSession(sessions[0].id);
			}
		} catch (e) {
			console.error('Failed to load sessions:', e);
		}
	}

	async function spawnSession(cwd?: string) {
		try {
			const session = await invoke<TerminalSession>('spawn_terminal_session', {
				cwd: cwd || projectId || null,
				env: null
			});
			sessions = [...sessions, session];
			selectSession(session.id);
		} catch (e) {
			console.error('Failed to spawn session:', e);
		}
	}

	async function selectSession(id: string) {
		activeSessionId = id;
		await refreshOutput();
	}

	async function refreshOutput() {
		if (!activeSessionId) return;
		try {
			const session = await invoke<TerminalSession>('get_terminal_session', { id: activeSessionId });
			const idx = sessions.findIndex(s => s.id === activeSessionId);
			if (idx >= 0) sessions[idx] = session;
		} catch (e) {
			console.error('Failed to refresh session:', e);
		}
	}

	async function sendCommand() {
		if (!activeSessionId || !commandInput.trim()) return;

		const cmd = commandInput.trim();
		commandHistory = [cmd, ...commandHistory];
		historyIndex = -1;
		commandInput = '';

		try {
			await invoke('write_terminal_input', {
				id: activeSessionId,
				data: cmd + '\n'
			});
			setTimeout(refreshOutput, 100);
		} catch (e) {
			console.error('Failed to send command:', e);
		}
	}

	async function sendSignal(signal: string) {
		if (!activeSessionId) return;
		try {
			await invoke('send_terminal_signal', { id: activeSessionId, signal });
		} catch (e) {
			console.error('Failed to send signal:', e);
		}
	}

	async function closeSession(id: string) {
		try {
			await invoke('close_terminal_session', { id });
			sessions = sessions.filter(s => s.id !== id);
			if (activeSessionId === id) {
				activeSessionId = sessions[0]?.id ?? null;
			}
		} catch (e) {
			console.error('Failed to close session:', e);
		}
	}

	function handleKeyDown(e: KeyboardEvent) {
		if (e.key === 'Enter') {
			sendCommand();
		} else if (e.key === 'ArrowUp') {
			if (sessionContainer) {
				sessionContainer.scrollTop = sessionContainer.scrollTop;
			}
		} else if (e.key === 'c' && (e.metaKey || e.ctrlKey)) {
			e.preventDefault();
			sendSignal('C');
		}
	}

	let activeSession = $derived(sessions.find(s => s.id === activeSessionId));
	let outputLines = $derived(() => {
		if (!activeSession) return [];
		const anySession = activeSession as any;
		const output = anySession.output || anySession.recentOutput || '';
		if (!output) return [];
		return output.split('\n').filter((l: string) => l.length > 0);
	});

	let sessionTabs = $derived(sessions.slice(0, 6));

	function formatStatus(status: string): string {
		switch (status) {
			case 'running': return '● Running';
			case 'idle': return '○ Idle';
			case 'exited': return '✕ Exited';
			case 'error': return '⚠ Error';
			default: return status;
		}
	}
</script>

{#if open}
	<div class="terminal-panel">
		<div class="terminal-toolbar">
			<div class="session-tabs">
				{#each sessionTabs as session (session.id)}
					<button
						class="session-tab"
						class:active={session.id === activeSessionId}
						onclick={() => selectSession(session.id)}
					>
						<span class="session-name">
							{activeSessionId === session.id ? '●' : '○'}
							{session.directory?.split('/').pop() ?? 'Shell'}
						</span>
						<span
							class="tab-close"
							onclick={(e) => { e.stopPropagation(); closeSession(session.id); }}
						>
							<svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
								<path d="M18 6L6 18M6 6l12 12"/>
							</svg>
						</span>
					</button>
				{/each}
				<button class="new-tab-btn" onclick={() => spawnSession()}>
					<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
						<path d="M12 5v14M5 12h14"/>
					</svg>
				</button>
			</div>
			<div class="terminal-actions">
				{#if activeSession}
					<button class="term-btn" onclick={() => sendSignal('C')} title="Interrupt (Ctrl+C)">
						<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
							<path d="M18 6L6 18M6 6l12 12"/>
						</svg>
					</button>
				{/if}
				<button class="term-btn close-btn" onclick={onClose} title="Close">
					<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
						<path d="M18 6L6 18M6 6l12 12"/>
					</svg>
				</button>
			</div>
		</div>

		<div class="terminal-body">
			{#if activeSession}
				<div class="terminal-output" bind:this={sessionContainer}>
					{#if outputLines().length === 0}
						<div class="terminal-empty">
							<span class="prompt-symbol">$</span>
							<span class="welcome-text">Terminal ready — type a command or use ↑↓ for history</span>
						</div>
					{/if}
					{#each outputLines() as line (line)}
						<div class="output-line">{line}</div>
					{/each}
				</div>
				<div class="terminal-input-row">
					<span class="prompt-symbol">$</span>
					<input
						type="text"
						class="terminal-input"
						placeholder="Run a command…"
						value={commandInput}
						oninput={(e) => commandInput = e.currentTarget.value}
						onkeydown={handleKeyDown}
						spellcheck={false}
					/>
				</div>
			{:else}
				<div class="terminal-empty-state">
					<div class="empty-icon">
						<svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" opacity="0.3">
							<polyline points="4 17 10 11 4 5"/>
							<line x1="12" y1="19" x2="20" y2="19"/>
						</svg>
					</div>
					<p>No active terminal sessions</p>
					<button class="spawn-btn" onclick={() => spawnSession()}>
						<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
							<path d="M12 5v14M5 12h14"/>
						</svg>
						New Shell
					</button>
				</div>
			{/if}
		</div>
	</div>
{/if}

<style>
	.terminal-panel {
		position: fixed;
		bottom: 0;
		right: 0;
		left: 0;
		height: 50vh;
		background: var(--surface-2);
		border-top: var(--border-1) var(--border-color-1);
		display: flex;
		flex-direction: column;
		z-index: 100;
		animation: slide-up 0.2s ease-out;
	}

	@keyframes slide-up {
		from { transform: translateY(100%); }
		to { transform: translateY(0); }
	}

	.terminal-toolbar {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: var(--space-2) var(--space-4);
		background: var(--surface-3);
		border-bottom: var(--border-1) var(--border-color-1);
		flex-shrink: 0;
		min-height: 38px;
	}

	.session-tabs {
		display: flex;
		align-items: center;
		gap: 1px;
		flex: 1;
		overflow-x: auto;
	}

	.session-tab {
		display: flex;
		align-items: center;
		gap: 4px;
		padding: 4px 10px;
		border: none;
		background: transparent;
		color: var(--text-tertiary);
		font-size: var(--font-size-xs);
		font-family: var(--font-mono);
		cursor: pointer;
		border-radius: var(--radius-sm);
		transition: all var(--transition-fast);
		white-space: nowrap;
		max-width: 180px;
	}

	.session-tab:hover {
		background: var(--surface-4);
		color: var(--text-secondary);
	}

	.session-tab.active {
		background: var(--surface-2);
		color: var(--text-primary);
	}

	.session-name {
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.tab-close {
		display: none;
		width: 14px;
		height: 14px;
		align-items: center;
		justify-content: center;
		border: none;
		background: transparent;
		color: var(--text-tertiary);
		cursor: pointer;
		border-radius: var(--radius-sm);
	}

	.session-tab:hover .tab-close {
		display: flex;
	}

	.tab-close:hover {
		color: var(--danger);
	}

	.new-tab-btn {
		width: 24px;
		height: 24px;
		border: none;
		background: transparent;
		border-radius: var(--radius-sm);
		color: var(--text-tertiary);
		cursor: pointer;
		display: flex;
		align-items: center;
		justify-content: center;
		transition: all var(--transition-fast);
		flex-shrink: 0;
	}

	.new-tab-btn:hover {
		background: var(--surface-3);
		color: var(--text-primary);
	}

	.terminal-actions {
		display: flex;
		align-items: center;
		gap: var(--space-1);
	}

	.term-btn {
		width: 24px;
		height: 24px;
		border: none;
		background: transparent;
		border-radius: var(--radius-sm);
		color: var(--text-tertiary);
		cursor: pointer;
		display: flex;
		align-items: center;
		justify-content: center;
		transition: all var(--transition-fast);
	}

	.term-btn:hover {
		background: var(--surface-4);
		color: var(--text-primary);
	}

	.term-btn.close-btn:hover {
		background: rgba(255, 59, 48, 0.15);
		color: var(--danger);
	}

	.terminal-body {
		flex: 1;
		overflow: hidden;
		display: flex;
		flex-direction: column;
	}

	.terminal-output {
		flex: 1;
		overflow-y: auto;
		padding: var(--space-3) var(--space-4);
		font-family: var(--font-mono);
		font-size: 12px;
		line-height: 1.5;
		color: var(--text-secondary);
		background: var(--surface-1);
	}

	.output-line {
		white-space: pre-wrap;
		word-break: break-all;
	}

	.terminal-empty {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		color: var(--text-tertiary);
	}

	.prompt-symbol {
		color: var(--accent-1);
		font-weight: 700;
	}

	.welcome-text {
		font-style: italic;
	}

	.terminal-input-row {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		padding: var(--space-2) var(--space-4);
		background: var(--surface-2);
		border-top: var(--border-1) var(--border-color-1);
	}

	.terminal-input {
		flex: 1;
		border: none;
		background: none;
		font-family: var(--font-mono);
		font-size: 13px;
		color: var(--text-primary);
		outline: none;
	}

	.terminal-input::placeholder {
		color: var(--text-tertiary);
	}

	.terminal-empty-state {
		flex: 1;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: var(--space-3);
		color: var(--text-tertiary);
	}

	.empty-icon {
		margin-bottom: var(--space-2);
	}

	.terminal-empty-state p {
		font-size: var(--font-size-sm);
	}

	.spawn-btn {
		display: flex;
		align-items: center;
		gap: var(--space-2);
		padding: 6px 14px;
		border: var(--border-1) var(--accent-1);
		background: var(--accent-3);
		border-radius: var(--radius-sm);
		font-size: var(--font-size-xs);
		font-weight: 500;
		color: var(--accent-1);
		cursor: pointer;
		transition: all var(--transition-fast);
	}

	.spawn-btn:hover {
		background: var(--accent-1);
		color: var(--text-inverse);
	}

	/* Scrollbar */
	.terminal-output::-webkit-scrollbar {
		width: 6px;
	}

	.terminal-output::-webkit-scrollbar-track {
		background: transparent;
	}

	.terminal-output::-webkit-scrollbar-thumb {
		background: var(--surface-4);
		border-radius: var(--radius-full);
	}
</style>
