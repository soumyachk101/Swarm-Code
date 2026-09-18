// =============================================================================
// SwarmAI Tauri Frontend — Complete Type Definitions
// Mirrors the Rust backend models in src-tauri/src/models/
// =============================================================================

// ---------------------------------------------------------------------------
// Primitives
// ---------------------------------------------------------------------------
export type UUID = string;

// ---------------------------------------------------------------------------
// Provider types
// ---------------------------------------------------------------------------
export enum ProviderKind {
	Codex = 'codex',
	Claude = 'claude',
	Cursor = 'cursor',
	Opencode = 'opencode',
	Grok = 'grok',
	Deepseek = 'deepseek',
	Meta = 'meta',
	Devin = 'devin',
	Antigravity = 'antigravity',
	Copilot = 'copilot',
}

export const PROVIDER_LABELS: Record<ProviderKind, string> = {
	[ProviderKind.Codex]: 'Codex',
	[ProviderKind.Claude]: 'Claude',
	[ProviderKind.Cursor]: 'Cursor',
	[ProviderKind.Opencode]: 'OpenCode',
	[ProviderKind.Grok]: 'Grok',
	[ProviderKind.Deepseek]: 'DeepSeek',
	[ProviderKind.Meta]: 'Meta',
	[ProviderKind.Devin]: 'Devin',
	[ProviderKind.Antigravity]: 'Antigravity',
	[ProviderKind.Copilot]: 'Copilot',
};

export enum ProviderType {
	Cli = 'cli',
	ApiKey = 'api_key',
	Acp = 'acp',
	Native = 'native',
}

export interface ProviderStatus {
	provider: ProviderKind;
	is_installed: boolean;
	is_authenticated: boolean;
	version: string | null;
	last_checked: string | null;
	error: string | null;
}

export interface Provider {
	id: UUID;
	provider_type: ProviderType;
	kind: ProviderKind;
	name: string;
	api_key: string | null;
	base_url: string | null;
	executable_path: string | null;
	models: ModelInfo[];
	default_model_id: string | null;
	enabled: boolean;
	is_default: boolean;
	installed: boolean;
	authenticated: boolean;
	version: string | null;
	status_message: string | null;
	created_at: string;
	updated_at: string;
	last_tested_at: string | null;
}

export interface ModelInfo {
	id: string;
	name: string;
	detail: string | null;
	efforts: string[];
	default_effort: string | null;
	is_default: boolean;
	fast_tier: string | null;
}

export interface ModelPin {
	provider: ProviderKind;
	model_id: string;
}

export interface ProviderCredits {
	provider_id: string;
	remaining: number | null;
	unit: string | null;
	resets_at: string | null;
	is_unlimited: boolean;
}

export interface ProviderTestResult {
	success: boolean;
	message: string;
	models: ModelInfo[];
	response_time_ms: number | null;
}

export enum RuntimeMode {
	Supervised = 'supervised',
	AutoAcceptEdits = 'auto_accept_edits',
	Auto = 'auto',
	FullAccess = 'full_access',
}

export const RUNTIME_MODE_TITLES: Record<RuntimeMode, string> = {
	[RuntimeMode.Supervised]: 'Supervised',
	[RuntimeMode.AutoAcceptEdits]: 'Auto-accept edits',
	[RuntimeMode.Auto]: 'Auto',
	[RuntimeMode.FullAccess]: 'Full access',
};

export const RUNTIME_MODE_SUMMARIES: Record<RuntimeMode, string> = {
	[RuntimeMode.Supervised]: 'Asks before commands and file changes',
	[RuntimeMode.AutoAcceptEdits]: 'Edits files freely, asks before other actions',
	[RuntimeMode.Auto]: 'The provider\'s reviewer approves routine actions',
	[RuntimeMode.FullAccess]: 'Runs commands and edits without asking',
};

export enum InteractionMode {
	Build = 'build',
	Plan = 'plan',
}

export enum WorkspaceMode {
	Local = 'local',
	Worktree = 'worktree',
}

// ---------------------------------------------------------------------------
// Thread types
// ---------------------------------------------------------------------------
export enum ThreadStatus {
	Idle = 'idle',
	Running = 'running',
	Paused = 'paused',
	Completed = 'completed',
	Failed = 'failed',
	Cancelled = 'cancelled',
}

export interface ChatThread {
	id: UUID;
	project_id: UUID;
	title: string;
	created_at: string;
	updated_at: string;
	provider: ProviderKind;
	model: string | null;
	effort: string | null;
	fast_mode: boolean;
	runtime_mode: RuntimeMode;
	interaction_mode: InteractionMode;
	worktree_path: string | null;
	branch: string | null;
	provider_session_id: string | null;
	is_pinned: boolean;
	is_archived: boolean;
	is_settled: boolean;
	settled_at: string | null;
	has_unread: boolean;
	has_custom_title: boolean;
	sort_order: number | null;
	activity_order: number | null;
	activity_order_day: string | null;
	last_status: string | null;
	parent_thread_id: UUID | null;
	is_in_panel: boolean;
	folds_helpers: boolean;
	hydra_enabled: boolean;
	hydra_pair_id: UUID | null;
	hydra_spawn_count: number;
	hydra: HydraHeadInfo | null;
}

export interface ThreadSummary {
	id: UUID;
	name: string;
	project_id: UUID | null;
	provider: ProviderKind;
	model: string | null;
	status: ThreadStatus;
	created_at: string;
	updated_at: string;
}

export interface ThreadDocument {
	thread_id: UUID;
	items: TimelineItem[];
	turns: TurnRecord[];
	usage: ContextUsage | null;
	follow_ups: FollowUpPrompt[];
}

// ---------------------------------------------------------------------------
// Timeline / Message types
// ---------------------------------------------------------------------------
export type TimelineContent =
	| { type: 'user'; value: UserMessage }
	| { type: 'assistant'; value: AssistantMessage }
	| { type: 'reasoning'; value: ReasoningBlock }
	| { type: 'tool'; value: ToolCall }
	| { type: 'plan'; value: ProposedPlan }
	| { type: 'todos'; value: TodoStep[] }
	| { type: 'notice'; value: Notice }
	| { type: 'turn_end'; value: TurnSummary };

export interface TimelineItem {
	id: string;
	turn_id: UUID | null;
	date: string;
	content: TimelineContent;
}

export interface UserMessage {
	text: string;
	attachments: Attachment[];
	hydra_heads: number[] | null;
}

export interface Attachment {
	id: UUID;
	name: string;
	path: string;
	mime_type: string;
}

export interface AssistantMessage {
	text: string;
	is_streaming: boolean;
}

export interface ReasoningBlock {
	text: string;
	is_streaming: boolean;
}

export enum ToolKind {
	Command = 'command',
	Read = 'read',
	Edit = 'edit',
	Search = 'search',
	Web = 'web',
	Mcp = 'mcp',
	Agent = 'agent',
	Other = 'other',
}

export enum ToolStatus {
	Running = 'running',
	Completed = 'completed',
	Failed = 'failed',
	Declined = 'declined',
}

export interface FileEdit {
	path: string;
	diff: string | null;
	additions: number;
	deletions: number;
}

export interface ToolCall {
	kind: ToolKind;
	title: string;
	detail: string | null;
	output: string;
	status: ToolStatus;
	exit_code: number | null;
	edits: FileEdit[];
	started_at: string;
	finished_at: string | null;
}

export enum PlanState {
	Drafting = 'drafting',
	Proposed = 'proposed',
	Accepted = 'accepted',
	Dismissed = 'dismissed',
}

export interface ProposedPlan {
	markdown: string;
	state: PlanState;
}

export enum TodoStatus {
	Pending = 'pending',
	Active = 'active',
	Done = 'done',
}

export interface TodoStep {
	text: string;
	status: TodoStatus;
}

export enum NoticeLevel {
	Info = 'info',
	Warning = 'warning',
	Error = 'error',
}

export interface Notice {
	level: NoticeLevel;
	message: string;
}

export enum TurnStatus {
	Running = 'running',
	Completed = 'completed',
	Interrupted = 'interrupted',
	Failed = 'failed',
}

export interface TurnSummary {
	turn_id: UUID;
	status: TurnStatus;
	duration: number;
	files_changed: number;
	additions: number;
	deletions: number;
}

export interface TurnRecord {
	id: UUID;
	index: number;
	provider_turn_id: string | null;
	started_at: string;
	completed_at: string | null;
	status: TurnStatus;
	base_checkpoint: string | null;
	end_checkpoint: string | null;
	user_item_id: string | null;
	provider_diff: string | null;
	provider_anchor: string | null;
	touched_paths: string[] | null;
	hydra_merged: boolean;
}

export interface ContextUsage {
	used_tokens: number;
	window_tokens: number | null;
}

export interface FollowUpPrompt {
	id: UUID;
	text: string;
	attachments: Attachment[];
	created_at: string;
}

export interface TranscriptMessage {
	role: string;
	content: string;
	timestamp: string;
}

export interface ThreadDocumentSection {
	title: string;
	markdown: string;
	items: TimelineItem[];
}

// Streaming
export type ChunkContent =
	| { type: 'text'; delta: string }
	| { type: 'reasoning'; delta: string }
	| { type: 'tool_start'; id: string; kind: string; title: string }
	| { type: 'tool_output'; id: string; delta: string }
	| { type: 'tool_complete'; id: string; status: string }
	| { type: 'plan_draft'; markdown: string }
	| { type: 'notice'; level: string; message: string }
	| { type: 'turn_end'; turn_id: UUID };

export interface MessageChunk {
	thread_id: UUID;
	content: ChunkContent;
	timestamp: string;
}

export interface MessageOptions {
	effort: string | null;
	fast_mode: boolean;
	interaction_mode: string | null;
	attachments: AttachmentInfo[];
	hydra_enabled: boolean;
	hydra_pair_id: UUID | null;
}

export interface AttachmentInfo {
	id: string;
	name: string;
	path: string;
	mime_type: string;
}

// ---------------------------------------------------------------------------
// Hydra types
// ---------------------------------------------------------------------------
export interface HydraPair {
	id: UUID;
	provider: ProviderKind;
	orchestrator_model: string | null;
	orchestrator_effort: string | null;
	worker_provider: ProviderKind | null;
	worker_model: string | null;
	worker_effort: string | null;
	max_heads: number | null;
	auto_merge: boolean;
	reviews_heads: boolean;
	isolates_heads: boolean;
}

export interface HydraHeadInfo {
	index: number;
	task: string;
	kind: HydraHeadKind;
	origin: HydraHeadOrigin;
	status: HydraHeadStatus;
	summary: string | null;
	activity: string | null;
	tool_calls: number;
	tokens: number;
	started_at: string;
	finished_at: string | null;
	native_id: string | null;
	native_task_id: string | null;
	tool_use_id: string | null;
	batch_id: UUID | null;
	can_stop: boolean;
	is_background: boolean;
	base_tree: string | null;
	landing: HydraLanding | null;
}

export enum HydraHeadKind {
	Native = 'native',
	Droppy = 'droppy',
}

export enum HydraHeadOrigin {
	Delegated = 'delegated',
	Queued = 'queued',
	Sent = 'sent',
}

export enum HydraHeadStatus {
	Running = 'running',
	Completed = 'completed',
	Failed = 'failed',
	Stopped = 'stopped',
}

export type WorkingIndicatorState =
	| 'idle'
	| 'running'
	| 'thinking'
	| 'searching'
	| 'planning'
	| 'working'
	| 'spawning'
	| 'reviewing'
	| 'writing'
	| 'done'
	| 'error';

export interface HydraLanding {
	files: HydraLandingFile[];
	conflicts: string[];
	patch_path: string | null;
	error: string | null;
}

export interface HydraLandingFile {
	path: string;
	additions: number;
	deletions: number;
}

export interface HydraDelegation {
	task: string;
	prompt: string;
	name: string | null;
}

export interface HydraReport {
	head_index: number;
	task: string;
	origin: HydraHeadOrigin;
	status: HydraHeadStatus;
	text: string;
	landing: HydraLanding | null;
	copy_path: string | null;
	elapsed: number | null;
	tool_calls: number;
}

export interface HydraLaunch {
	heads_provider: ProviderKind;
	runs_natively: boolean;
	heads_label: string | null;
	worker_model: string | null;
	worker_effort: string | null;
	max_heads: number | null;
	isolates_heads: boolean;
	auto_merges: boolean;
	reviews_heads: boolean;
}

export interface HydraPersona {
	name: string;
	asset: string;
	hex: number;
}

export const HYDRA_PERSONAS: HydraPersona[] = [
	{ name: 'Hank', asset: 'hydra-head-01', hex: 0xFF8A3D },
	{ name: 'Walter', asset: 'hydra-head-02', hex: 0x3D8BFF },
	{ name: 'Ada', asset: 'hydra-head-03', hex: 0x34C46A },
	{ name: 'Otto', asset: 'hydra-head-04', hex: 0xA35BE0 },
	{ name: 'Nova', asset: 'hydra-head-05', hex: 0xF25C9A },
	{ name: 'Remy', asset: 'hydra-head-06', hex: 0x2BB5B0 },
	{ name: 'Iris', asset: 'hydra-head-07', hex: 0xE8B430 },
	{ name: 'Milo', asset: 'hydra-head-08', hex: 0xE84F4F },
	{ name: 'Juno', asset: 'hydra-head-09', hex: 0x6A5CFF },
	{ name: 'Ezra', asset: 'hydra-head-10', hex: 0x4FD1A1 },
	{ name: 'Lena', asset: 'hydra-head-11', hex: 0x2FB8E6 },
	{ name: 'Bo', asset: 'hydra-head-12', hex: 0xB0784A },
	{ name: 'Kai', asset: 'hydra-head-13', hex: 0x8FD14F },
	{ name: 'Vera', asset: 'hydra-head-14', hex: 0xD946EF },
	{ name: 'Finn', asset: 'hydra-head-15', hex: 0xF97316 },
	{ name: 'Mira', asset: 'hydra-head-16', hex: 0xC084FC },
	{ name: 'Odin', asset: 'hydra-head-17', hex: 0xB45309 },
	{ name: 'Suki', asset: 'hydra-head-18', hex: 0xF472B6 },
	{ name: 'Rex', asset: 'hydra-head-19', hex: 0x2563EB },
	{ name: 'Zola', asset: 'hydra-head-20', hex: 0x65A30D },
];

export function hydraPersonaAt(index: number): HydraPersona {
	const personas = HYDRA_PERSONAS;
	const count = personas.length;
	const idx = (((index % count) + count) % count);
	const base = personas[idx];
	const round = Math.max(0, Math.floor(index / count));
	if (round > 0) {
		return { name: `${base.name} ${round + 1}`, asset: base.asset, hex: base.hex };
	}
	return base;
}

// ---------------------------------------------------------------------------
// Project types
// ---------------------------------------------------------------------------
export interface ProjectScript {
	id: UUID;
	name: string;
	command: string;
	symbol: string;
	run_on_worktree_create: boolean;
}

export interface Project {
	id: UUID;
	name: string;
	path: string;
	added_at: string;
	is_expanded: boolean;
	scripts: ProjectScript[];
}

// ---------------------------------------------------------------------------
// Library types
// ---------------------------------------------------------------------------
export interface Library {
	projects: Project[];
	threads: ChatThread[];
}

// ---------------------------------------------------------------------------
// Settings types
// ---------------------------------------------------------------------------
export enum AppTheme {
	System = 'system',
	Light = 'light',
	Dark = 'dark',
	CatppuccinMocha = 'catppuccin_mocha',
	CatppuccinLatte = 'catppuccin_latte',
	Dracula = 'dracula',
	TokyoNight = 'tokyo_night',
	Nord = 'nord',
	Gruvbox = 'gruvbox',
	GruvboxLight = 'gruvbox_light',
	OneDark = 'one_dark',
	Everforest = 'everforest',
	Kanagawa = 'kanagawa',
	RosePine = 'rose_pine',
	SolarizedDark = 'solarized_dark',
	SolarizedLight = 'solarized_light',
	GithubDark = 'github_dark',
	GithubLight = 'github_light',
	Ayu = 'ayu',
	NightOwl = 'night_owl',
	Monokai = 'monokai',
	Claude = 'claude',
	ClaudeLight = 'claude_light',
	Codex = 'codex',
	Cursor = 'cursor',
	Matrix = 'matrix',
}

export const THEME_DISPLAY_NAMES: Record<AppTheme, string> = {
	[AppTheme.System]: 'System',
	[AppTheme.Light]: 'Light',
	[AppTheme.Dark]: 'Dark',
	[AppTheme.CatppuccinMocha]: 'Catppuccin Mocha',
	[AppTheme.CatppuccinLatte]: 'Catppuccin Latte',
	[AppTheme.Dracula]: 'Dracula',
	[AppTheme.TokyoNight]: 'Tokyo Night',
	[AppTheme.Nord]: 'Nord',
	[AppTheme.Gruvbox]: 'Gruvbox',
	[AppTheme.GruvboxLight]: 'Gruvbox Light',
	[AppTheme.OneDark]: 'One Dark',
	[AppTheme.Everforest]: 'Everforest',
	[AppTheme.Kanagawa]: 'Kanagawa',
	[AppTheme.RosePine]: 'Rosé Pine',
	[AppTheme.SolarizedDark]: 'Solarized Dark',
	[AppTheme.SolarizedLight]: 'Solarized Light',
	[AppTheme.GithubDark]: 'GitHub Dark',
	[AppTheme.GithubLight]: 'GitHub Light',
	[AppTheme.Ayu]: 'Ayu',
	[AppTheme.NightOwl]: 'Night Owl',
	[AppTheme.Monokai]: 'Monokai',
	[AppTheme.Claude]: 'Claude',
	[AppTheme.ClaudeLight]: 'Claude Light',
	[AppTheme.Codex]: 'Codex',
	[AppTheme.Cursor]: 'Cursor',
	[AppTheme.Matrix]: 'Matrix',
};

export interface ThemeSpec {
	scheme: 'light' | 'dark' | null;
	accent: string | null;
	surface: string;
	success: string;
	warning: string;
	danger: string;
}

export interface AppSettings {
	theme: AppTheme;
	theme_mode: 'system' | 'light' | 'dark';
	font_size: number;
	font_family: string;
	sidebar_width: number;
	show_timeline: boolean;
	show_usage: boolean;
	auto_scroll: boolean;
	streaming: boolean;
	sound_enabled: boolean;
	notification_enabled: boolean;
	default_provider: ProviderKind | null;
	default_model: string | null;
	default_effort: string | null;
	default_runtime_mode: RuntimeMode;
	pinned_models: ModelPin[];
	shortcuts: Shortcut[];
	recent_threads: UUID[];
	editor_path: string | null;
	terminal_shell: string;
	terminal_rows: number;
	terminal_cols: number;
	hydra_max_heads: number;
	hydra_auto_merge: boolean;
	hydra_reviews_heads: boolean;
	hydra_isolates_heads: boolean;
	hydra_queue_heads: boolean;
	hydra_always_heads: boolean;
	hydra_enabled: boolean;
	hydra_auto_clear_finished: boolean;
	hydra_pairs: HydraPair[];
	hydra_pair_id: UUID | null;
	hydra_head_count: number;
	notify_when_finished: boolean;
	chime_when_finished: string;
	confirm_before_deleting: boolean;
	auto_continue_after_limit: boolean;
	thread_finish_action: 'settle' | 'archive';
	settle_sound: string;
	show_reasoning: boolean;
	chat_zoom: number;
	sidebar_activity_view: boolean;
	app_theme: AppTheme;
	backdrop_opacity: number;
	binary_paths: Record<string, string>;
	disabled_providers: ProviderKind[];
	model_list: ModelInfo[];
	model_preferences: Record<string, { effort?: string; fastMode?: boolean }>;
	last_project_id: UUID | null;
	last_effort: Record<ProviderKind, string>;
	default_workspace_mode: string;
}

export interface Shortcut {
	action: string;
	key: string;
	modifiers: string[];
	display: string;
}

// ---------------------------------------------------------------------------
// Git types
// ---------------------------------------------------------------------------
export enum DiffChangeType {
	Added = 'added',
	Modified = 'modified',
	Deleted = 'deleted',
	Renamed = 'renamed',
	Copied = 'copied',
}

export interface GitStatus {
	branch: string | null;
	upstream: string | null;
	ahead: number;
	behind: number;
	modified: string[];
	added: string[];
	deleted: string[];
	renamed: string[];
	untracked: string[];
	staged: string[];
	is_repo: boolean;
}

export interface DiffEntry {
	path: string;
	old_path: string | null;
	change_type: DiffChangeType;
	additions: number;
	deletions: number;
	diff: string | null;
	is_staged: boolean;
}

export interface GitCommit {
	hash: string;
	short_hash: string;
	author: string;
	email: string;
	date: string;
	message: string;
}

export interface GitBlame {
	line: number;
	commit_hash: string;
	author: string;
	date: string;
	summary: string;
}

// ---------------------------------------------------------------------------
// Terminal types
// ---------------------------------------------------------------------------
export interface TerminalSession {
	id: UUID;
	thread_id: UUID;
	directory: string;
	title: string;
	is_running: boolean;
	cols: number;
	rows: number;
}

export enum TerminalStream {
	Stdout = 'stdout',
	Stderr = 'stderr',
	System = 'system',
}

// ---------------------------------------------------------------------------
// Filesystem types
// ---------------------------------------------------------------------------
export interface DirEntry {
	name: string;
	path: string;
	is_directory: boolean;
	size: number | null;
	modified: string | null;
	extension: string | null;
}

export interface FilePreview {
	path: string;
	name: string;
	extension: string;
	size: number;
	lines: number;
	preview: string;
	is_text: boolean;
}

// ---------------------------------------------------------------------------
// Approval / Question types
// ---------------------------------------------------------------------------
export enum ApprovalKind {
	Command = 'command',
	FileChange = 'file_change',
	Tool = 'tool',
	Permissions = 'permissions',
	Plan = 'plan',
}

export enum ApprovalRole {
	Approve = 'approve',
	ApproveAlways = 'approve_always',
	Decline = 'decline',
	Cancel = 'cancel',
}

export interface ApprovalOption {
	id: string;
	title: string;
	role: ApprovalRole;
}

export interface ApprovalRequest {
	id: string;
	kind: ApprovalKind;
	title: string;
	detail: string | null;
	reason: string | null;
	options: ApprovalOption[];
	tool_item_id: string | null;
}

export interface QuestionRequest {
	id: string;
	questions: Question[];
}

export interface Question {
	id: string;
	header: string;
	prompt: string;
	choices: QuestionChoice[];
	allows_multiple: boolean;
	allows_other: boolean;
	is_secret: boolean;
}

export interface QuestionChoice {
	label: string;
	detail: string | null;
}

// ---------------------------------------------------------------------------
// Merge types
// ---------------------------------------------------------------------------
export enum Forge {
	Github = 'github',
	Gitlab = 'gitlab',
	Gitea = 'gitea',
}

export interface MergeRequestLink {
	url: string;
	forge: Forge;
	number: number;
}

// ---------------------------------------------------------------------------
// UI Helpers
// ---------------------------------------------------------------------------
export type ViewKind = 'chat' | 'settings' | 'about' | 'settings_providers' | 'settings_hydra';

export interface SidebarFilter {
	search: string;
	showPinnedOnly: boolean;
	showArchived: boolean;
	activeProvider: ProviderKind | null;
}

export function isHydraRunning(thread: ChatThread): boolean {
	return thread.hydra_enabled && thread.status === 'running';
}

export function formatRelativeTime(dateStr: string): string {
	const date = new Date(dateStr);
	const now = new Date();
	const diffMs = now.getTime() - date.getTime();
	const diffSec = Math.floor(diffMs / 1000);
	if (diffSec < 60) return 'just now';
	const diffMin = Math.floor(diffSec / 60);
	if (diffMin < 60) return `${diffMin}m ago`;
	const diffHr = Math.floor(diffMin / 60);
	if (diffHr < 24) return `${diffHr}h ago`;
	const diffDay = Math.floor(diffHr / 24);
	if (diffDay < 7) return `${diffDay}d ago`;
	return date.toLocaleDateString();
}

export function truncateText(text: string, maxLen: number): string {
	if (text.length <= maxLen) return text;
	return text.slice(0, maxLen - 1) + '…';
}
