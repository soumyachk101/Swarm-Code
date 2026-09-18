// =============================================================================
// SwarmAI Mobile — Shared TypeScript Types
// =============================================================================

export type ViewKind = 'connect' | 'pair' | 'threads' | 'chat' | 'approvals' | 'settings';

export type ConnectionStatus = 'disconnected' | 'connecting' | 'connected' | 'paired' | 'reconnecting' | 'failed';

export type BridgeThreadSummary = {
    id: string;
    projectID: string;
    projectName: string;
    title: string;
    provider: string;
    model: string;
    lastStatus: string;
    hasUnread: boolean;
    updatedAt: string;
    messageCount: number;
    lastMessagePreview: string;
};

export type BridgeThreadDetail = {
    id: string;
    projectID: string;
    projectPath: string;
    title: string;
    provider: string;
    model: string;
    runtimeMode: string;
    createdAt: string;
    updatedAt: string;
    entries: BridgeTimelineEntry[];
    approvals: BridgeApproval[];
    diffRevision: number;
};

export type BridgeTimelineEntry = {
    id: string;
    kind: string;
    date: string;
    text?: string;
    name?: string;
    input?: string;
    output?: string;
    error?: string;
    summary?: string;
};

export type BridgeApproval = {
    id: string;
    kind: string;
    title: string;
    detail?: string;
    options: string[];
};

export type BridgeStatus = {
    status: string;
    version: string;
    threadCount: number;
    paired: boolean;
    connectedClients: number;
};

export type BridgeModels = {
    providers: Record<string, { id: string; models: string[] }>;
};

export type SavedPairing = {
    id: string;
    host: string;
    port: number;
    name: string;
    token: string;
    lastConnected?: string;
};

export type BridgeEvent = {
    type: string;
    threadID?: string;
    content?: string;
    isTool?: boolean;
    messageID?: string;
    tool?: string;
    input?: string;
    result?: string;
    error?: string;
    action?: string;
    details?: string;
    sessionToken?: string;
    reason?: string;
    projectID?: string;
    model?: string;
    code?: string;
};

export type AppState = {
    status: ConnectionStatus;
    error: string | null;
    threads: BridgeThreadSummary[];
    activeThread: BridgeThreadDetail | null;
    pairings: SavedPairing[];
    currentHost: string;
    currentPort: number;
};

export const initialState: AppState = {
    status: 'disconnected',
    error: null,
    threads: [],
    activeThread: null,
    pairings: [],
    currentHost: '',
    currentPort: 8765,
};
