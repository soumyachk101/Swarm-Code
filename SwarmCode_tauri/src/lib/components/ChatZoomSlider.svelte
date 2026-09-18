<script lang="ts">
	// ---------------------------------------------------------------------------
	// ChatZoomSlider – zoom control for chat text size
	// Matches ChatZoomSlider.swift: a slider with Small/Medium/Large labels and
	// a +5%/-5% stepper, persisted to settings via the invoker.
	// ---------------------------------------------------------------------------

	// ---------------------------------------------------------------------------
	// Props
	// ---------------------------------------------------------------------------

	interface Props {
		fontSize: number;
		readonly?: boolean;
		onChange: (value: number) => void;
	}

	let { fontSize = $bindable(14), readonly = false, onChange }: Props = $props();

	// ---------------------------------------------------------------------------
	// Slider range
	// ---------------------------------------------------------------------------

	const min = 10;
	const max = 26;
	const step = 1;
	const presetSmall = 12;
	const presetMedium = 14;
	const presetLarge = 18;

	// ---------------------------------------------------------------------------
	// Derived
	// ---------------------------------------------------------------------------

	let pct = $derived(((fontSize - min) / (max - min)) * 100);

	function bump(delta: number) {
		if (readonly) return;
		const next = Math.max(min, Math.min(max, fontSize + delta));
		fontSize = next;
		onChange(next);
	}

	function setPreset(value: number) {
		if (readonly) return;
		fontSize = value;
		onChange(value);
	}

	// ---------------------------------------------------------------------------
	// Keyboard
	// ---------------------------------------------------------------------------

	function onKey(event: KeyboardEvent) {
		if (readonly) return;
		if (event.key === 'ArrowUp' || event.key === 'ArrowRight') {
			event.preventDefault();
			bump(1);
		} else if (event.key === 'ArrowDown' || event.key === 'ArrowLeft') {
			event.preventDefault();
			bump(-1);
		}
	}
</script>

<div class="zoom-slider-root" role="group" aria-label="Chat text size">
	<!-- Label bar -->
	<div class="zoom-label-bar">
		<span class="zoom-title">Text Size</span>
		<span class="zoom-value">{fontSize}px</span>
	</div>

	<!-- Slider + stepper row -->
	<div class="zoom-row">
		<!-- Minus button -->
		<button
			class="step-btn"
			onclick={() => bump(-1)}
			disabled={readonly || fontSize <= min}
			aria-label="Decrease text size"
			type="button"
		>
			−5%
		</button>

		<!-- Range input -->
		<div class="slider-wrap">
			<input
				type="range"
				class="zoom-input"
				{min}
				{max}
				{step}
				value={fontSize}
				disabled={readonly}
				oninput={(e) => {
					const v = parseInt((e.target as HTMLInputElement).value, 10);
					if (!isNaN(v)) {
						fontSize = v;
						onChange(v);
					}
				}}
				onkeydown={onKey}
			/>
			<!-- Custom track fill -->
			<div class="slider-track" aria-hidden="true">
				<div class="slider-fill" style="width: {pct}%"></div>
			</div>
		</div>

		<!-- Plus button -->
		<button
			class="step-btn"
			onclick={() => bump(1)}
			disabled={readonly || fontSize >= max}
			aria-label="Increase text size"
			type="button"
		>
			+5%
		</button>
	</div>

	<!-- Presets -->
	<div class="preset-row">
		<button
			class="preset-btn"
			class:active={fontSize === presetSmall}
			onclick={() => setPreset(presetSmall)}
			disabled={readonly}
			type="button"
			aria-pressed={fontSize === presetSmall}
		>
			Small
		</button>
		<button
			class="preset-btn"
			class:active={fontSize === presetMedium}
			onclick={() => setPreset(presetMedium)}
			disabled={readonly}
			type="button"
			aria-pressed={fontSize === presetMedium}
		>
			Medium
		</button>
		<button
			class="preset-btn"
			class:active={fontSize === presetLarge}
			onclick={() => setPreset(presetLarge)}
			disabled={readonly}
			type="button"
			aria-pressed={fontSize === presetLarge}
		>
			Large
		</button>
	</div>
</div>

<style>
	.zoom-slider-root {
		display: flex;
		flex-direction: column;
		gap: 10px;
		width: 100%;
		max-width: 380px;
		font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', sans-serif;
	}

	.zoom-label-bar {
		display: flex;
		align-items: center;
		justify-content: space-between;
	}

	.zoom-title {
		font-size: 12px;
		font-weight: 500;
		color: var(--chrome-secondary, #6b7280);
		text-transform: uppercase;
		letter-spacing: 0.04em;
	}

	.zoom-value {
		font-size: 13px;
		font-weight: 600;
		color: var(--chrome-primary, #111827);
		font-variant-numeric: tabular-nums;
		font-family: 'SF Mono', monospace;
	}

	.zoom-row {
		display: flex;
		align-items: center;
		gap: 12px;
	}

	.step-btn {
		appearance: none;
		border: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.12));
		background: var(--chrome-surface, transparent);
		color: var(--chrome-primary, #111827);
		font-size: 11px;
		font-weight: 500;
		padding: 4px 10px;
		border-radius: 8px;
		cursor: pointer;
		transition: all 140ms ease;
		font-family: inherit;
		min-width: 44px;
	}

	.step-btn:hover:not(:disabled) {
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.08));
	}

	.step-btn:active:not(:disabled) {
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.14));
	}

	.step-btn:disabled {
		opacity: 0.35;
		cursor: not-allowed;
	}

	.slider-wrap {
		flex: 1;
		position: relative;
		height: 28px;
		display: flex;
		align-items: center;
	}

	.zoom-input {
		appearance: none;
		-webkit-appearance: none;
		width: 100%;
		height: 6px;
		background: transparent;
		outline: none;
		cursor: pointer;
		position: relative;
		z-index: 2;
	}

	.zoom-input::-webkit-slider-thumb {
		-webkit-appearance: none;
		width: 18px;
		height: 18px;
		border-radius: 50%;
		background: var(--chrome-accent, #6366f1);
		border: 2px solid var(--chrome-surface, #ffffff);
		box-shadow: 0 1px 4px rgba(0, 0, 0, 0.18);
		cursor: pointer;
		transition: transform 120ms ease;
	}

	.zoom-input::-webkit-slider-thumb:hover {
		transform: scale(1.15);
	}

	.zoom-input::-moz-range-thumb {
		width: 18px;
		height: 18px;
		border-radius: 50%;
		background: var(--chrome-accent, #6366f1);
		border: 2px solid var(--chrome-surface, #ffffff);
		box-shadow: 0 1px 4px rgba(0, 0, 0, 0.18);
		cursor: pointer;
	}

	.zoom-input:disabled {
		opacity: 0.4;
		cursor: not-allowed;
	}

	.slider-track {
		position: absolute;
		left: 0;
		right: 0;
		top: 50%;
		transform: translateY(-50%);
		height: 4px;
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.1));
		border-radius: 2px;
		pointer-events: none;
		z-index: 1;
	}

	.slider-fill {
		height: 100%;
		background: var(--chrome-accent, #6366f1);
		border-radius: 2px;
		transition: width 100ms ease;
	}

	.preset-row {
		display: flex;
		gap: 6px;
	}

	.preset-btn {
		flex: 1;
		appearance: none;
		border: 1px solid var(--chrome-overlay, rgba(0, 0, 0, 0.1));
		background: var(--chrome-surface, transparent);
		color: var(--chrome-secondary, #6b7280);
		font-size: 11px;
		font-weight: 500;
		padding: 6px 0;
		border-radius: 8px;
		cursor: pointer;
		transition: all 140ms ease;
		font-family: inherit;
		text-align: center;
	}

	.preset-btn:hover:not(:disabled) {
		background: var(--chrome-overlay-soft, rgba(0, 0, 0, 0.04));
		color: var(--chrome-primary, #111827);
	}

	.preset-btn:active:not(:disabled) {
		background: var(--chrome-overlay, rgba(0, 0, 0, 0.1));
	}

	.preset-btn.active {
		background: var(--chrome-accent, #6366f1);
		color: #ffffff;
		border-color: var(--chrome-accent, #6366f1);
		font-weight: 600;
	}

	.preset-btn:disabled {
		opacity: 0.4;
		cursor: not-allowed;
	}

	@media (prefers-reduced-motion: reduce) {
		.zoom-input::-webkit-slider-thumb,
		.preset-btn,
		.step-btn,
		.slider-fill {
			transition: none;
		}
	}
</style>
