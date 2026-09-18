// =============================================================================
// Swarm Code Tauri Frontend — Tauri Command Wrappers
// All backend commands organized by domain
// =============================================================================

import { invoke } from '@tauri-apps/api/core';
import type {
	Project,
	ProjectScript,
	ChatThread,
	ThreadSummary,
	ThreadDocument,
	Provider,
	ProviderStatus,
	ModelInfo,
	ProviderTestResult,
	ProviderCredits,
	ModelPin,
	AppSettings,
	Shortcut,
	AttachmentInfo,
	MessageOptions,
	MessageChunk,
	GitStatus,
	DiffEntry,
	GitCommit,
	GitBlame,
	TerminalSession,
	DirEntry,
	FilePreview,
	HydraPair,
	HydraHeadInfo,
	HydraReport,
	HydraLaunch,
	Library,
	FollowUpPrompt,
	ProviderKind,
	UUID,
	ApprovalRequest,
	QuestionRequest,
	MergeRequestLink,
	ContextUsage,
} from '$lib/types';

// =============================================================================
// Projects
// =============================================================================

export async function getProjects(): Promise<Project[]> {
	return invoke<Project[]>('get_projects');
}

export async function addProject(name: string, path: string): Promise<Project> {
	return invoke<Project>('add_project', { name, path });
}

export async function deleteProject(projectId: UUID): Promise<void> {
	return invoke<void>('delete_project', { projectId });
}

// =============================================================================
// Threads
// =============================================================================

export async function getThreads(projectId: UUID | null): Promise<ChatThread[]> {
	return invoke<ChatThread[]>('get_threads', { projectId });
}

export async function createThread(
	projectId: UUID,
	provider: ProviderKind,
	model: string | null,
	effort: string | null,
	runtimeMode: string,
	fastMode: boolean,
): Promise<ChatThread> {
	return invoke<ChatThread>('create_thread', {
		projectId,
		provider,
		model,
		effort,
		runtimeMode,
		fastMode,
	});
}

export async function deleteThread(threadId: UUID): Promise<void> {
	return invoke<void>('delete_thread', { threadId });
}

export async function getThread(threadId: UUID): Promise<ChatThread> {
	return invoke<ChatThread>('get_thread', { threadId });
}

export async function getRecentThreads(limit: number = 20): Promise<ThreadSummary[]> {
	return invoke<ThreadSummary[]>('get_recent_threads', { limit });
}

export async function getThreadDocument(threadId: UUID): Promise<ThreadDocument> {
	return invoke<ThreadDocument>('get_thread_document', { threadId });
}

export async function getThreadUsage(threadId: UUID): Promise<ContextUsage | null> {
	return invoke<ContextUsage | null>('get_thread_usage', { threadId });
}

// =============================================================================
// Messages
// =============================================================================

export async function sendMessage(
	threadId: UUID,
	text: string,
	options: Partial<MessageOptions> = {},
): Promise<MessageChunk> {
	return invoke<MessageChunk>('send_message', {
		threadId,
		text,
		options: {
			effort: options.effort ?? null,
			fast_mode: options.fast_mode ?? false,
			interaction_mode: options.interaction_mode ?? null,
			attachments: options.attachments ?? [],
			hydra_enabled: options.hydra_enabled ?? false,
			hydra_pair_id: options.hydra_pair_id ?? null,
		},
	});
}

export async function getMessages(threadId: UUID, limit?: number): Promise<MessageChunk[]> {
	return invoke<MessageChunk[]>('get_messages', { threadId, limit });
}

export async function deleteMessage(threadId: UUID, messageId: string): Promise<void> {
	return invoke<void>('delete_message', { threadId, messageId });
}

export async function sendFollowUp(
	threadId: UUID,
	text: string,
	attachments: AttachmentInfo[] = [],
): Promise<MessageChunk> {
	return invoke<MessageChunk>('send_follow_up', { threadId, text, attachments });
}

export async function approveRequest(
	threadId: UUID,
	requestId: string,
	role: string,
): Promise<void> {
	return invoke<void>('approve_request', { threadId, requestId, role });
}

export async function answerQuestion(
	threadId: UUID,
	questionId: string,
	answers: string[],
): Promise<void> {
	return invoke<void>('answer_question', { threadId, questionId, answers });
}

// =============================================================================
// Providers
// =============================================================================

export async function getProviders(): Promise<Provider[]> {
	return invoke<Provider[]>('get_providers');
}

export async function getModelsForProvider(providerId: UUID): Promise<ModelInfo[]> {
	return invoke<ModelInfo[]>('get_models_for_provider', { providerId });
}

export async function getAvailableModels(): Promise<ModelInfo[]> {
	return invoke<ModelInfo[]>('get_available_models');
}

export async function saveProvider(provider: Partial<Provider>): Promise<Provider> {
	return invoke<Provider>('save_provider', { provider });
}

export async function deleteProvider(providerId: UUID): Promise<void> {
	return invoke<void>('delete_provider', { providerId });
}

export async function testProvider(providerId: UUID): Promise<ProviderTestResult> {
	return invoke<ProviderTestResult>('test_provider', { providerId });
}

export async function getProviderCredits(providerId: UUID): Promise<ProviderCredits> {
	return invoke<ProviderCredits>('get_provider_credits', { providerId });
}

export async function refreshProviderStatus(providerId: UUID): Promise<ProviderStatus> {
	return invoke<ProviderStatus>('refresh_provider_status', { providerId });
}

// =============================================================================
// Hydra
// =============================================================================

export async function createHydra(
	projectId: UUID,
	config: Partial<HydraPair>,
): Promise<HydraPair> {
	return invoke<HydraPair>('create_hydra', { projectId, config });
}

export async function getHydra(hydraId: UUID): Promise<HydraPair> {
	return invoke<HydraPair>('get_hydra', { hydraId });
}

export async function getHydras(projectId: UUID | null): Promise<HydraPair[]> {
	return invoke<HydraPair[]>('get_hydras', { projectId });
}

export async function deleteHydra(hydraId: UUID): Promise<void> {
	return invoke<void>('delete_hydra', { hydraId });
}

export async function launchHydraRun(
	hydraId: UUID,
	task: string,
	config: Partial<HydraLaunch>,
): Promise<HydraHeadInfo> {
	return invoke<HydraHeadInfo>('launch_hydra_run', { hydraId, task, config });
}

export async function stopHydraHead(headId: UUID): Promise<void> {
	return invoke<void>('stop_hydra_head', { headId });
}

export async function landHydraHead(headId: UUID): Promise<HydraReport> {
	return invoke<HydraReport>('land_hydra_head', { headId });
}

// =============================================================================
// Settings
// =============================================================================

export async function getSettings(): Promise<AppSettings> {
	return invoke<AppSettings>('get_settings');
}

export async function updateSettings(settings: Partial<AppSettings>): Promise<AppSettings> {
	return invoke<AppSettings>('update_settings', { settings });
}

export async function resetSettings(): Promise<AppSettings> {
	return invoke<AppSettings>('reset_settings');
}

// =============================================================================
// Library
// =============================================================================

export async function getLibraryItems(): Promise<Library> {
	return invoke<Library>('get_library_items');
}

export async function saveLibraryItem(item: Partial<Project>): Promise<Project> {
	return invoke<Project>('save_library_item', { item });
}

export async function deleteLibraryItem(itemId: UUID): Promise<void> {
	return invoke<void>('delete_library_item', { itemId });
}

// =============================================================================
// Filesystem
// =============================================================================

export async function getFilePreview(path: string): Promise<FilePreview> {
	return invoke<FilePreview>('get_file_preview', { path });
}

export async function readFile(path: string): Promise<string> {
	return invoke<string>('read_file', { path });
}

export async function listDirectory(path: string): Promise<DirEntry[]> {
	return invoke<DirEntry[]>('list_directory', { path });
}

export async function openInEditor(path: string, line?: number): Promise<void> {
	return invoke<void>('open_in_editor', { path, line });
}

// =============================================================================
// Git
// =============================================================================

export async function getGitStatus(projectPath: string): Promise<GitStatus> {
	return invoke<GitStatus>('get_git_status', { projectPath });
}

export async function getTouchedPaths(projectPath: string): Promise<string[]> {
	return invoke<string[]>('get_touched_paths', { projectPath });
}

export async function getDiff(paths: string[]): Promise<DiffEntry[]> {
	return invoke<DiffEntry[]>('get_diff', { paths });
}

export async function getCommitLog(
	projectPath: string,
	limit: number = 20,
): Promise<GitCommit[]> {
	return invoke<GitCommit[]>('get_commit_log', { projectPath, limit });
}

export async function gitBlame(path: string, line: number): Promise<GitBlame> {
	return invoke<GitBlame>('git_blame', { path, line });
}

export async function gitCommit(
	projectPath: string,
	message: string,
	paths: string[] = [],
): Promise<string> {
	return invoke<string>('git_commit', { projectPath, message, paths });
}

export async function gitStage(projectPath: string, paths: string[]): Promise<void> {
	return invoke<void>('git_stage', { projectPath, paths });
}

export async function gitPush(projectPath: string): Promise<void> {
	return invoke<void>('git_push', { projectPath });
}

// =============================================================================
// Terminal
// =============================================================================

export async function createTerminalSession(
	threadId: UUID,
	directory: string,
	rows: number = 24,
	cols: number = 80,
): Promise<TerminalSession> {
	return invoke<TerminalSession>('create_terminal_session', {
		threadId,
		directory,
		rows,
		cols,
	});
}

export async function sendTerminalInput(
	sessionId: UUID,
	input: string,
): Promise<void> {
	return invoke<void>('send_terminal_input', { sessionId, input });
}

export async function resizeTerminal(
	sessionId: UUID,
	rows: number,
	cols: number,
): Promise<void> {
	return invoke<void>('resize_terminal', { sessionId, rows, cols });
}

export async function closeTerminal(sessionId: UUID): Promise<void> {
	return invoke<void>('close_terminal', { sessionId });
}

// =============================================================================
// Shortcuts
// =============================================================================

export async function getRegisteredShortcuts(): Promise<Shortcut[]> {
	return invoke<Shortcut[]>('get_registered_shortcuts');
}

export async function registerShortcut(shortcut: Partial<Shortcut>): Promise<Shortcut> {
	return invoke<Shortcut>('register_shortcut', { shortcut });
}

export async function unregisterShortcut(action: string): Promise<void> {
	return invoke<void>('unregister_shortcut', { action });
}

// =============================================================================
// Misc
// =============================================================================

export async function openMergeLink(link: Partial<MergeRequestLink>): Promise<void> {
	return invoke<void>('open_merge_link', { link });
}

export async function showToast(message: string): Promise<void> {
	return invoke<void>('show_toast', { message });
}

export async function openUrl(url: string): Promise<void> {
	return invoke<void>('open_url', { url });
}
