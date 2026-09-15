// ---------------------------------------------------------------------------
// hydraStore – Svelte 5 $state-based store for Hydra multi-head run state
// Matches the Hydra runtime model from the Swift source.
// ---------------------------------------------------------------------------

import type { UUID, ProviderKind } from '$lib/types';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface HydraHead {
	id: UUID;
	name: string;
	provider: ProviderKind;
	status: 'idle' | 'thinking' | 'streaming' | 'completed' | 'error' | 'waiting';
	output: string;
	error: string | null;
	startedAt: string | null;
	finishedAt: string | null;
}

export interface HydraRun {
	id: UUID;
	headCount: number;
	heads: HydraHead[];
	status: 'idle' | 'running' | 'completed' | 'cancelled';
	prompt: string;
	createdAt: string;
	finishedAt: string | null;
}

export interface HydraConfig {
	headCount: number;
	providers: ProviderKind[];
	autoStart: boolean;
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

export const hydraStore = {
	// Active hydra run
	activeRun: null as HydraRun | null,

	// Previous runs (history)
	history: [] as HydraRun[],

	// Current configuration
	config: {
		headCount: 3,
		providers: [
			ProviderKind.Claude,
			ProviderKind.Codex,
			ProviderKind.Grok,
		] as ProviderKind[],
		autoStart: false,
	} as HydraConfig,

	// UI state
	isPanelOpen: false,
	headSelectorOpen: false,

	// ---------------------------------------------------------------------------
	// Getters
	// ---------------------------------------------------------------------------

	isRunning(): boolean {
		return this.activeRun !== null && this.activeRun.status === 'running';
	},

	getRunningHeads(): HydraHead[] {
		return this.activeRun?.heads.filter((h) => h.status !== 'idle' && h.status !== 'completed' && h.status !== 'waiting') ?? [];
	},

	getCompletedHeads(): HydraHead[] {
		return this.activeRun?.heads.filter((h) => h.status === 'completed') ?? [];
	},

	getErrorHeads(): HydraHead[] {
		return this.activeRun?.heads.filter((h) => h.status === 'error') ?? [];
	},

	// ---------------------------------------------------------------------------
	// Actions
	// ---------------------------------------------------------------------------

	startRun(prompt: string, headCount?: number, providers?: ProviderKind[]): UUID {
		if (this.isRunning()) {
			throw new Error('A Hydra run is already in progress');
		}

		const id = crypto.randomUUID();
		const count = headCount ?? this.config.headCount;
		const activeProviders = providers ?? this.config.providers;

		const heads: HydraHead[] = [];
		for (let i = 0; i < count; i++) {
			const provider = activeProviders[i % activeProviders.length];
			heads.push({
				id: crypto.randomUUID(),
				name: `Head ${i + 1}`,
				provider,
				status: 'waiting',
				output: '',
				error: null,
				startedAt: null,
				finishedAt: null,
			});
		}

		this.activeRun = {
			id,
			headCount: count,
			heads,
			status: 'running',
			prompt,
			createdAt: new Date().toISOString(),
			finishedAt: null,
		};

		// Start heads sequentially with a stagger
		for (let i = 0; i < heads.length; i++) {
			this.delay(200 * i).then(() => {
				this.startHead(heads[i].id);
			});
		}

		return id;
	},

	startHead(headId: UUID): void {
		if (!this.activeRun) return;

		const head = this.activeRun.heads.find((h) => h.id === headId);
		if (!head || head.status !== 'waiting') return;

		head.status = 'thinking';
		head.startedAt = new Date().toISOString();

		// Simulate thinking phase then streaming
		this.delay(800 + Math.random() * 1200).then(() => {
			head.status = 'streaming';
			this.generateHeadOutput(head);
		});
	},

	generateHeadOutput(head: HydraHead): void {
		if (!this.activeRun) return;

		// Simulate streaming output character by character
		const sampleOutputs: Record<ProviderKind, string> = {
			[ProviderKind.Codex]: 'Analyzing codebase structure and dependencies...',
			[ProviderKind.Claude]: 'Based on the context, I suggest the following approach...',
			[ProviderKind.Cursor]: 'Looking at the code, here are the relevant changes needed...',
			[ProviderKind.Opencode]: 'Exploring the repository for patterns...',
			[ProviderKind.Grok]: 'Processing the request with multi-modal understanding...',
			[ProviderKind.Deepseek]: 'Deep analysis indicates several optimization paths...',
			[ProviderKind.Meta]: 'Generating recommendations based on best practices...',
			[ProviderKind.Devin]: 'Planning implementation steps...',
			[ProviderKind.Antigravity]: 'Detected potential improvements in the architecture...',
			[ProviderKind.Copilot]: 'Suggesting code completions and improvements...',
		};

		const fullText = sampleOutputs[head.provider] ?? 'Processing request...';
		let index = 0;

		const interval = setInterval(() => {
			if (!this.activeRun) {
				clearInterval(interval);
				return;
			}

			if (index < fullText.length) {
				head.output += fullText[index];
				index++;
			} else {
				clearInterval(interval);
				head.status = 'completed';
				head.finishedAt = new Date().toISOString();
				this.checkAllHeadsComplete();
			}
		}, 30);
	},

	checkAllHeadsComplete(): void {
		if (!this.activeRun) return;

		const allComplete = this.activeRun.heads.every(
			(h) => h.status === 'completed' || h.status === 'error'
		);

		if (allComplete) {
			this.activeRun.status = 'completed';
			this.activeRun.finishedAt = new Date().toISOString();

			// Move to history
			this.history.unshift({ ...this.activeRun });
			this.activeRun = null;
		}
	},

	cancelRun(): void {
		if (!this.activeRun) return;

		for (const head of this.activeRun.heads) {
			if (head.status === 'thinking' || head.status === 'streaming' || head.status === 'waiting') {
				head.status = 'error';
				head.error = 'Cancelled by user';
				head.finishedAt = new Date().toISOString();
			}
		}

		this.activeRun.status = 'cancelled';
		this.activeRun.finishedAt = new Date().toISOString();
		this.history.unshift({ ...this.activeRun });
		this.activeRun = null;
	},

	updateHeadOutput(headId: UUID, text: string): void {
		if (!this.activeRun) return;
		const head = this.activeRun.heads.find((h) => h.id === headId);
		if (head) {
			head.output = text;
		}
	},

	setHeadError(headId: UUID, error: string): void {
		if (!this.activeRun) return;
		const head = this.activeRun.heads.find((h) => h.id === headId);
		if (head) {
			head.status = 'error';
			head.error = error;
			head.finishedAt = new Date().toISOString();
			this.checkAllHeadsComplete();
		}
	},

	// ---------------------------------------------------------------------------
	// Config
	// ---------------------------------------------------------------------------

	setHeadCount(count: number): void {
		this.config.headCount = Math.max(1, Math.min(10, count));
	},

	addProvider(provider: ProviderKind): void {
		if (!this.config.providers.includes(provider)) {
			this.config.providers.push(provider);
		}
	},

	removeProvider(provider: ProviderKind): void {
		this.config.providers = this.config.providers.filter((p) => p !== provider);
	},

	toggleAutoStart(): void {
		this.config.autoStart = !this.config.autoStart;
	},

	// ---------------------------------------------------------------------------
	// UI state
	// ---------------------------------------------------------------------------

	openPanel(): void {
		this.isPanelOpen = true;
	},

	closePanel(): void {
		this.isPanelOpen = false;
	},

	togglePanel(): void {
		this.isPanelOpen = !this.isPanelOpen;
	},

	openHeadSelector(): void {
		this.headSelectorOpen = true;
	},

	closeHeadSelector(): void {
		this.headSelectorOpen = false;
	},

	// ---------------------------------------------------------------------------
	// Utility
	// ---------------------------------------------------------------------------

	clearHistory(): void {
		this.history = [];
	},

	private delay(ms: number): Promise<void> {
		return new Promise((resolve) => setTimeout(resolve, ms));
	},
};

// ---------------------------------------------------------------------------
// Svelte 5 reactive helper: wraps the store for use with $state
// ---------------------------------------------------------------------------

export function createHydraStore() {
	return hydraStore;
}
