<script lang="ts">
import { onMount } from 'svelte';
import { getThreads, disconnectBridge } from '../api/commands';
import { threads, activeThread, view, connectionStatus, currentHost, currentPort } from '../stores/appStore';

const loadThreads = async () => {
    const host = $currentHost;
    const port = $currentPort;
    if (!host) return;
    const result = await getThreads(host, port);
    threads.set(result);
};

const selectThread = async (threadId: string) => {
    const host = $currentHost;
    const port = $currentPort;
    const detail = await (await import('../api/commands')).getThreadDetail(threadId, host, port);
    activeThread.set(detail);
    view.set('chat');
};

const handleDisconnect = async () => {
    await disconnectBridge();
    connectionStatus.set('disconnected');
    threads.set([]);
    activeThread.set(null);
    view.set('connect');
};

onMount(() => {
    loadThreads();
});

const formatTime = (dateStr: string) => {
    const d = new Date(dateStr);
    const now = new Date();
    const diffMs = now.getTime() - d.getTime();
    const diffMins = Math.floor(diffMs / 60000);
    if (diffMins < 1) return 'Just now';
    if (diffMins < 60) return `${diffMins}m ago`;
    const diffHours = Math.floor(diffMins / 60);
    if (diffHours < 24) return `${diffHours}h ago`;
    return d.toLocaleDateString();
};
</script>

<div class="screen">
    <!-- Header -->
    <div class="header" style="padding-top: calc(12px + var(--safe-top));">
        <div>
            <h2 class="text-primary" style="font-size: 20px; font-weight: 700;">Swarm Code</h2>
            <div style="display: flex; align-items: center; gap: 6px; margin-top: 2px;">
                <span class="status-dot {($connectionStatus === 'paired' || $connectionStatus === 'connected') ? 'connected' : 'disconnected'}"></span>
                <span style="font-size: 12px; color: var(--text-muted);">
                    {$connectionStatus === 'paired' || $connectionStatus === 'connected' ? 'Connected' : 'Disconnected'}
                </span>
            </div>
        </div>
        <button class="btn btn-sm btn-secondary" on:click={handleDisconnect}>Disconnect</button>
    </div>

    <div class="divider"></div>

    <!-- Thread List -->
    {#if $threads.length === 0}
        <div class="empty-state">
            <div class="empty-icon">💬</div>
            <div class="empty-title">No Threads</div>
            <div class="empty-desc">Your Mac has no active threads yet. Start a conversation in Swarm Code on your Mac to see it here.</div>
        </div>
    {:else}
        <div class="scrollable">
            {#each $threads as thread}
                <div class="thread-item" on:click={() => selectThread(thread.id)}>
                    <div style="display: flex; align-items: center; justify-content: space-between;">
                        <div class="thread-item-title">{thread.title || 'Untitled Thread'}</div>
                        {#if thread.hasUnread}
                            <span class="unread-badge"></span>
                        {/if}
                    </div>
                    <div class="thread-item-preview">
                        {thread.lastMessagePreview || 'No messages yet'}
                    </div>
                    <div class="thread-item-meta">
                        <span class="model-badge">{thread.provider}</span>
                        {#if thread.model}
                            <span class="model-badge" style="background: rgba(255,255,255,0.05); color: var(--text-secondary);">
                                {thread.model.length > 20 ? thread.model.slice(0, 20) + '…' : thread.model}
                            </span>
                        {/if}
                        <span>{formatTime(thread.updatedAt)}</span>
                        <span>{thread.messageCount} msgs</span>
                    </div>
                </div>
            {/each}
        </div>
    {/if}

    <!-- Bottom Nav -->
    <nav class="tab-bar">
        <div class="tab-item active">
            <span class="tab-icon">💬</span>
            <span>Threads</span>
        </div>
        <div class="tab-item" on:click={() => view.set('settings')}>
            <span class="tab-icon">⚙️</span>
            <span>Settings</span>
        </div>
    </nav>
</div>
