<script lang="ts">
import { onMount } from 'svelte';
import { activeThread, view, threads } from '../stores/appStore';

let messagesContainer: HTMLDivElement;
let messageInput: HTMLInputElement;
let inputText = '';

$: if ($activeThread) {
    scrollToBottom();
}

const goBack = () => {
    activeThread.set(null);
    view.set('threads');
};

const sendMessage = async () => {
    if (!inputText.trim() || !$activeThread) return;
    const text = inputText.trim();
    inputText = '';

    try {
        const { sendMessage } = await import('../api/commands');
        await sendMessage($activeThread.id, text);
    } catch (err) {
        console.error('Send failed:', err);
    }
};

const handleKeyDown = (e: KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        sendMessage();
    }
};

const scrollToBottom = () => {
    if (messagesContainer) {
        messagesContainer.scrollTop = messagesContainer.scrollHeight;
    }
};

const formatTime = (dateStr: string) => {
    const d = new Date(dateStr);
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
};

const getMessageClass = (kind: string) => {
    switch (kind) {
        case 'user': return 'message-user';
        case 'assistant': return 'message-assistant';
        case 'tool': return 'message-tool';
        case 'reasoning': return 'message-thinking';
        default: return 'message-assistant';
    }
};

const getRoleLabel = (kind: string) => {
    switch (kind) {
        case 'user': return 'You';
        case 'assistant': return 'Assistant';
        case 'tool': return 'Tool';
        case 'reasoning': return 'Thinking';
        case 'notice': return 'System';
        default: return kind;
    }
};
</script>

<div class="screen">
    <!-- Header -->
    <div class="header" style="padding-top: calc(12px + var(--safe-top));">
        <button class="header-back" on:click={goBack}>
            <svg width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" viewBox="0 0 24 24"><polyline points="15 18 9 12 15 6"/></svg>
        </button>
        <div style="flex: 1; margin-left: 12px; min-width: 0;">
            <div class="thread-item-title" style="font-size: 16px;">
                {$activeThread?.title || 'Thread'}
            </div>
            <div class="thread-item-meta">
                <span class="model-badge">{$activeThread?.provider || '—'}</span>
                {#if $activeThread?.model}
                    <span style="font-size: 11px; color: var(--text-muted);">
                        {$activeThread.model.length > 25 ? $activeThread.model.slice(0, 25) + '…' : $activeThread.model}
                    </span>
                {/if}
            </div>
        </div>
    </div>

    <div class="divider"></div>

    <!-- Messages -->
    <div class="scrollable" bind:this={messagesContainer} style="padding: 16px 0;">
        {#if $activeThread?.entries?.length === 0}
            <div class="empty-state">
                <div class="empty-icon">✉️</div>
                <div class="empty-title">No messages</div>
                <div class="empty-desc">Start the conversation by sending a message below.</div>
            </div>
        {:else}
            {#each $activeThread?.entries || [] as entry}
                <div style="
                    display: flex;
                    padding: 6px 16px;
                    align-items: flex-start;
                    gap: 8px;
                ">
                    <div style="flex: 1; min-width: 0;">
                        <div style="
                            display: flex; align-items: center; gap: 6px; margin-bottom: 4px;
                        ">
                            <span style="font-size: 11px; font-weight: 600; color: var(--accent);">
                                {getRoleLabel(entry.kind)}
                            </span>
                            <span style="font-size: 11px; color: var(--text-muted);">
                                {formatTime(entry.date)}
                            </span>
                        </div>
                        <div class="message-bubble {getMessageClass(entry.kind)}">
                            {#if entry.kind === 'tool'}
                                <div style="font-size: 11px; font-weight: 600; margin-bottom: 4px; opacity: 0.7;">
                                    {entry.name || 'tool'}
                                </div>
                                {#if entry.input}
                                    <div style="font-size: 12px; opacity: 0.6; margin-bottom: 4px;">> {entry.input.slice(0, 100)}{entry.input.length > 100 ? '…' : ''}</div>
                                {/if}
                                {#if entry.output}
                                    <div style="font-size: 12px; white-space: pre-wrap;">{entry.output.slice(0, 500)}{entry.output.length > 500 ? '…' : ''}</div>
                                {/if}
                                {#if entry.error}
                                    <div style="font-size: 12px; color: var(--danger); margin-top: 4px;">Error: {entry.error.slice(0, 200)}</div>
                                {/if}
                            {:else}
                                {#if entry.text}
                                    {entry.text.slice(0, 2000)}
                                    {entry.text.length > 2000 ? '…' : ''}
                                {/if}
                            {/if}
                        </div>
                    </div>
                </div>
            {/each}
        {/if}
    </div>

    <!-- Composer -->
    <div class="composer">
        <input
            class="composer-input"
            type="text"
            placeholder="Message..."
            bind:value={inputText}
            bind:this={messageInput}
            on:keydown={handleKeyDown}
        />
        <button
            class="composer-send"
            disabled={!inputText.trim()}
            on:click={sendMessage}
        >
            <svg width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" viewBox="0 0 24 24"><line x1="22" y1="2" x2="11" y2="13"/><polygon points="22 2 15 22 11 13 2 9 22 2"/></svg>
        </button>
    </div>
</div>
