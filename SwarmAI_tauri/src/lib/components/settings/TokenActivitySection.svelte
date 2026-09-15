<script lang="ts">
	// ---------------------------------------------------------------------------
	// TokenActivitySection – token usage statistics with heatmap, charts,
	// and per-provider breakdown. Matches TokenActivitySection.swift.
	// ---------------------------------------------------------------------------

	import type { ProviderKind } from '$lib/types';

	// ---------------------------------------------------------------------------
	// Types
	// ---------------------------------------------------------------------------

	export interface DailyTokenEntry {
		date: string; // "YYYY-MM-DD"
		tokens: number;
		providerBreakdown: Record<ProviderKind, number>;
	}

	export interface ProviderUsageSummary {
		provider: ProviderKind;
		totalTokens: number;
		percentage: number;
		requestCount: number;
		averageTokens: number;
	}

	export interface TokenActivityData {
		daily: DailyTokenEntry[];
		providerBreakdown: ProviderUsageSummary[];
		totalTokens: number;
	}

	// ---------------------------------------------------------------------------
	// Display modes
	// ---------------------------------------------------------------------------

	type ActivityMode = 'daily' | 'weekly' | 'cumulative';

	const MODE_LABELS: Record<ActivityMode, string> = {
		daily: 'Daily',
		weekly: 'Weekly',
		cumulative: 'Cumulative',
	};

	const PROVIDER_COLORS: Record<ProviderKind, string> = {
		[ProviderKind.Codex]: '#f59e0b',
		[ProviderKind.Claude]: '#6366f1',
		[ProviderKind.Cursor]: '#3b82f6',
		[ProviderKind.Opencode]: '#8b5cf6',
		[ProviderKind.Grok]: '#ec4899',
		[ProviderKind.Deepseek]: '#10b981',
		[ProviderKind.Meta]: '#06b6d4',
		[ProviderKind.Devin]: '#f97316',
		[ProviderKind.Antigravity]: '#14b8a6',
		[ProviderKind.Copilot]: '#6366f1',
	};

	// ---------------------------------------------------------------------------
	// Props
	// ---------------------------------------------------------------------------

	interface Props {
		data: TokenActivityData;
		readonly?: boolean;
	}

	let { data, readonly = false }: Props = $props();

	// ---------------------------------------------------------------------------
	// State
	// ---------------------------------------------------------------------------

	let mode = $state<ActivityMode>('daily');
	let hoveredDay = $state<string | null>(null);

	// ---------------------------------------------------------------------------
	// Derived
	// ---------------------------------------------------------------------------

	// Compute day-of-year grid (52 weeks x 7 days)
	let calendarGrid = $derived(() => {
		const dailyMap = new Map(data.daily.map((d) => [d.date, d.tokens]));
		const days: Date[] = [];
		const now = new Date();
		const yearStart = new Date(now.getFullYear(), 0, 1);
		const dayMs = 86400000;
		const totalDays = 366; // max for a year

		for (let i = 0; i < totalDays; i++) {
			const d = new Date(yearStart.getTime() + i * dayMs);
			const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
			const isFuture = d > now;
			days.push(d);
		}

		// Build 7-row (Sun-Sat) columns
		const rows = 7;
		const grid: Array<{ date: Date; dateKey: string; tokens: number; isFuture: boolean }[]> = [];
		const week: typeof grid[0] = [];

		// Pad to start on Sunday
		const firstDay = new Date(yearStart);
		const startWeekday = (firstDay.getDay() + 6) % 7; // Mon=0
		for (let i = 0; i < startWeekday; i++) {
			week.push({ date: new Date(0), dateKey: '', tokens: 0, isFuture: true });
		}

		for (const d of days) {
			const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
			const isFuture = d > now;
			week.push({ date: d, dateKey: key, tokens: dailyMap.get(key) ?? 0, isFuture });

			if (week.length === 7) {
				grid.push([...week]);
				week.length = 0;
			}
		}
		if (week.length > 0) {
			while (week.length < 7) week.push({ date: new Date(0), dateKey: '', tokens: 0, isFuture: true });
			grid.push([...week]);
		}

		return grid;
	});

	let maxDaily = $derived(Math.max(...data.daily.map((d) => d.tokens), 1));
	let cumulativeTotals = $derived(() => {
		let running = 0;
		const result: Record<string, number> = {};
		for (const entry of data.daily) {
			running += entry.tokens;
			result[entry.date] = running;
		}
		return result;
	});

	function getDisplayValue(dateKey: string, rowIndex: number, colIndex: number): number {
		if (mode === 'daily') {
			const entry = data.daily.find((d) => d.date === dateKey);
			return entry?.tokens ?? 0;
		} else if (mode === 'weekly') {
			// Sum of the current week
			let weekSum = 0;
			const startCol = Math.max(0, colIndex - 1);
			const endCol = Math.min(calendarGrid().length - 1, colIndex + 1);
			for (let c = startCol; c <= endCol; c++) {
				for (let r = 0; r < 7; r++) {
					if (calendarGrid()[c]?.[r]) weekSum += calendarGrid()[c][r].tokens;
				}
			}
			return weekSum;
		} else {
			return cumulativeTotals()[dateKey] ?? 0;
		}
	}

	function cellColor(dateKey: string, isFuture: boolean): string {
		const value = getDisplayValue(dateKey, 0, 0);
		if (isFuture) return 'rgba(99, 102, 241, 0.04)';
		if (value === 0) return 'rgba(99, 102, 241, 0.06)';
		const ratio = mode === 'daily' ? value / maxDaily : 0.5;
		const clamped = Math.min(ratio, 1);
		const alpha = 0.15 + clamped * 0.7;
		return `rgba(99, 102, 241, ${alpha.toFixed(2)})`;
	}

	function formatTokens(n: number): string {
		if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
		if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
		return String(n);
	}

	function hoveredInfo(dateKey: string | null): string {
		if (!dateKey) return '';
		const entry = data.daily.find((d) => d.date === dateKey);
		if (!entry) return '';
		return `${formatTokens(entry.tokens)} tokens`;
	}

	function setMode(m: ActivityMode) {
		mode = m;
	}

	function toggleProvider(provider: ProviderKind) {
		// In a real app, this would toggle provider visibility in the breakdown
	}

	// ---------------------------------------------------------------------------
	// Day labels
	// ---------------------------------------------------------------------------

	const DAY_LABELS = ['', 'Mon', '', 'Wed', '', 'Fri', ''];

	// Month tick marks
	let monthTicks = $derived(() => {
		const ticks: Array<{ label: string; col: number }> = [];
		const grid = calendarGrid();
		const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
		let lastMonth = -1;
		for (let c = 0; c < grid.length; c++) {
			const firstDay = grid[c][0];
			if (firstDay && firstDay.dateKey) {
				const d = new Date(firstDay.dateKey + 'T00:00:00');
				const m = d.getMonth();
				if (m !== lastMonth) {
					ticks.push({ label: monthNames[m], col: c });
					lastMonth = m;
				}
			}
		}
		return ticks;
	});

	function providerColor(provider: ProviderKind): string {
		return PROVIDER_COLORS[provider] ?? '#6b7280';
	}
</script>

<div class="token-activity-root">
	<!-- Summary -->
	<header class="summary-bar">
		<div class="summary-left">
			<h3 class="section-title">Token Activity</h3>
			<span class="total-count">{formatTokens(data.totalTokens)} total</span>
		</div>

		<!-- Mode toggle -->
		<div class="mode-toggle">
			{#each Object.keys(MODE_LABELS) as m}
				{@const isActive = mode === m}
				<button
					class="mode-pill"
					class:active={isActive}
					onclick={() => setMode(m as ActivityMode)}
					type="button"
				>
					{MODE_LABELS[m as ActivityMode]}
				</button>
			{/each}
		</div>
	</header>

	<!-- Heatmap -->
	<div class="heatmap-container">
		<!-- Day labels (left) -->
		<div class="day-labels">
			<div class="day-label-spacer"></div>
			{#each DAY_LABELS as label}
				<div class="day-label">{label}</div>
			{/each}
		</div>

		<!-- Grid -->
		<div class="heatmap-grid">
			<!-- Month ticks (top) -->
			<div class="month-ticks">
				{#each monthTicks() as tick}
					<div
						class="month-tick"
						style="grid-column: {tick.col + 1};"
					>
						{tick.label}
					</div>
				{/each}
			</div>

			<!-- Cells -->
			<div class="grid-cells">
				{#each calendarGrid() as col, colIndex}
					{#each col as cell, rowIndex}
						{@const isHovered = hoveredDay === cell.dateKey}
						{@const color = cellColor(cell.dateKey, cell.isFuture)}
						<div
							class="heatmap-cell"
							class:future-cell={cell.isFuture}
							class:hovered={isHovered}
							style="background: {color}; grid-column: {colIndex + 1}; grid-row: {rowIndex + 1};"
							onmouseenter={() => { if (cell.dateKey) hoveredDay = cell.dateKey; }}
							onmouseleave={() => { hoveredDay = null; }}
							title={cell.dateKey ? `${cell.dateKey}: ${formatTokens(cell.tokens)}` : ''}
						></div>
					{/each}
				{/each}
			</div>
		</div>

		<!-- Tooltip -->
		{#if hoveredDay}
			{@const entry = data.daily.find((d) => d.date === hoveredDay)}
			{#if entry}
				<div class="heatmap-tooltip">
					<span class="tooltip-date">{entry.date}</span>
					<span class="tooltip-value">{formatTokens(entry.tokens)} tokens</span>
				</div>
			{/if}
		{/if}
	</div>

	<!-- Provider breakdown -->
	<section class="provider-section">
		<h4 class="subsection-title">By Provider</h4>

		{#if data.providerBreakdown.length === 0}
			<p class="no-data">No provider data yet.</p>
		{:else}
			<div class="provider-list">
				{#each data.providerBreakdown as prov}
					{@const pct = prov.percentage}
					{@const barWidth = `${Math.min(pct, 100).toFixed(1)}%`}
					<div class="provider-row">
						<div class="provider-info">
							<span
								class="provider-dot"
								style="background: {providerColor(prov.provider)};"
							></span>
							<span class="provider-name">
								{prov.provider.charAt(0).toUpperCase() + prov.provider.slice(1)}
							</span>
							<span class="provider-count">{formatTokens(prov.totalTokens)}</span>
						</div>
						<div class="provider-bar-track">
							<div
								class="provider-bar"
								style="width: {barWidth}; background: {providerColor(prov.provider)};"
							></div>
						</div>
						<span class="provider-pct">{pct.toFixed(1)}%</span>
					</div>
				{/each}
			</div>
		{/if}
	</section>

	<!-- Detailed chart (last 14 days) -->
	{#if data.daily.length > 1}
		<section class="chart-section">
			<h4 class="subsection-title">Last 14 Days</h4>
			<div class="bar-chart">
				{#each data.daily.slice(-14) as entry}
					{@const barH = maxDaily > 0 ? `${(entry.tokens / maxDaily) * 100}%` : '0%'}
					<div class="bar-col">
						<div class="bar-fill" style="height: {barH};">
							{#if entry.tokens > 0}
								<span class="bar-label">{formatTokens(entry.tokens)}</span>
							{/if}
						</div>
						<span class="bar-date">
							{new Date(entry.date + 'T00:00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric' })}
						</span>
					</div>
				{/each}
			</div>
		</section>
	{/if}
</div>

<style>
	.token-activity-root {
		display: flex;
		flex-direction: column;
		gap: 20px;
		padding: 16px;
		font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', sans-serif;
	}

	/* ── Summary ── */

	.summary-bar {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 12px;
		flex-wrap: wrap;
	}

	.summary-left {
		display: flex;
		align-items: baseline;
		gap: 8px;
	}

	.section-title {
		font-size: 15px;
		font-weight: 600;
		color: var(--chrome-primary, #111827);
		margin: 0;
	}

	.total-count {
		font-size: 12px;
		color: var(--chrome-secondary, #6b7280);
	}

	.mode-toggle {
		display: flex;
		gap: 2px;
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.03));
		padding: 3px;
		border-radius: 10px;
	}

	.mode-pill {
		appearance: none;
		border: none;
		background: transparent;
		color: var(--chrome-secondary, #6b7280);
		font-size: 11px;
		font-weight: 500;
		padding: 5px 12px;
		border-radius: 8px;
		cursor: pointer;
		transition: all 140ms ease;
		font-family: inherit;
	}

	.mode-pill:hover {
		color: var(--chrome-primary, #111827);
	}

	.mode-pill.active {
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.06));
		color: var(--chrome-primary, #111827);
		font-weight: 600;
	}

	/* ── Heatmap ── */

	.heatmap-container {
		position: relative;
		overflow: hidden;
	}

	.day-labels {
		display: contents;
	}

	.day-label-spacer {
		width: 32px;
		flex-shrink: 0;
	}

	.day-label {
		font-size: 9px;
		color: var(--chrome-secondary, #9ca3af);
		height: 14px;
		display: flex;
		align-items: center;
		line-height: 1;
	}

	.heatmap-grid {
		display: flex;
		flex-direction: column;
		gap: 3px;
	}

	.month-ticks {
		display: flex;
		gap: 3px;
		margin-bottom: 2px;
		padding-left: 0;
	}

	.month-tick {
		font-size: 9px;
		color: var(--chrome-secondary, #9ca3af);
		font-weight: 500;
		min-width: 12px;
	}

	.grid-cells {
		display: grid;
		grid-template-rows: repeat(7, 12px);
		gap: 3px;
		grid-auto-flow: column;
		grid-auto-columns: 12px;
	}

	.heatmap-cell {
		width: 12px;
		height: 12px;
		border-radius: 2px;
		cursor: pointer;
		transition: transform 100ms ease, outline 100ms ease;
	}

	.heatmap-cell:hover {
		transform: scale(1.4);
		outline: 2px solid var(--chrome-primary, #111827);
		z-index: 2;
	}

	.heatmap-cell.future-cell {
		cursor: default;
	}

	.heatmap-cell.hovered {
		outline: 2px solid var(--chrome-primary, #111827);
		transform: scale(1.3);
		z-index: 2;
	}

	.heatmap-tooltip {
		position: absolute;
		background: var(--chrome-primary, #111827);
		color: #ffffff;
		font-size: 11px;
		padding: 6px 10px;
		border-radius: 6px;
		display: flex;
		flex-direction: column;
		gap: 2px;
		pointer-events: none;
		z-index: 10;
		white-space: nowrap;
		box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
	}

	.tooltip-date {
		font-size: 10px;
		opacity: 0.7;
	}

	.tooltip-value {
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}

	/* ── Provider breakdown ── */

	.subsection-title {
		font-size: 13px;
		font-weight: 600;
		color: var(--chrome-primary, #111827);
		margin: 0;
	}

	.provider-list {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}

	.provider-row {
		display: grid;
		grid-template-columns: 1fr 2fr 50px;
		gap: 10px;
		align-items: center;
	}

	.provider-info {
		display: flex;
		align-items: center;
		gap: 6px;
		min-width: 0;
	}

	.provider-dot {
		width: 8px;
		height: 8px;
		border-radius: 50%;
		flex-shrink: 0;
	}

	.provider-name {
		font-size: 12px;
		color: var(--chrome-primary, #111827);
		font-weight: 500;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.provider-count {
		font-size: 11px;
		color: var(--chrome-secondary, #6b7280);
		font-variant-numeric: tabular-nums;
	}

	.provider-bar-track {
		height: 6px;
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.06));
		border-radius: 3px;
		overflow: hidden;
	}

	.provider-bar {
		height: 100%;
		border-radius: 3px;
		transition: width 400ms cubic-bezier(0.22, 0.61, 0.36, 1);
	}

	.provider-pct {
		font-size: 11px;
		color: var(--chrome-secondary, #6b7280);
		font-variant-numeric: tabular-nums;
		text-align: right;
	}

	.no-data {
		font-size: 12px;
		color: var(--chrome-secondary, #6b7280);
		margin: 0;
		padding: 8px 0;
	}

	/* ── Bar chart ── */

	.chart-section {
		margin-top: 4px;
	}

	.bar-chart {
		display: flex;
		align-items: flex-end;
		gap: 4px;
		height: 120px;
		padding-top: 8px;
	}

	.bar-col {
		flex: 1;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: flex-end;
		min-height: 0;
	}

	.bar-fill {
		width: 100%;
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.08));
		border-radius: 4px 4px 2px 2px;
		transition: height 400ms cubic-bezier(0.22, 0.61, 0.36, 1);
		display: flex;
		align-items: flex-start;
		justify-content: center;
		padding-top: 3px;
		position: relative;
		background: linear-gradient(to top, rgba(99, 102, 241, 0.7), rgba(99, 102, 241, 0.3));
	}

	.bar-label {
		font-size: 8px;
		font-weight: 600;
		color: var(--chrome-primary, #111827);
		position: absolute;
		top: -14px;
		white-space: nowrap;
	}

	.bar-date {
		font-size: 8px;
		color: var(--chrome-secondary, #9ca3af);
		margin-top: 4px;
		transform: rotate(-45deg);
		transform-origin: center;
		white-space: nowrap;
	}

	@media (prefers-reduced-motion: reduce) {
		.heatmap-cell,
		.provider-bar,
		.bar-fill {
			transition: none;
		}
	}

	@media (max-width: 480px) {
		.token-activity-root {
			padding: 12px;
		}
		.provider-row {
			grid-template-columns: 1fr 1fr auto;
		}
		.provider-bar-track {
			display: none;
		}
	}
</style>
