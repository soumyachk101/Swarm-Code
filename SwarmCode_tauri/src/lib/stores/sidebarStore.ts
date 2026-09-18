// =============================================================================
// Swarm Code Tauri Frontend — Sidebar Store
// =============================================================================

import { writable, derived, type Readable, type Writable } from 'svelte/store';
import type { ChatThread, ThreadSummary, Project, UUID } from '$lib/types';
import * as Commands from '$lib/api/commands';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

export const threads: Writable<ChatThread[]> = writable([]);
export const threadSummaries: Writable<ThreadSummary[]> = writable([]);
export const selectedThreadId: Writable<string | null> = writable(null);
export const searchQuery: Writable<string> = writable('');
export const activeProjectId: Writable<string | null> = writable(null);
export const projects: Writable<Project[]> = writable([]);
export const isCreatingThread: Writable<boolean> = writable(false);
export const sidebarWidth: Writable<number> = writable(260);
export const showArchive: Writable<boolean> = writable(false);
export const sortOrder: Writable<'recent' | 'alpha' | 'pinned'> = writable('recent');

// ---------------------------------------------------------------------------
// Derived
// ---------------------------------------------------------------------------

export const filteredThreads: Readable<ChatThread[]> = derived(
	[threads, searchQuery, showArchive, sortOrder],
	([$threads, $searchQuery, $showArchive, $sortOrder]) => {
		let list = $threads;

		if (!$showArchive) {
			list = list.filter((t) => !t.is_archived);
		}

		if ($searchQuery) {
			const q = $searchQuery.toLowerCase();
			list = list.filter(
				(t) =>
					t.title?.toLowerCase().includes(q) ||
					t.branch?.toLowerCase().includes(q) ||
					t.model?.toLowerCase().includes(q),
			);
		}

		switch ($sortOrder) {
			case 'pinned':
				return [...list].sort((a, b) => (b.is_pinned ? 1 : 0) - (a.is_pinned ? 1 : 0));
			case 'alpha':
				return [...list].sort((a, b) => (a.title ?? '').localeCompare(b.title ?? ''));
			case 'recent':
			default:
				return [...list].sort(
					(a, b) =>
						new Date(b.created_at ?? 0).getTime() - new Date(a.created_at ?? 0).getTime(),
				);
		}
	},
);

export const selectedThread: Readable<ChatThread | null> = derived(
	[threads, selectedThreadId],
	([$threads, $selectedThreadId]) =>
		$threads.find((t) => t.id === $selectedThreadId) ?? null,
);

export const threadCount: Readable<number> = derived(threads, ($threads) => $threads.length);

export const unarchivedCount: Readable<number> = derived(
	threads,
	($threads) => $threads.filter((t) => !t.is_archived).length,
);

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

export async function loadThreads(projectId: UUID | null = null): Promise<void> {
	try {
		const results = await Commands.getThreads(projectId);
		threads.set(results);
	} catch (err) {
		console.error('Failed to load threads:', err);
	}
}

export async function createThread(options: {
	projectId: UUID;
	provider: string;
	model?: string;
	effort?: string;
	runtimeMode?: string;
	fastMode?: boolean;
	title?: string;
}): Promise<ChatThread> {
	try {
		const thread = await Commands.createThread(
			options.projectId,
			options.provider,
			options.model ?? null,
			options.effort ?? null,
			options.runtimeMode ?? 'stdin',
			options.fastMode ?? false,
		);
		threads.update((list) => [thread, ...list]);
		selectedThreadId.set(thread.id);
		return thread;
	} catch (err) {
		console.error('Failed to create thread:', err);
		throw err;
	}
}

export async function removeThread(threadId: string): Promise<void> {
	try {
		await Commands.deleteThread(threadId);
		threads.update((list) => {
			const next = list.filter((t) => t.id !== threadId);
			return next;
		});
		if ($selectedThreadId === threadId) {
			selectedThreadId.set(null);
		}
	} catch (err) {
		console.error('Failed to delete thread:', err);
		throw err;
	}
}

export function selectThread(threadId: string | null): void {
	selectedThreadId.set(threadId);
}

export function setSearchQuery(query: string): void {
	searchQuery.set(query);
}

export function toggleArchive(threadId: string): void {
	threads.update((list) =>
		list.map((t) =>
			t.id === threadId ? { ...t, is_archived: !t.is_archived } : t,
		),
	);
}

export function pinThread(threadId: string): void {
	threads.update((list) =>
		list.map((t) =>
			t.id === threadId ? { ...t, is_pinned: !t.is_pinned } : t,
		),
	);
}

export function setActiveProject(projectId: string | null): void {
	activeProjectId.set(projectId);
	if (projectId) {
		loadThreads(projectId);
	}
}

export function setSidebarWidth(width: number): void {
	const clamped = Math.max(200, Math.min(400, width));
	sidebarWidth.set(clamped);
}

export async function loadProjects(): Promise<void> {
	try {
		const projectList = await Commands.getProjects();
		projects.set(projectList);
	} catch (err) {
		console.error('Failed to load projects:', err);
	}
}
