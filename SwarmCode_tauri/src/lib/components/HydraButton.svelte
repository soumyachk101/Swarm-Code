<script lang="ts">
	// ---------------------------------------------------------------------------
	// HydraButton – toggle hydra mode in the composer
	// Matches HydraButton.swift: a button that opens a configuration panel
	// with head count selector, provider picker, and merge options.
	// ---------------------------------------------------------------------------

	import { HYDRA_PERSONAS } from '$lib/types';
	import { hydraPersonaAt } from '$lib/types';

	// ---------------------------------------------------------------------------
	// Props
	// ---------------------------------------------------------------------------

	interface Props {
		enabled?: boolean;
		readonly?: boolean;
		maxHeads?: number;
		headCount?: number;
		selectedPersonas?: number[];
		onToggle: () => void;
		onHeadCountChange: (count: number) => void;
		onPersonaToggle: (index: number) => void;
	}

	let {
		enabled = $bindable(false),
		readonly = false,
		maxHeads = 8,
		headCount = $bindable(1),
		selectedPersonas = $bindable([0]),
		onToggle,
		onHeadCountChange,
		onPersonaToggle,
	}: Props = $props();

	// ---------------------------------------------------------------------------
	// State
	// ---------------------------------------------------------------------------

	let panelOpen = $state(false);
	let autoMerge = $state(true);
	let reviewsHeads = $state(false);
	let isolatesHeads = $state(true);

	let triggerRef: HTMLDivElement | undefined = $state();
	let panelRef: HTMLDivElement | undefined = $state();

	// Close panel when clicking outside
	$effect(() => {
		if (!panelOpen) return;
		const handleClick = (e: MouseEvent) => {
			const tgt = e.target as Node;
			if (triggerRef?.contains(tgt) || panelRef?.contains(tgt)) return;
			panelOpen = false;
		};
		document.addEventListener('mousedown', handleClick);
		return () => document.removeEventListener('mousedown', handleClick);
	});

	// ---------------------------------------------------------------------------
	// Helpers
	// ---------------------------------------------------------------------------

	const personaColors = HYDRA_PERSONAS.map((p) => '#' + p.hex.toString(16).padStart(6, '0'));

	function personaLabel(index: number): string {
		return hydraPersonaAt(index).name;
	}

	function personaColor(index: number): string {
		return personaColors[index] ?? '#8b5cf6';
	}

	function togglePersona(index: number) {
		if (readonly) return;
		const next = new Set(selectedPersonas);
		if (next.has(index)) {
			// don't remove if it's the last one
			if (next.size > 1) next.delete(index);
		} else {
			next.add(index);
		}
		selectedPersonas = Array.from(next);
		onPersonaToggle(index);
	}

	function setHeadCount(count: number) {
		if (readonly) return;
		headCount = Math.max(1, Math.min(maxHeads, count));
		onHeadCountChange(headCount);
	}

	function handleToggle() {
		if (readonly) return;
		enabled = !enabled;
		onToggle();
		if (!enabled) panelOpen = false;
	}
</script>

<div class="hydra-button-root">
	<!-- Main toggle button -->
	<div bind:this={triggerRef}>
		<button
			class="hydra-trigger"
			class:active={enabled}
			class:panel-open={panelOpen}
			onclick={handleToggle}
			disabled={readonly}
			type="button"
			title={enabled ? 'Disable Hydra mode' : 'Enable Hydra multi-head mode'}
			aria-pressed={enabled}
		>
			<span class="hydra-trigger-icon">
				<svg width="16" height="16" viewBox="0 0 16 16" fill="none" aria-hidden="true">
					<circle cx="8" cy="8" r="2.5" fill="currentColor"/>
					<circle cx="2.5" cy="3" r="1.8" fill="currentColor" opacity="0.7"/>
					<circle cx="13.5" cy="3" r="1.8" fill="currentColor" opacity="0.7"/>
					<circle cx="2.5" cy="13" r="1.8" fill="currentColor" opacity="0.7"/>
					<circle cx="13.5" cy="13" r="1.8" fill="currentColor" opacity="0.7"/>
					<line x1="5.8" y1="5.3" x2="3.4" y2="4.2" stroke="currentColor" stroke-width="1.2" opacity="0.5"/>
					<line x1="10.2" y1="5.3" x2="12.6" y2="4.2" stroke="currentColor" stroke-width="1.2" opacity="0.5"/>
					<line x1="5.8" y1="10.7" x2="3.4" y2="11.8" stroke="currentColor" stroke-width="1.2" opacity="0.5"/>
					<line x1="10.2" y1="10.7" x2="12.6" y2="11.8" stroke="currentColor" stroke-width="1.2" opacity="0.5"/>
				</svg>
			</span>
			<span class="hydra-trigger-label">Hydra</span>

			{#if enabled && selectedPersonas.length > 0}
				<span class="head-count-badge" style="background: {personaColor(selectedPersonas[0])}22; color: {personaColor(selectedPersonas[0])}">
					{selectedPersonas.length}
				</span>
			{/if}
		</button>
	</div>

	<!-- Config panel -->
	{#if panelOpen}
		<div bind:this={panelRef} class="hydra-panel" role="dialog" aria-label="Hydra configuration">
			<header class="panel-header">
				<span class="panel-title">Hydra Configuration</span>
				<button class="close-btn" onclick={() => panelOpen = false} type="button" aria-label="Close">✕</button>
			</header>

			<!-- Head count -->
			<section class="panel-section">
				<label class="section-label">Head Count</label>
				<div class="head-count-control">
					<button
						class="count-btn"
						onclick={() => setHeadCount(headCount - 1)}
						disabled={headCount <= 1}
						type="button"
					>−</button>
					<span class="count-value">{headCount}</span>
					<button
						class="count-btn"
						onclick={() => setHeadCount(headCount + 1)}
						disabled={headCount >= maxHeads}
						type="button"
					>+</button>
				</div>
			</section>

			<!-- Persona selection -->
			<section class="panel-section">
				<label class="section-label">Personas</label>
				<div class="persona-grid">
					{#each Array.from({ length: Math.min(maxHeads, 8) }) as _, i}
						{@const isSelected = selectedPersonas.includes(i)}
						<button
							class="persona-chip"
							class:selected={isSelected}
							style="
								--persona-color: {personaColor(i)};
								background: {isSelected ? personaColor(i) + '20' : 'var(--chrome-overlay-soft, rgba(0,0,0,0.03))'};
								border-color: {isSelected ? personaColor(i) + '55' : 'var(--chrome-overlay, rgba(0,0,0,0.08))'};
								color: {isSelected ? personaColor(i) : 'var(--chrome-secondary, #6b7280)'};
							"
							onclick={() => togglePersona(i)}
							type="button"
							title={personaLabel(i)}
						>
							<span class="persona-dot" style="background: {personaColor(i)}"></span>
							{personaLabel(i)}
						</button>
					{/each}
				</div>
			</section>

			<!-- Options -->
			<section class="panel-section">
				<label class="checkbox-row">
					<input type="checkbox" bind:checked={autoMerge} />
					<span class="checkbox-label">Auto-merge results</span>
				</label>
				<label class="checkbox-row">
					<input type="checkbox" bind:checked={reviewsHeads} />
					<span class="checkbox-label">Review each head's output</span>
				</label>
				<label class="checkbox-row">
					<input type="checkbox" bind:checked={isolatesHeads} />
					<span class="checkbox-label">Isolate head runs</span>
				</label>
			</section>

			<!-- Apply -->
			<footer class="panel-footer">
				<button class="apply-btn" onclick={() => panelOpen = false} type="button">
					Apply
				</button>
			</footer>
		</div>
	{/if}
</div>

<style>
	.hydra-button-root {
		position: relative;
		display: inline-flex;
		align-items: center;
	}

	.hydra-trigger {
		appearance: none;
		border: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.1));
		background: var(--chrome-surface, transparent);
		color: var(--chrome-secondary, #6b7280);
		font-size: 12px;
		font-weight: 500;
		padding: 6px 10px;
		border-radius: 8px;
		cursor: pointer;
		transition: all 160ms ease;
		display: inline-flex;
		align-items: center;
		gap: 5px;
		font-family: inherit;
	}

	.hydra-trigger:hover:not(:disabled) {
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.04));
	}

	.hydra-trigger.active {
		background: #8b5cf615;
		border-color: #8b5cf640;
		color: #8b5cf6;
	}

	.hydra-trigger:disabled {
		opacity: 0.4;
		cursor: not-allowed;
	}

	.hydra-trigger-icon {
		display: inline-flex;
		align-items: center;
	}

	.hydra-trigger-label {
		font-weight: 600;
	}

	.head-count-badge {
		font-size: 10px;
		font-weight: 700;
		padding: 1px 6px;
		border-radius: 8px;
		line-height: 1.3;
		min-width: 16px;
		text-align: center;
	}

	/* ── Panel ── */

	.hydra-panel {
		position: absolute;
		top: calc(100% + 8px);
		right: 0;
		width: 260px;
		background: var(--chrome-surface, #ffffff);
		border: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.1));
		border-radius: 12px;
		box-shadow: 0 8px 30px rgba(0, 0, 0, 0.14), 0 2px 6px rgba(0, 0, 0, 0.06);
		z-index: 50;
		overflow: hidden;
		animation: panelIn 160ms ease;
		font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', sans-serif;
	}

	@keyframes panelIn {
		from {
			opacity: 0;
			transform: translateY(-4px) scale(0.97);
		}
		to {
			opacity: 1;
			transform: translateY(0) scale(1);
		}
	}

	.panel-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 12px 14px;
		border-bottom: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.06));
	}

	.panel-title {
		font-size: 13px;
		font-weight: 600;
		color: var(--chrome-primary, #111827);
	}

	.close-btn {
		appearance: none;
		border: none;
		background: transparent;
		color: var(--chrome-secondary, #6b7280);
		cursor: pointer;
		font-size: 12px;
		padding: 2px 6px;
		border-radius: 4px;
		transition: background 120ms;
	}

	.close-btn:hover {
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.08));
	}

	.panel-section {
		padding: 12px 14px;
		border-bottom: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.04));
	}

	.panel-section:last-of-type {
		border-bottom: none;
	}

	.section-label {
		display: block;
		font-size: 10px;
		font-weight: 600;
		text-transform: uppercase;
		letter-spacing: 0.05em;
		color: var(--chrome-secondary, #6b7280);
		margin-bottom: 8px;
	}

	/* ── Head count ── */

	.head-count-control {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 16px;
	}

	.count-btn {
		appearance: none;
		border: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.12));
		background: var(--chrome-surface, transparent);
		color: var(--chrome-primary, #111827);
		width: 30px;
		height: 30px;
		border-radius: 8px;
		font-size: 16px;
		cursor: pointer;
		display: flex;
		align-items: center;
		justify-content: center;
		transition: all 140ms ease;
		font-family: inherit;
		line-height: 1;
	}

	.count-btn:hover:not(:disabled) {
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.08));
	}

	.count-btn:disabled {
		opacity: 0.3;
		cursor: not-allowed;
	}

	.count-value {
		font-size: 20px;
		font-weight: 700;
		min-width: 32px;
		text-align: center;
		font-variant-numeric: tabular-nums;
		color: var(--chrome-primary, #111827);
	}

	/* ── Personas ── */

	.persona-grid {
		display: grid;
		grid-template-columns: repeat(2, 1fr);
		gap: 6px;
	}

	.persona-chip {
		appearance: none;
		border: 1px solid;
		background: transparent;
		font-size: 11px;
		font-weight: 500;
		padding: 6px 8px;
		border-radius: 8px;
		cursor: pointer;
		transition: all 140ms ease;
		display: flex;
		align-items: center;
		gap: 5px;
		font-family: inherit;
	}

	.persona-chip:hover {
		filter: brightness(0.95);
	}

	.persona-chip.selected {
		font-weight: 600;
	}

	.persona-dot {
		width: 8px;
		height: 8px;
		border-radius: 50%;
		flex-shrink: 0;
	}

	/* ── Options ── */

	.checkbox-row {
		display: flex;
		align-items: center;
		gap: 8px;
		cursor: pointer;
		padding: 4px 0;
		font-size: 12px;
		color: var(--chrome-primary, #111827);
	}

	.checkbox-row input[type='checkbox'] {
		accent-color: var(--chrome-accent, #6366f1);
		width: 14px;
		height: 14px;
	}

	/* ── Footer ── */

	.panel-footer {
		padding: 10px 14px;
	}

	.apply-btn {
		appearance: none;
		border: none;
		background: var(--chrome-accent, #6366f1);
		color: #ffffff;
		font-size: 12px;
		font-weight: 600;
		padding: 8px 0;
		border-radius: 8px;
		cursor: pointer;
		width: 100%;
		transition: background 140ms ease;
		font-family: inherit;
	}

	.apply-btn:hover {
		background: #4f46e5;
	}

	@media (prefers-reduced-motion: reduce) {
		.hydra-panel {
			animation: none;
		}
	}
</style>
