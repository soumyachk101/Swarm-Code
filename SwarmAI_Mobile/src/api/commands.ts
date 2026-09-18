// =============================================================================
// SwarmAI Mobile — Tauri Commands (Frontend → Rust Bridge)
// =============================================================================

import { invoke } from '@tauri-apps/api/core';

// ---- Types ----

export type ConnectionStatus = 'disconnected' | 'connecting' | 'connected' | 'paired' | 'reconnecting' | 'failed';
export type BridgeThreadSummary = import('../types').BridgeThreadSummary;
export type BridgeThreadDetail = import('../types').BridgeThreadDetail;
export type BridgeStatus = import('../types').BridgeStatus;
export type BridgeModels = import('../types').BridgeModels;
export type SavedPairing = import('../types').SavedPairing;

// ---- Connection ----

export async function getConnectionStatus(): Promise<ConnectionStatus> {
    return invoke('get_connection_status');
}

export async function connectToBridge(
    host: string,
    port: number,
): Promise<string> {
    return invoke('connect_to_bridge', { host, port });
}

export async function disconnectBridge(): Promise<void> {
    return invoke('disconnect_bridge');
}

export async function discoverBridges(): Promise<SavedPairing[]> {
    return invoke('discover_bridges');
}

// ---- Pairing ----

export async function savePairing(pairing: SavedPairing): Promise<SavedPairing> {
    return invoke('save_pairing', { pairing });
}

export async function getSavedPairings(): Promise<SavedPairing[]> {
    return invoke('get_saved_pairings');
}

export async function deletePairing(id: string): Promise<void> {
    return invoke('delete_pairing', { id });
}

// ---- Threads ----

export async function getThreads(
    host?: string,
    port?: number,
): Promise<BridgeThreadSummary[]> {
    return invoke('get_threads', { host, port });
}

export async function getThreadDetail(
    threadId: string,
    host?: string,
    port?: number,
): Promise<BridgeThreadDetail> {
    return invoke('get_thread_detail', { threadId, host, port });
}

// ---- Actions ----

export async function sendMessage(threadId: string, content: string): Promise<void> {
    return invoke('send_message', { threadId, content });
}

export async function approveAction(threadId: string, actionId: string): Promise<void> {
    return invoke('approve_action', { threadId, actionId });
}

export async function rejectAction(threadId: string, actionId: string): Promise<void> {
    return invoke('reject_action', { threadId, actionId });
}

export async function createThread(projectId?: string, prompt?: string): Promise<void> {
    return invoke('create_thread', { projectId, prompt });
}

// ---- Models ----

export async function getModels(
    host?: string,
    port?: number,
): Promise<BridgeModels> {
    return invoke('get_models', { host, port });
}

// ---- Git ----

export async function getGitStatus(threadId: string, host?: string, port?: number): Promise<string> {
    return invoke('get_git_status', { threadId, host, port });
}
