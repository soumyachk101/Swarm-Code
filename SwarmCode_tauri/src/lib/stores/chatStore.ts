// =============================================================================
// Swarm Code Tauri Frontend — Chat Store
// =============================================================================

import { derived, writable, type Readable, type Writable } from 'svelte/store';
import type {
	ChatThread,
	ThreadDocument,
	ThreadSummary,
	MessageChunk,
	FollowUpPrompt,
	ApprovalRequest,
	QuestionRequest,
	ContextUsage,
	AttachmentInfo,
	MessageOptions,
} from '$lib/types';
import type { StreamEvent } from '$lib/api/events';
import * as Commands from '$lib/api/commands';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

export const threads: Writable<ChatThread[]> = writable([]);
export const threadSummaries: Writable<ThreadSummary[]> = writable([]);
export const activeThreadId: Writable<string | null> = writable(null);
export const threadDocument: Writable<ThreadDocument | null> = writable(null);
export const threadUsage: Writable<ContextUsage | null> = writable(null);
export const isGenerating: Writable<boolean> = writable(false);
export const isPaused: Writable<boolean> = writable(false);
export const pendingApprovals: Writable<ApprovalRequest[]> = writable([]);
export const pendingQuestions: Writable<QuestionRequest[]> = writable([]);
export const followUps: Writable<FollowUpPrompt[]> = writable([]);
export const streamingError: Writable<string | null> = writable(null);
export const searchQuery: Writable<string> = writable('');
export const currentProvider: Writable<string | null> = writable(null);
export const currentModel: Writable<string | null> = writable(null);
export const effortLevel: Writable<string | null> = writable(null);

// ---------------------------------------------------------------------------
// Hydra state (loose coupling — hydraStore owns authority)
// ---------------------------------------------------------------------------

export const hydraPanelOpen: Writable<boolean> = writable(false);
export const hydraEnabled: Writable<boolean> = writable(false);
export const hydraHeadCount: Writable<number> = writable(2);

// ---------------------------------------------------------------------------
// Attachment state (composer)
// ---------------------------------------------------------------------------

export interface ChangeStats {
	files: number;
	additions: number;
	deletions: number;
}

export const changeStats: Writable<ChangeStats | null> = writable(null);

// ---------------------------------------------------------------------------
// Attachment state (composer)
// ---------------------------------------------------------------------------

export const attachments: Writable<AttachmentInfo[]> = writable([]);

// ---------------------------------------------------------------------------
// Derived
// ---------------------------------------------------------------------------

export const activeThread: Readable<ChatThread | null> = derived(
	[threads, activeThreadId],
	([$threads, $activeThreadId]) =>
		$threads.find((t) => t.id === $activeThreadId) ?? null,
);

export const filteredThreads: Readable<ChatThread[]> = derived(
	[threads, searchQuery],
	([$threads, $searchQuery]) => {
		if (!$searchQuery) return $threads;
		const q = $searchQuery.toLowerCase();
		return $threads.filter(
			(t) =>
				t.title.toLowerCase().includes(q) ||
				t.branch?.toLowerCase().includes(q) ||
				t.model?.toLowerCase().includes(q),
		);
	},
);

export const pinnedThreads: Readable<ChatThread[]> = derived(
	threads,
	($threads) => $threads.filter((t) => t.is_pinned && !t.is_archived),
);

export const activeThreadMessages: Readable<ThreadDocument | null> = derived(
	[threadDocument],
	([$doc]) => $doc,
);

export const hasPendingApprovals: Readable<boolean> = derived(
	pendingApprovals,
	($a) => $a.length > 0,
);

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

export async function selectThread(threadId: string | null): Promise<void> {
	activeThreadId.set(threadId);
	if (threadId) {
		await loadThreadDocument(threadId);
	}
	else {
		threadDocument.set(null);
		threadUsage.set(null);
	}
}

export async function loadThreadDocument(threadId: string): Promise<void> {
	try {
		const doc = await Commands.getThreadDocument(threadId);
		threadDocument.set(doc);
		followUps.set(doc.follow_ups ?? []);
	} catch (err) {
		console.error('Failed to load thread document:', err);
	}
}

export async function loadThreads(projectId: string | null = null): Promise<void> {
	try {
		const [allThreads, summaries] = await Promise.all([
			Commands.getThreads(projectId),
			Commands.getRecentThreads(50),
		]);
		threads.set(allThreads);
		threadSummaries.set(summaries);
	} catch (err) {
		console.error('Failed to load threads:', err);
	}
}

export async function sendChatMessage(
	text: string,
	options: Partial<MessageOptions> = {},
): Promise<void> {
	const threadId = $activeThreadId;
	if (!threadId) return;

	const mergedOptions: MessageOptions = {
		effort: options.effort ?? $effortLevel,
		fast_mode: options.fast_mode ?? false,
		interaction_mode: options.interaction_mode ?? null,
		attachments: options.attachments ?? [],
		hydra_enabled: options.hydra_enabled ?? $hydraEnabled,
		hydra_pair_id: options.hydra_pair_id ?? null,
	};

	isGenerating.set(true);
	streamingError.set(null);

	try {
		const chunk = await Commands.sendMessage(threadId, text, mergedOptions);
		await loadThreadDocument(threadId);
	} catch (err) {
		streamingError.set(err instanceof Error ? err.message : 'Failed to send message');
		console.error('Send message failed:', err);
	} finally {
		isGenerating.set(false);
	}
}

export async function approveRequestAction(
	requestId: string,
	role: string,
): Promise<void> {
	const threadId = $activeThreadId;
	if (!threadId) return;
	try {
		await Commands.approveRequest(threadId, requestId, role);
		pendingApprovals.update((list) =>
			list.filter((a) => a.id !== requestId),
		);
	} catch (err) {
		console.error('Approval failed:', err);
	}
}

export async function answerQuestionAction(
	questionId: string,
	answers: string[],
): Promise<void> {
	const threadId = $activeThreadId;
	if (!threadId) return;
	try {
		await Commands.answerQuestion(threadId, questionId, answers);
		pendingQuestions.update((list) =>
			list.filter((q) => q.id !== questionId),
		);
	} catch (err) {
		console.error('Question answer failed:', err);
	}
}

export function setProvider(provider: string | null): void {
	currentProvider.set(provider);
}

export function setModel(model: string | null): void {
	currentModel.set(model);
}

export function setEffort(effort: string | null): void {
	effortLevel.set(effort);
}

export function toggleHydra(): void {
	hydraEnabled.update((v) => !v);
}

export function addAttachment(file: AttachmentInfo): void {
	attachments.update((list) => [...list, file]);
}

export function removeAttachment(id: string): void {
	attachments.update((list) => list.filter((a) => a.id !== id));
}

export function clearAttachments(): void {
	attachments.set([]);
}

export function stopGeneration(): void {
	isPaused.set(true);
}

// ---------------------------------------------------------------------------
// Streaming handler — call from main.js after wiring event listeners
// ---------------------------------------------------------------------------

// StreamEvent is re-exported from events
import type { StreamEvent } from '$lib/api/events';

export function handleStreamEvent(event: StreamEvent): void {
	const threadId = event.type.includes('threadId') ? (event as any).threadId : null;

	switch (event.type) {
		case 'text_delta':
		case 'reasoning_delta': {
			threadDocument.update((doc) => {
				if (!doc) return doc;
				return {
					...doc,
					items: [...doc.items],
				};
			});
			break;
		}
		case 'tool_start': {
			threadDocument.update((doc) => {
				if (!doc) return doc;
				return {
					...doc,
					items: [
						...doc.items,
						{
							id: event.toolId,
							turn_id: null,
							date: new Date().toISOString(),
							content: {
								type: 'tool',
								value: {
									kind: event.kind,
									title: event.title,
									detail: null,
									output: '',
									status: 'running',
									exit_code: null,
									edits: [],
									started_at: new Date().toISOString(),
									finished_at: null,
								},
							} as any,
						},
					],
				};
			});
			break;
		}
		case 'tool_output': {
			threadDocument.update((doc) => {
				if (!doc) return doc;
				const items = [...doc.items];
				for (let i = items.length - 1; i >= 0; i--) {
					const item = items[i];
					if (
						item.content.type === 'tool' &&
						(item.content.value as any).id === event.toolId
					) {
						const tool = item.content.value as any;
						items[i] = {
							...item,
							content: {
								type: 'tool',
								value: {
									...tool,
									output: tool.output + event.delta,
								},
							} as any,
						};
						break;
					}
				}
				return { ...doc, items };
			});
			break;
		}
		case 'tool_complete': {
			threadDocument.update((doc) => {
				if (!doc) return doc;
				const items = [...doc.items];
				for (let i = items.length - 1; i >= 0; i--) {
					const item = items[i];
					if (
						item.content.type === 'tool' &&
						(item.content.value as any).id === event.toolId
					) {
						const tool = item.content.value as any;
						items[i] = {
							...item,
							content: {
								type: 'tool',
								value: {
									...tool,
									status: event.status,
									finished_at: new Date().toISOString(),
								},
							} as any,
						};
						break;
					}
				}
				return { ...doc, items };
			});
			break;
		}
		case 'turn_end': {
			isGenerating.set(false);
			threadDocument.update((doc) => {
				if (!doc) return doc;
				return {
					...doc,
					turns: [
						...doc.turns,
						{
							id: event.turnId,
							index: doc.turns.length,
							provider_turn_id: null,
							started_at: new Date().toISOString(),
							completed_at: new Date().toISOString(),
							status: 'completed',
							base_checkpoint: null,
							end_checkpoint: null,
							user_item_id: null,
							provider_diff: null,
							provider_anchor: null,
							touched_paths: null,
							hydra_merged: false,
						},
					],
				};
			});
			break;
		}
	}
}
