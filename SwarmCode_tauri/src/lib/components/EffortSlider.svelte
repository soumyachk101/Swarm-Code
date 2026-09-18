<script lang="ts">
	interface EffortLevel {
		value: string;
		label: string;
		description: string;
	}

	interface Props {
		value?: string | null;
		onChange: (value: string) => void;
		options?: EffortLevel[];
	}

	const DEFAULT_EFFORTS: EffortLevel[] = [
		{ value: 'minimal', label: 'Minimal', description: 'Fastest, most concise' },
		{ value: 'low', label: 'Low', description: 'Quick, low-cost tasks' },
		{ value: 'medium', label: 'Medium', description: 'Balanced speed and quality' },
		{ value: 'high', label: 'High', description: 'Careful, thorough reasoning' },
		{ value: 'xhigh', label: 'Extra', description: 'Deep thinking, max effort' },
	];

	let { value = 'medium', onChange, options = DEFAULT_EFFORTS }: Props = $props();

	let activeIndex = $derived(
		options.findIndex(opt => opt.value === value)
	);

	let sliderPercent = $derived(
		activeIndex >= 0 ? (activeIndex / Math.max(1, options.length - 1)) * 100 : 50
	);

	let activeOption = $derived(
		options[activeIndex] ?? options[0]
	);

	function selectOption(opt: EffortLevel) {
		onChange(opt.value);
	}
</script>

<div class="effort-slider">
	<div class="slider-header">
		<span class="label">Effort</span>
		<span class="value">{activeOption?.label ?? value}</span>
	</div>

	<div class="slider-track">
		<div class="slider-fill" style="width: {sliderPercent}%"></div>
		<div
			class="slider-thumb"
			style="left: {sliderPercent}%"
		></div>
	</div>

	<div class="slider-options">
		{#each options as opt (opt.value)}
			<button
				class="option-btn"
				class:active={opt.value === value}
				onclick={() => selectOption(opt)}
				title={opt.description}
			>
				{opt.label}
			</button>
		{/each}
	</div>

	{#if activeOption?.description}
		<p class="description">{activeOption.description}</p>
	{/if}
</div>

<style>
	.effort-slider {
		display: flex;
		flex-direction: column;
		gap: var(--space-2);
		padding: var(--space-3);
		background: var(--surface-2);
		border: var(--border-1) var(--border-color-1);
		border-radius: var(--radius-md);
	}

	.slider-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
	}

	.label {
		font-size: var(--font-size-xs);
		font-weight: 500;
		color: var(--text-tertiary);
		text-transform: uppercase;
		letter-spacing: 0.3px;
	}

	.value {
		font-size: var(--font-size-sm);
		font-weight: 600;
		color: var(--accent-1);
	}

	.slider-track {
		position: relative;
		height: 4px;
		background: var(--surface-3);
		border-radius: var(--radius-full);
		margin: 6px 8px;
	}

	.slider-fill {
		position: absolute;
		left: 0;
		top: 0;
		bottom: 0;
		background: var(--accent-1);
		border-radius: var(--radius-full);
		transition: width var(--transition-base);
	}

	.slider-thumb {
		position: absolute;
		top: 50%;
		width: 12px;
		height: 12px;
		border-radius: 50%;
		background: var(--surface-1);
		border: 2px solid var(--accent-1);
		transform: translate(-50%, -50%);
		cursor: grab;
		transition: left var(--transition-base), transform var(--transition-fast);
		box-shadow: 0 1px 4px rgba(0, 0, 0, 0.2);
	}

	.slider-thumb:hover {
		transform: translate(-50%, -50%) scale(1.15);
	}

	.slider-options {
		display: flex;
		gap: 2px;
		margin-top: var(--space-1);
	}

	.option-btn {
		flex: 1;
		padding: 4px 0;
		border: none;
		background: transparent;
		font-size: 10px;
		color: var(--text-tertiary);
		cursor: pointer;
		transition: all var(--transition-fast);
		text-transform: uppercase;
		letter-spacing: 0.3px;
		border-radius: var(--radius-sm);
	}

	.option-btn:hover {
		color: var(--text-primary);
	}

	.option-btn.active {
		color: var(--accent-1);
		font-weight: 600;
	}

	.description {
		font-size: 11px;
		color: var(--text-tertiary);
		font-style: italic;
		margin-top: var(--space-1);
	}
</style>
