// =============================================================================
// Swarm Code Mobile — App State Store
// =============================================================================

import { writable, get } from 'svelte/store';
import type { ViewKind, AppState, BridgeThreadSummary, BridgeThreadDetail, SavedPairing, ConnectionStatus, BridgeStatus, BridgeModels } from '../types';

export const view = writable<ViewKind>('connect');
export const threads = writable<BridgeThreadSummary[]>([]);
export const activeThread = writable<BridgeThreadDetail | null>(null);
export const pairings = writable<SavedPairing[]>([]);
export const status = writable<BridgeStatus | null>(null);
export const models = writable<BridgeModels>({ providers: {} });
export const connectionStatus = writable<ConnectionStatus>('disconnected');
export const connectionError = writable<string | null>(null);
export const currentHost = writable('');
export const currentPort = writable<number>(8765);
export const isLoading = writable(false);
export const pendingActions = writable<{ id: string; kind: string; title: string; detail?: string }[]>([]);

export function getAppState(): AppState {
    return {
        status: get(connectionStatus),
        error: get(connectionError),
        threads: get(threads),
        activeThread: get(activeThread),
        pairings: get(pairings),
        currentHost: get(currentHost),
        currentPort: get(currentPort),
    };
}
