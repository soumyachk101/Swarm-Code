<script lang="ts">
import { onMount } from 'svelte';
import {
    disconnectBridge, getModels, getConnectionStatus
} from '../api/commands';
import {
    connectionStatus, connectionError, models, view, currentHost, currentPort
} from '../stores/appStore';

let statusString = 'Disconnected';

const handleDisconnect = async () => {
    await disconnectBridge();
    connectionStatus.set('disconnected');
    view.set('connect');
};

const handleFetchModels = async () => {
    const host = $currentHost;
    const port = $currentPort;
    if (!host) return;
    try {
        const { getModels } = await import('../api/commands');
        const result = await getModels(host, port);
        models.set(result);
    } catch (err) {
        console.error('Failed to fetch models:', err);
    }
};

const statusLabel: Record<string, string> = {
    disconnected: 'Disconnected',
    connecting: 'Connecting…',
    connected: 'Connected',
    paired: 'Paired',
    reconnecting: 'Reconnecting…',
    failed: 'Connection Failed',
};

onMount(() => {
    const unsub = connectionStatus.subscribe(s => {
        statusString = statusLabel[s] || s;
    });
    return () => unsub();
});

const goBack = () => view.set('threads');
</script>

<div class="screen">
    <div class="header" style="padding-top: calc(12px + var(--safe-top));">
        <button class="header-back" on:click={goBack}>
            <svg width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" viewBox="0 0 24 24"><polyline points="15 18 9 12 15 6"/></svg>
        </button>
        <div>
            <h2 class="text-primary" style="font-size: 20px; font-weight: 700;">Settings</h2>
        </div>
    </div>

    <div class="divider"></div>

    <div class="scrollable" style="padding: 20px 16px;">
        <!-- Connection Status -->
        <div class="glass" style="padding: 18px; border-radius: var(--radius-lg); margin-bottom: 16px;">
            <h3 style="margin-bottom: 14px;">Connection</h3>
            <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 12px;">
                <span class="text-secondary" style="font-size: 14px;">Status</span>
                <div style="display: flex; align-items: center; gap: 8px;">
                    <span class="status-dot {$connectionStatus === 'paired' || $connectionStatus === 'connected' ? 'connected' : $connectionStatus}"></span>
                    <span style="font-size: 14px; font-weight: 500;">{$connectionStatus === 'paired' || $connectionStatus === 'connected' ? 'Connected' : statusString}</span>
                </div>
            </div>
            {#if $currentHost}
                <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px;">
                    <span class="text-secondary" style="font-size: 14px;">Host</span>
                    <span style="font-size: 14px; font-family: 'SF Mono', monospace;">{$currentHost}:{$currentPort}</span>
                </div>
            {/if}
            <button class="btn btn-danger btn-full btn-sm" on:click={handleDisconnect}>
                Disconnect
            </button>
        </div>

        <!-- Models -->
        <div class="glass" style="padding: 18px; border-radius: var(--radius-lg); margin-bottom: 16px;">
            <h3 style="margin-bottom: 14px;">Models</h3>
            {#if Object.keys($models.providers).length === 0}
                <p class="text-secondary" style="font-size: 13px; margin-bottom: 12px;">No models fetched yet. Pull them from your Mac.</p>
                <button class="btn btn-secondary btn-full btn-sm" on:click={handleFetchModels}>
                    Refresh Models
                </button>
            {:else}
                <div style="display: flex; flex-direction: column; gap: 12px;">
                    {#each Object.entries($models.providers) as [providerId, info]}
                        <div>
                            <div style="font-size: 13px; font-weight: 600; color: var(--text-primary); margin-bottom: 4px; text-transform: capitalize;">{providerId}</div>
                            <div style="display: flex; flex-wrap: wrap; gap: 6px;">
                                {#each info.models.slice(0, 6) as model}
                                    <span class="model-badge">{model}</span>
                                {/each}
                                {#if info.models.length > 6}
                                    <span class="text-muted" style="font-size: 12px;">+{info.models.length - 6} more</span>
                                {/each}
                            </div>
                        </div>
                    {/each}
                </div>
            {/if}
        </div>

        <!-- About -->
        <div class="glass" style="padding: 18px; border-radius: var(--radius-lg);">
            <h3 style="margin-bottom: 8px;">About</h3>
            <div style="font-size: 14px; color: var(--text-secondary); line-height: 1.6;">
                <p>Swarm Code Mobile v0.1.0</p>
                <p class="text-muted" style="font-size: 12px; margin-top: 4px;">Works with Swarm Code on macOS via local bridge. Requires Swarm Code bridge enabled in Settings.</p>
            </div>
        </div>
    </div>

    <!-- Bottom Nav -->
    <nav class="tab-bar">
        <div class="tab-item" on:click={() => view.set('threads')}>
            <span class="tab-icon">💬</span>
            <span>Threads</span>
        </div>
        <div class="tab-item active">
            <span class="tab-icon">⚙️</span>
            <span>Settings</span>
        </div>
    </nav>
</div>
