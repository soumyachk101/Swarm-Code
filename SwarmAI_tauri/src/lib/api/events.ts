// =============================================================================
// SwarmAI Tauri Frontend — Event Listeners & Streaming
// =============================================================================

import { listen, type UnlistenFn } from '@tauri-apps/api/event';
import type {
	MessageChunk,
	ProviderStatus,
	ProviderCredits,
	GitStatus,
	DiffEntry,
	TerminalSession,
	ApprovalRequest,
	QuestionRequest,
	HydraReport,
	ContextUsage,
} from '$lib/types';

// ---------------------------------------------------------------------------
// Streaming events
// ---------------------------------------------------------------------------

export type StreamEvent =
	| { type: 'text_delta'; threadId: string; delta: string }
	| { type: 'reasoning_delta'; threadId: string; delta: string }
	| { type: 'tool_start'; threadId: string; toolId: string; kind: string; title: string }
	| { type: 'tool_output'; threadId: string; toolId: string; delta: string }
	| { type: 'tool_complete'; threadId: string; toolId: string; status: string }
	| { type: 'plan_draft'; threadId: string; markdown: string }
	| { type: 'notice'; threadId: string; level: string; message: string }
	| { type: 'turn_end'; threadId: string; turnId: string; duration: number }
	| { type: 'turn_status'; threadId: string; status: string };

export function onStreamMessage(
	callback: (event: StreamEvent) => void,
): Promise<UnlistenFn> {
	return listen<StreamEvent>('stream:message', (event) => {
		callback(event.payload);
	});
}

// ---------------------------------------------------------------------------
// Provider events
// ---------------------------------------------------------------------------

export function onProviderStatusChanged(
	callback: (status: ProviderStatus) => void,
): Promise<UnlistenFn> {
	return listen<ProviderStatus>('provider:status_changed', (event) => {
		callback(event.payload);
	});
}

export function onProviderCreditsChanged(
	callback: (credits: ProviderCredits) => void,
): Promise<UnlistenFn> {
	return listen<ProviderCredits>('provider:credits_changed', (event) => {
		callback(event.payload);
	});
}

// ---------------------------------------------------------------------------
// Git events
// ---------------------------------------------------------------------------

export function onGitStatusChanged(
	callback: (status: GitStatus) => void,
): Promise<UnlistenFn> {
	return listen<GitStatus>('git:status_changed', (event) => {
		callback(event.payload);
	});
}

export function onGitDiffChanged(
	callback: (diffs: DiffEntry[]) => void,
): Promise<UnlistenFn> {
	return listen<DiffEntry[]>('git:diff_changed', (event) => {
		callback(event.payload);
	});
}

// ---------------------------------------------------------------------------
// Terminal events
// ---------------------------------------------------------------------------

export type TerminalEvent =
	| { type: 'output'; sessionId: string; stream: string; data: string }
	| { type: 'resize'; sessionId: string; rows: number; cols: number }
	| { type: 'closed'; sessionId: string }
	| { type: 'started'; sessionId: string; pid: number };

export function onTerminalOutput(
	callback: (event: TerminalEvent) => void,
): Promise<UnlistenFn> {
	return listen<TerminalEvent>('terminal:output', (event) => {
		callback(event.payload);
	});
}

// ---------------------------------------------------------------------------
// Approval / Question events
// ---------------------------------------------------------------------------

export function onApprovalRequest(
	callback: (request: ApprovalRequest) => void,
): Promise<UnlistenFn> {
	return listen<ApprovalRequest>('approval:request', (event) => {
		callback(event.payload);
	});
}

export function onQuestionRequest(
	callback: (request: QuestionRequest) => void,
): Promise<UnlistenFn> {
	return listen<QuestionRequest>('question:request', (event) => {
		callback(event.payload);
	});
}

// ---------------------------------------------------------------------------
// Hydra events
// ---------------------------------------------------------------------------

export function onHydraReport(
	callback: (report: HydraReport) => void,
): Promise<UnlistenFn> {
	return listen<HydraReport>('hydra:report', (event) => {
		callback(event.payload);
	});
}

export function onHydraHeadStatus(
	callback: (head: HydraReport) => void,
): Promise<UnlistenFn> {
	return listen<HydraReport>('hydra:head_status', (event) => {
		callback(event.payload);
	});
}

// ---------------------------------------------------------------------------
// Thread events
// ---------------------------------------------------------------------------

export type ThreadEvent =
	| { type: 'created'; thread: ChatThread }
	| { type: 'updated'; thread: ChatThread }
	| { type: 'deleted'; threadId: string }
	| { type: 'status_changed'; threadId: string; status: string };

export function onThreadEvent(
	callback: (event: ThreadEvent) => void,
): Promise<UnlistenFn> {
	return listen<ThreadEvent>('thread:event', (event) => {
		callback(event.payload);
	});
}

// ---------------------------------------------------------------------------
// Usage events
// ---------------------------------------------------------------------------

export function onUsageChanged(
	callback: (usage: ContextUsage) => void,
): Promise<UnlistenFn> {
	return listen<ContextUsage>('usage:changed', (event) => {
		callback(event.payload);
	});
}

// ---------------------------------------------------------------------------
// Generic helper
// ---------------------------------------------------------------------------

export function onNotification(
	callback: (message: string) => void,
): Promise<UnlistenFn> {
	return listen<string>('notification', (event) => {
		callback(event.payload);
	});
}
