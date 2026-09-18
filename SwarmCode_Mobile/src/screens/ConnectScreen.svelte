<script lang="ts">
import { onMount } from 'svelte';
import { discoverBridges, connectToBridge, savePairing, getSavedPairings } from '../api/commands';
import {
    connectionStatus, currentHost, currentPort, pairings, connectionError, isLoading, view, threads
} from '../stores/appStore';

let hostInput = '';
let portInput = '8765';
let discoveryResults: { id: string; host: string; port: number; name: string }[] = [];
let isDiscovering = false;

const autoConnect = async () => {
    const saved = await getSavedPairings();
    pairings.set(saved);
    if (saved.length > 0 && saved[0].host) {
        hostInput = saved[0].host;
        portInput = String(saved[0].port);
        handleConnect();
    }
};

const handleConnect = async () => {
    if (!hostInput.trim()) return;
    const host = hostInput.trim();
    if (/^([0-9A-Fa-f]{2}[:-]){5}([0-9A-Fa-f]{2})$/.test(host)) {
        connectionError.set("Hardware MAC address detected. Please enter your Mac's IP address (e.g. 192.168.1.x or localhost), not the hardware MAC address.");
        return;
    }
    const port = parseInt(portInput) || 8765;
    currentHost.set(host);
    currentPort.set(port);
    isLoading.set(true);
    connectionError.set(null);

    try {
        const result = await connectToBridge(host, port);
        connectionStatus.set('connected');
        view.set('pair');
    } catch (err) {
        connectionStatus.set('failed');
        connectionError.set(err instanceof Error ? err.message : String(err));
    } finally {
        isLoading.set(false);
    }
};

const loadThreads = async (host: string, port: number) => {
    try {
        isLoading.set(true);
        const { getThreads } = await import('../api/commands');
        const result = await getThreads(host, port);
        threads.set(result);
    } catch (err) {
        console.error('Failed to load threads:', err);
    } finally {
        isLoading.set(false);
    }
};

const handleDiscover = async () => {
    isDiscovering = true;
    discoveryResults = [];
    try {
        const results = await discoverBridges();
        discoveryResults = results.map(r => ({
            id: r.id,
            host: r.host,
            port: r.port,
            name: r.name,
        }));
    } catch (err) {
        console.error('Discovery failed:', err);
    } finally {
        isDiscovering = false;
    }
};

const selectDiscovery = (host: string, port: number) => {
    hostInput = host;
    portInput = String(port);
    handleConnect();
};

onMount(() => {
    getSavedPairings().then(saved => {
        pairings.set(saved);
        if (saved.length > 0 && saved[0].host) {
            hostInput = saved[0].host;
            portInput = String(saved[0].port);
        }
    });
});
</script>

<div class="screen" style="justify-content: center; padding: 24px;">
    <!-- Logo / Brand -->
    <div style="text-align: center; margin-bottom: 40px;">
        <div style="
            width: 80px; height: 80px; margin: 0 auto 16px;
            border-radius: 22px; display: flex; align-items: center; justify-content: center;
            background: linear-gradient(135deg, var(--accent), #9d7aff);
            font-size: 40px; color: white; font-weight: 700;
            box-shadow: 0 8px 32px var(--accent-glow);
        ">S</div>
        <h1 style="font-size: 28px; margin-bottom: 6px;">Swarm Code</h1>
        <p style="font-size: 14px;">Connect to your Mac to control Swarm Code remotely</p>
    </div>

    <!-- Connection Form -->
    <div class="glass" style="padding: 20px; border-radius: var(--radius-lg); margin-bottom: 20px;">
        <div style="display: flex; flex-direction: column; gap: 14px;">
            <div>
                <label class="text-secondary" style="font-size: 12px; font-weight: 600; display: block; margin-bottom: 6px; text-transform: uppercase; letter-spacing: 0.05em;">Mac IP Address / Hostname</label>
                <input
                    class="input"
                    type="text"
                    placeholder="localhost or 192.168.1.x"
                    bind:value={hostInput}
                    autocomplete="off"
                />
            </div>
            <div>
                <label class="text-secondary" style="font-size: 12px; font-weight: 600; display: block; margin-bottom: 6px; text-transform: uppercase; letter-spacing: 0.05em;">Port</label>
                <input
                    class="input"
                    type="number"
                    placeholder="8765"
                    bind:value={portInput}
                />
            </div>
            <button
                class="btn btn-primary btn-full"
                disabled={$isLoading || !hostInput.trim()}
                onclick={handleConnect}
            >
                {#if $isLoading}
                    Connecting...
                {:else}
                    Connect
                {/if}
            </button>
        </div>
    </div>

    <!-- Error Display -->
    {#if $connectionError}
        <div style="
            padding: 12px 16px; border-radius: var(--radius-md); margin-bottom: 16px;
            background: rgba(248, 113, 113, 0.1); border: 1px solid rgba(248, 113, 113, 0.2);
            color: var(--danger); font-size: 13px;
        ">
            {$connectionError}
        </div>
    {/if}

    <!-- Discover Button -->
    <button
        class="btn btn-secondary btn-full"
        disabled={isDiscovering}
        onclick={handleDiscover}
    >
        {isDiscovering ? 'Discovering...' : 'Discover Swarm Code on Network'}
    </button>

    {#if discoveryResults.length > 0}
        <div style="margin-top: 20px;">
            <h3 style="margin-bottom: 12px;">Found Devices</h3>
            {#each discoveryResults as result}
                <div class="glass thread-item" onclick={() => selectDiscovery(result.host, result.port)}>
                    <div class="thread-item-title">{result.name}</div>
                    <div class="thread-item-meta">
                        <span>{result.host}:{result.port}</span>
                    </div>
                </div>
            {/each}
        </div>
    {/if}

    <!-- Saved Pairings -->
    {#if $pairings.length > 0 && discoveryResults.length === 0}
        <div style="margin-top: 20px;">
            <h3 style="margin-bottom: 12px;">Recent Connections</h3>
            {#each $pairings as pairing}
                <div class="glass thread-item" onclick={() => {
                    hostInput = pairing.host;
                    portInput = String(pairing.port);
                    handleConnect();
                }}>
                    <div class="thread-item-title">{pairing.name}</div>
                    <div class="thread-item-meta">
                        <span>{pairing.host}:{pairing.port}</span>
                        {#if pairing.lastConnected}
                            <span>Last: {new Date(pairing.lastConnected).toLocaleDateString()}</span>
                        {/if}
                    </div>
                </div>
            {/each}
        </div>
    {/if}
</div>
