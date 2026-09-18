<script lang="ts">
	interface Props {
		size?: number;
		state?: 'idle' | 'thinking' | 'running' | 'done' | 'error';
		color?: string;
		animating?: boolean;
	}

	let { size = 16, state = 'idle', color = 'currentColor', animating = false }: Props = $props();

	let iconColor = $derived(color);
	let animationClass = $derived(animating ? 'pulse' : '');

	function getHeadCount(state: string): number {
		switch (state) {
			case 'thinking': return 3;
			case 'running': return 5;
			case 'done': return 1;
			case 'error': return 1;
			default: return 5;
		}
	}
</script>

<svg
	class="hydra-glyph {animationClass}"
	width={size}
	height={size}
	viewBox="0 0 24 24"
	fill="none"
	stroke={iconColor}
	stroke-width="2"
	stroke-linecap="round"
	stroke-linejoin="round"
>
	<!-- Central star shape -->
	<path d="M12 2l2 4 4 1-3 3 1 4-4-2-4 2 1-4-3-3 4-1z"/>
	<!-- Orbiting head indicators -->
	{#if state === 'thinking' || state === 'running'}
		{#each Array(getHeadCount(state)) as _, i}
			{@const angle = (i * 72 - 90) * Math.PI / 180}
			{@const r = 7}
			{@const cx = 12 + r * Math.cos(angle)}
			{@const cy = 12 + r * Math.sin(angle)}
			<circle cx={cx} cy={cy} r="1.2" fill={state === 'running' ? iconColor : 'none'} />
		{/each}
	{/if}
	<!-- Error indicator -->
	{#if state === 'error'}
		<line x1="15" y1="9" x2="9" y2="15" />
		<line x1="9" y1="9" x2="15" y2="15" />
	{/if}
</svg>

<style>
	.hydra-glyph {
		display: inline-flex;
		vertical-align: middle;
	}

	.hydra-glyph.pulse {
		animation: glyph-pulse 1.5s ease-in-out infinite;
	}

	@keyframes glyph-pulse {
		0%, 100% { opacity: 1; transform: scale(1); }
		50% { opacity: 0.7; transform: scale(0.92); }
	}
</style>
