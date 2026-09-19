<script lang="ts">
	import type { TimelineItem, AssistantMessage, ToolCall, Notice } from '$lib/types';
	import { ToolStatus, HydraHeadStatus, ProviderKind } from '$lib/types';
	import { HYDRA_PERSONAS, hydraPersonaAt } from '$lib/types';
	import { ToolPresentation } from '$lib/toolPresentation';
	import MarkdownRenderer from './MarkdownRenderer.svelte';

	// ---------------------------------------------------------------------------
	// Props
	// ---------------------------------------------------------------------------

	interface Props {
		block: {
			id: string;
			type: string;
			label: string;
			time: string;
			events: Array<{
				id: string;
				type: string;
				timestamp: string;
				description: string;
				icon: string;
				color: string;
				details?: string;
				metadata?: Record<string, unknown>;
			}>;
		};
		readonly?: boolean;
		zoom?: number;
	}

	let { block, readonly = false, zoom = 1 }: Props = $props();

	// ---------------------------------------------------------------------------
	// Helpers
	// ---------------------------------------------------------------------------

	let expanded = $state<Set<string>>(new Set());

	function toggle(id: string) {
		const next = new Set(expanded);
		next.has(id) ? next.delete(id) : next.add(id);
		expanded = next;
	}

	function eventIcon(name: string): string {
		const map: Record<string, string> = {
			message: '✉',
			bot: '⚡',
			code: '〉',
			brain: '◈',
			'list-checks': '☰',
			info: 'ℹ',
			'alert-triangle': '⚠',
			'check-circle': '✓',
			paperclip: '⤴',
			terminal: '⌨',
			cpu: '◆'
		};
		return map[name] ?? '●';
	}

	function statusBadge(status: string): { label: string; color: string } {
		switch (status) {
			case 'completed':
				return { label: 'Done', color: '#10b981' };
			case 'failed':
				return { label: 'Failed', color: '#ef4444' };
			case 'running':
				return { label: 'Running', color: '#3b82f6' };
			case 'stopped':
				return { label: 'Stopped', color: '#f59e0b' };
			default:
				return { label: status, color: '#6b7280' };
		}
	}

	function hydraBadge(headIndex: number): string {
		if (headIndex >= 0 && headIndex < HYDRA_PERSONAS.length) {
			return hydraPersonaAt(headIndex).name;
		}
		return `Head #${headIndex}`;
	}

	function getTextSize(base: number): string {
		return `${base * zoom}px`;
	}

	// ---------------------------------------------------------------------------
	// Row rendering based on block type
	// ---------------------------------------------------------------------------

	function isUserBlock(): boolean {
		return block.type === 'user' || block.type === 'message';
	}

	function isAssistantBlock(): boolean {
		return block.type === 'assistant';
	}

	function isToolBlock(): boolean {
		return block.type === 'tool';
	}

	function isPlanBlock(): boolean {
		return block.type === 'plan';
	}

	function isTodoBlock(): boolean {
		return block.type === 'todo';
	}

	function isNoticeBlock(): boolean {
		return block.type === 'notice';
	}

	function isTurnEndBlock(): boolean {
		return block.type === 'turn_end';
	}

	function isHydraBlock(): boolean {
		return block.type === 'hydra';
	}

	// Extract event data for row rendering
	function getUserEvent() {
		return block.events.find(e => e.type === 'message');
	}

	function getAssistantEvent() {
		return block.events.find(e => e.type === 'message' || e.type === 'assistant');
	}

	function getToolEvents() {
		return block.events.filter(e => e.type === 'tool_call');
	}

	function getPlanEvent() {
		return block.events.find(e => e.type === 'plan');
	}

	function getNoticeEvent() {
		return block.events.find(e => e.type === 'notice');
	}

	function getTurnEndEvent() {
		return block.events.find(e => e.type === 'turn_end');
	}

	function getHydraEvent() {
		return block.events.find(e => e.type === 'hydra_start' || e.type === 'hydra_complete');
	}
</script>

<div class="timeline-rows">
	{#if isUserBlock()}
		{@const ev = getUserEvent()}
		{#if ev}
			{@const isHydra = ev.metadata?.fromHydra as boolean || false}
			<div class="user-message-row">
				{#if ev.metadata?.attachments && (ev.metadata.attachments as any[]).length > 0}
					<div class="attachments-strip">
						{#each ev.metadata.attachments as att ((att as any).id)}
							<button class="attachment-thumb" title={(att as any).name}>
								<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
									<path d="M13 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9z"/>
									<polyline points="13 2 13 9 20 9"/>
								</svg>
								<span class="att-thumb-name">{(att as any).name}</span>
							</button>
						{/each}
					</div>
				{/if}
				{#if ev.description}
					<div class="user-bubble">
						<div class="bubble-text" style="font-size: {getTextSize(14)}">{ev.description}</div>
						<span class="bubble-time">{block.time}</span>
					</div>
				{/if}
			</div>
		{/if}

	{:else if isAssistantBlock()}
		{@const ev = getAssistantEvent()}
		{#if ev}
			<div class="assistant-message-row">
				<div class="avatar assistant-avatar">
					<img src="/icons/swarmcode-logo.svg" alt="Swarm Code" width="14" height="14" />
				</div>
				<div class="assistant-bubble">
					{#if ev.details}
						<div class="message-text" style="font-size: {getTextSize(14)}">{ev.details}</div>
					{:else if ev.description}
						<div class="message-text" style="font-size: {getTextSize(14)}">{ev.description}</div>
					{/if}
					<span class="bubble-time">{block.time}</span>
				</div>
			</div>
		{/if}

	{:else if isToolBlock()}
		{@const toolEvents = getToolEvents()}
		{#if toolEvents.length === 1}
			{@const tool = toolEvents[0]}
			<div class="tool-row">
				<div class="tool-line">
					<span class="tool-icon" style="color: {tool.color}">
						{eventIcon(tool.icon)}
					</span>
					<span class="tool-label" style="font-size: {getTextSize(13)}">{tool.description}</span>
					{#if tool.metadata?.status}
						{@const badge = statusBadge(tool.metadata.status as string)}
						<span class="tag tag-status" style="background: {badge.color}22; color: {badge.color}; border-color: {badge.color}44;">
							{badge.label}
						</span>
					{/if}
					{#if tool.metadata?.kind}
						<span class="tag tag-kind">{tool.metadata.kind}</span>
					{/if}
					<button class="expand-chevron" class:open={expanded.has(tool.id)} onclick={() => toggle(tool.id)}>
						▾
					</button>
				</div>
				{#if expanded.has(tool.id) && tool.details}
					<div class="tool-detail">
						<pre class="tool-output">{tool.details}</pre>
					</div>
				{/if}
			</div>
		{:else if toolEvents.length > 1}
			<div class="work-group">
				<button class="work-group-header" onclick={() => toggle('group-' + block.id)}>
					<span class="tool-icon">&#x2699;</span>
					<span class="tool-label" style="font-size: {getTextSize(13)}">{block.label}</span>
					<span class="expand-chevron" class:open={expanded.has('group-' + block.id)}>▾</span>
				</button>
				{#if !expanded.has('group-' + block.id)}
					<div class="work-steps">
						{#each toolEvents.slice(-2) as tool (tool.id)}
							{@const isExp = expanded.has(tool.id)}
							<div class="tool-row">
								<div class="tool-line">
									<span class="tool-icon" style="color: {tool.color}">{eventIcon(tool.icon)}</span>
									<span class="tool-label" style="font-size: {getTextSize(13)}">{tool.description}</span>
									<button class="expand-chevron" class:open={isExp} onclick={() => toggle(tool.id)}>▾</button>
								</div>
								{#if isExp && tool.details}
									<div class="tool-detail"><pre class="tool-output">{tool.details}</pre></div>
								{/if}
							</div>
						{/each}
						{#if toolEvents.length > 2}
							<button class="show-earlier" onclick={() => toggle('earlier-' + block.id)}>
								{block.events.length - 2} earlier steps
							</button>
						{/if}
					</div>
				{/if}
			</div>
		{/if}

	{:else if isPlanBlock()}
		{@const planEv = getPlanEvent()}
		{#if planEv}
			<div class="plan-card">
				<div class="plan-header">
					<span class="plan-icon">&#x2637;</span>
					<span class="plan-title" style="font-size: {getTextSize(15)}">Plan</span>
					{#if planEv.metadata?.state === 'proposed'}
						<div class="plan-actions">
							<button class="plan-btn plan-accept">Implement</button>
							<button class="plan-btn plan-dismiss">Dismiss</button>
						</div>
					{:else if planEv.metadata?.state === 'accepted'}
						<span class="plan-state-badge accepted">Approved</span>
					{:else if planEv.metadata?.state === 'dismissed'}
						<span class="plan-state-badge dismissed">Dismissed</span>
					{/if}
				</div>
				{#if planEv.details}
					<div class="plan-body">
						<MarkdownRenderer content={planEv.details} class="plan-markdown" />
					</div>
				{:else}
					<div class="plan-loading"><span class="loading-dot">.</span><span class="loading-dot">.</span><span class="loading-dot">.</span></div>
				{/if}
			</div>
		{/if}

	{:else if isTodoBlock()}
		<div class="todo-card">
			{#each block.events as ev (ev.id)}
				{@const done = ev.metadata?.done as boolean || false}
				<div class="todo-item status-{done ? 'done' : 'pending'}">
					<span class="todo-check">
						{#if done}
							<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3">
								<path d="M20 6L9 17l-5-5"/>
							</svg>
						{:else}
							<span class="todo-empty"></span>
						{/if}
					</span>
					<span class="todo-text" style="font-size: {getTextSize(13)}">{ev.description}</span>
				</div>
			{/each}
		</div>

	{:else if isNoticeBlock()}
		{@const noticeEv = getNoticeEvent()}
		{#if noticeEv}
			<div class="notice-row">
				<span class="notice-icon">ℹ</span>
				<span class="notice-text" style="font-size: {getTextSize(13)}">{noticeEv.description}</span>
			</div>
		{/if}

	{:else if isTurnEndBlock()}
		{@const turnEv = getTurnEndEvent()}
		{#if turnEv}
			<div class="turn-end-row">
				<span class="turn-end-label" style="font-size: {getTextSize(12)}">
					{turnEv.description || 'Turn complete'}
				</span>
			</div>
		{/if}

	{:else if isHydraBlock()}
		{@const hydraEv = getHydraEvent()}
		{#if hydraEv}
			<div class="hydra-row">
				<span class="hydra-icon">&#x26A1;</span>
				<span class="hydra-text" style="font-size: {getTextSize(13)}">{hydraEv.description}</span>
				{#if hydraEv.metadata?.heads}
					<div class="hydra-heads">
						{#each hydraEv.metadata.heads as head, i (i)}
							{@const persona = hydraPersonaAt(head.index ?? i)}
							<span
								class="hydra-head-tag"
								style="background: #{persona.hex.toString(16).padStart(6, '0')}22; color: #{persona.hex.toString(16).padStart(6, '0')}; border-color: #{persona.hex.toString(16).padStart(6, '0')}44;"
							>
								{persona.name}
							</span>
						{/each}
					</div>
				{/if}
			</div>
		{/if}

	{:else}
		<!-- Generic fallback: render events as before -->
		{#each block.events as event (event.id)}
			{@const isExp = expanded.has(event.id)}
			<div class="event-row" class:expanded={isExp}>
				<button class="event-header" onclick={() => toggle(event.id)} aria-expanded={isExp} type="button">
					<span class="event-icon" style="color: {event.color}">{eventIcon(event.icon)}</span>
					<span class="event-desc">{event.description}</span>
					{#if event.details}
						<span class="event-details-hint">{event.details}</span>
					{/if}
					<span class="expand-chevron" class:open={isExp}>▾</span>
				</button>
				{#if isExp && event.metadata}
					<div class="event-detail">
						{#if event.type === 'tool_call' && event.details}
							<div class="detail-section">
								<span class="detail-label">Output</span>
								<pre class="detail-pre">{event.details}</pre>
							</div>
							<div class="detail-tags">
								{#if event.metadata.kind}
									<span class="tag tag-kind">{event.metadata.kind}</span>
								{/if}
								{#if event.metadata.status}
									{@const badge = statusBadge(event.metadata.status as string)}
									<span class="tag tag-status" style="background: {badge.color}22; color: {badge.color}; border-color: {badge.color}44;">
										{badge.label}
									</span>
								{/if}
							</div>
						{/if}
					</div>
				{/if}
			</div>
		{/each}
	{/if}
</div>

<style>
	/* ===== Layout ===== */
	.timeline-rows {
		display: flex;
		flex-direction: column;
		gap: 4px;
	}

	/* ===== User Message Row ===== */
	.user-message-row {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
	}

	.attachments-strip {
		display: flex;
		flex-wrap: wrap;
		gap: 6px;
		margin-bottom: 6px;
	}

	.attachment-thumb {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		padding: 4px 8px;
		border-radius: 6px;
		border: 1px solid var(--border-subtle);
		background: var(--surface-2);
		color: var(--text-secondary);
		font-size: 11px;
		cursor: pointer;
		transition: background 0.15s;
	}

	.attachment-thumb:hover {
		background: var(--surface-3);
	}

	.att-thumb-name {
		max-width: 120px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.user-bubble {
		max-width: 75%;
		background: var(--accent-subtle, rgba(99, 102, 241, 0.1));
		border-radius: 14px 14px 4px 14px;
		padding: 10px 14px;
		position: relative;
	}

	.bubble-text {
		line-height: 1.5;
		color: var(--text-primary);
		word-break: break-word;
	}

	.bubble-time {
		display: block;
		font-size: 10px;
		color: var(--text-tertiary);
		margin-top: 4px;
		text-align: right;
	}

	/* ===== Assistant Message Row ===== */
	.assistant-message-row {
		display: flex;
		gap: 10px;
		align-items: flex-start;
	}

	.avatar {
		width: 28px;
		height: 28px;
		border-radius: 50%;
		display: flex;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
		margin-top: 2px;
	}

	.assistant-avatar {
		background: var(--surface-3);
	}

	.assistant-bubble {
		flex: 1;
		min-width: 0;
		background: var(--surface-2);
		border-radius: 14px 14px 14px 4px;
		padding: 10px 14px;
		position: relative;
	}

	.message-text {
		line-height: 1.6;
		color: var(--text-primary);
		word-break: break-word;
	}

	/* ===== Tool Row ===== */
	.tool-row {
		display: flex;
		flex-direction: column;
		gap: 4px;
	}

	.tool-line {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 5px 8px;
		border-radius: 6px;
		background: var(--surface-1);
		cursor: pointer;
		transition: background 0.15s;
	}

	.tool-line:hover {
		background: var(--surface-2);
	}

	.tool-icon {
		width: 16px;
		text-align: center;
		flex-shrink: 0;
		font-size: 12px;
	}

	.tool-label {
		flex: 1;
		min-width: 0;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
		color: var(--text-secondary);
	}

	.tool-detail {
		padding: 0 8px 8px 32px;
	}

	.tool-output {
		font-family: 'SF Mono', 'Menlo', 'Consolas', monospace;
		font-size: 11px;
		line-height: 1.5;
		background: var(--surface-0);
		border-radius: 6px;
		padding: 8px 10px;
		margin: 0;
		overflow-x: auto;
		white-space: pre-wrap;
		word-break: break-word;
		max-height: 200px;
		color: var(--text-primary);
		border: 1px solid var(--border-subtle);
	}

	/* ===== Work Group ===== */
	.work-group {
		display: flex;
		flex-direction: column;
		gap: 2px;
	}

	.work-group-header {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 5px 8px;
		border: none;
		background: transparent;
		color: var(--text-secondary);
		font-size: 13px;
		cursor: pointer;
		border-radius: 6px;
		transition: background 0.15s;
		font-family: inherit;
	}

	.work-group-header:hover {
		background: var(--surface-2);
	}

	.work-steps {
		display: flex;
		flex-direction: column;
		gap: 2px;
		padding-left: 8px;
	}

	.show-earlier {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		padding: 4px 8px;
		border: none;
		background: transparent;
		color: var(--text-tertiary);
		font-size: 12px;
		cursor: pointer;
		border-radius: 4px;
		font-family: inherit;
	}

	.show-earlier:hover {
		background: var(--surface-2);
		color: var(--text-secondary);
	}

	/* ===== Tags ===== */
	.tag {
		font-size: 10px;
		font-family: 'SF Mono', monospace;
		padding: 2px 6px;
		border-radius: 4px;
		border: 1px solid var(--border-subtle);
		background: var(--surface-1);
		color: var(--text-tertiary);
		text-transform: capitalize;
		white-space: nowrap;
	}

	.tag-kind {
		font-weight: 500;
	}

	.tag-status {
		font-weight: 600;
		text-transform: uppercase;
	}

	.expand-chevron {
		font-size: 10px;
		color: var(--text-tertiary);
		transition: transform 160ms ease;
		flex-shrink: 0;
		background: none;
		border: none;
		cursor: pointer;
		padding: 0;
	}

	.expand-chevron.open {
		transform: rotate(180deg);
	}

	/* ===== Plan Card ===== */
	.plan-card {
		background: var(--accent-subtle, rgba(99, 102, 241, 0.06));
		border: 1px solid var(--accent-border, rgba(99, 102, 241, 0.15));
		border-radius: 14px;
		padding: 14px;
		max-width: 100%;
	}

	.plan-header {
		display: flex;
		align-items: center;
		gap: 8px;
		margin-bottom: 8px;
	}

	.plan-icon {
		font-size: 16px;
	}

	.plan-title {
		font-weight: 600;
		color: var(--text-primary);
	}

	.plan-actions {
		display: flex;
		gap: 6px;
		margin-left: auto;
	}

	.plan-btn {
		padding: 4px 12px;
		border-radius: 8px;
		border: none;
		font-size: 12px;
		font-weight: 500;
		cursor: pointer;
		font-family: inherit;
		transition: opacity 0.15s;
	}

	.plan-btn:hover {
		opacity: 0.85;
	}

	.plan-accept {
		background: var(--accent);
		color: white;
	}

	.plan-dismiss {
		background: var(--surface-3);
		color: var(--text-secondary);
	}

	.plan-state-badge {
		font-size: 11px;
		padding: 2px 8px;
		border-radius: 6px;
		font-weight: 500;
	}

	.plan-state-badge.accepted {
		background: #10b98122;
		color: #10b981;
	}

	.plan-state-badge.dismissed {
		background: #ef444422;
		color: #ef4444;
	}

	.plan-body {
		color: var(--text-primary);
		line-height: 1.6;
	}

	.plan-body :global(.message-markdown) {
		font-size: 14px;
	}

	.plan-loading {
		display: flex;
		gap: 2px;
		padding: 8px 0;
	}

	.loading-dot {
		animation: loadPulse 1.2s ease-in-out infinite;
	}

	.loading-dot:nth-child(2) {
		animation-delay: 0.2s;
	}

	.loading-dot:nth-child(3) {
		animation-delay: 0.4s;
	}

	@keyframes loadPulse {
		0%, 80%, 100% { opacity: 0.3; }
		40% { opacity: 1; }
	}

	/* ===== Todo Card ===== */
	.todo-card {
		background: var(--surface-2);
		border: 1px solid var(--border-subtle);
		border-radius: 12px;
		padding: 12px;
		max-width: 100%;
	}

	.todo-item {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 4px 0;
	}

	.todo-check {
		width: 16px;
		height: 16px;
		display: flex;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
	}

	.todo-text {
		color: var(--text-primary);
		line-height: 1.4;
	}

	.todo-item.status-done .todo-text {
		text-decoration: line-through;
		color: var(--text-tertiary);
	}

	.todo-empty {
		width: 12px;
		height: 12px;
		border-radius: 3px;
		border: 1.5px solid var(--border-subtle);
	}

	.todo-spinner {
		width: 10px;
		height: 10px;
		border: 1.5px solid var(--accent);
		border-top-color: transparent;
		border-radius: 50%;
		animation: spin 0.8s linear infinite;
	}

	@keyframes spin {
		to { transform: rotate(360deg); }
	}

	/* ===== Notice Row ===== */
	.notice-row {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 6px 12px;
		background: var(--surface-2);
		border-radius: 8px;
		color: var(--text-secondary);
	}

	.notice-icon {
		flex-shrink: 0;
		font-size: 14px;
	}

	.notice-text {
		line-height: 1.4;
	}

	/* ===== Turn End Row ===== */
	.turn-end-row {
		display: flex;
		align-items: center;
		padding: 4px 0;
	}

	.turn-end-label {
		color: var(--text-tertiary);
		font-style: italic;
	}

	/* ===== Hydra Row ===== */
	.hydra-row {
		display: flex;
		flex-direction: column;
		gap: 6px;
		padding: 8px 12px;
		background: rgba(139, 92, 246, 0.06);
		border: 1px solid rgba(139, 92, 246, 0.15);
		border-radius: 10px;
	}

	.hydra-icon {
		font-size: 14px;
	}

	.hydra-text {
		color: var(--text-secondary);
		line-height: 1.4;
	}

	.hydra-heads {
		display: flex;
		flex-wrap: wrap;
		gap: 6px;
	}

	.hydra-head-tag {
		font-size: 10px;
		font-weight: 600;
		padding: 3px 8px;
		border-radius: 10px;
		border: 1px solid;
		line-height: 1.2;
	}

	/* ===== Generic Event Row (fallback) ===== */
	.event-row {
		border-radius: 6px;
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.03));
		transition: background 160ms ease;
		overflow: hidden;
	}

	.event-row:hover {
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.07));
	}

	.event-row.expanded {
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.06));
	}

	.event-header {
		appearance: none;
		border: none;
		background: transparent;
		display: flex;
		align-items: center;
		gap: 8px;
		width: 100%;
		padding: 7px 10px;
		cursor: pointer;
		text-align: left;
		font-family: inherit;
		color: var(--chrome-primary, #111827);
		transition: background 120ms ease;
		border-radius: 6px;
	}

	.event-header:hover {
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.04));
	}

	.event-icon {
		font-size: 12px;
		flex-shrink: 0;
		width: 18px;
		text-align: center;
	}

	.event-desc {
		font-size: 12px;
		line-height: 1.4;
		flex: 1;
		min-width: 0;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.event-details-hint {
		font-size: 10px;
		color: var(--chrome-secondary, #6b7280);
		flex-shrink: 0;
	}

	.event-detail {
		padding: 0 10px 10px;
		border-top: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.06));
		margin-top: 2px;
		padding-top: 8px;
	}

	.detail-section {
		margin-bottom: 6px;
	}

	.detail-label {
		display: block;
		font-size: 10px;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--chrome-secondary, #6b7280);
		margin-bottom: 4px;
	}

	.detail-pre {
		font-family: 'SF Mono', 'Menlo', 'Consolas', monospace;
		font-size: 11px;
		line-height: 1.5;
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.05));
		border-radius: 6px;
		padding: 8px 10px;
		margin: 0;
		overflow-x: auto;
		white-space: pre-wrap;
		word-break: break-word;
		max-height: 200px;
		color: var(--chrome-primary, #111827);
	}

	.detail-tags {
		display: flex;
		flex-wrap: wrap;
		gap: 6px;
	}

	.file-thumb {
		display: flex;
		align-items: center;
		gap: 6px;
	}

	.file-icon {
		font-size: 16px;
	}

	.file-name {
		font-size: 12px;
		font-weight: 500;
	}
</style>
