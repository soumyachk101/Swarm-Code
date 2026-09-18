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
</script>

<svg
	width={size}
	height={size}
	viewBox="0 0 24 24"
	fill="none"
	xmlns="http://www.w3.org/2000/svg"
	class="timeline-glyph {animationClass}"
>
	{#if state === 'idle'}
		<!-- Horizontal timeline bar with tick marks -->
		<line x1="3" y1="12" x2="21" y2="12" stroke={iconColor} stroke-width="1.5" stroke-linecap="round" opacity="0.4"/>
		<circle cx="6" cy="12" r="2" stroke={iconColor} stroke-width="1.5" fill="none"/>
		<circle cx="12" cy="12" r="2" stroke={iconColor} stroke-width="1.5" fill="none"/>
		<circle cx="18" cy="12" r="2" stroke={iconColor} stroke-width="1.5" fill="none"/>
	{:else if state === 'thinking'}
		<line x1="3" y1="12" x2="21" y2="12" stroke={iconColor} stroke-width="1.5" stroke-linecap="round" opacity="0.4"/>
		<circle cx="6" cy="12" r="2" stroke={iconColor} stroke-width="1.5" fill={iconColor}/>
		<circle cx="12" cy="12" r="2" stroke={iconColor} stroke-width="1.5" fill={iconColor}/>
		<circle cx="18" cy="12" r="2" stroke={iconColor} stroke-width="1.5" fill="none"/>
	{:else if state === 'running'}
		<line x1="3" y1="12" x2="21" y2="12" stroke={iconColor} stroke-width="1.5" stroke-linecap="round" opacity="0.6"/>
		<circle cx="6" cy="12" r="2.5" stroke={iconColor} stroke-width="1.5" fill={iconColor}/>
		<circle cx="12" cy="12" r="2.5" stroke={iconColor} stroke-width="1.5" fill={iconColor}/>
		<circle cx="18" cy="12" r="2.5" stroke={iconColor} stroke-width="1.5" fill={iconColor}/>
	{:else if state === 'done'}
		<line x1="3" y1="12" x2="21" y2="12" stroke={iconColor} stroke-width="1.5" stroke-linecap="round" opacity="0.6"/>
		<circle cx="6" cy="12" r="2" stroke={iconColor} stroke-width="1.5" fill={iconColor}/>
		<circle cx="12" cy="12" r="2" stroke={iconColor} stroke-width="1.5" fill={iconColor}/>
		<circle cx="18" cy="12" r="2" stroke={iconColor} stroke-width="1.5" fill={iconColor}/>
	{:else if state === 'error'}
		<line x1="3" y1="12" x2="21" y2="12" stroke={iconColor} stroke-width="1.5" stroke-linecap="round" opacity="0.3"/>
		<circle cx="12" cy="12" r="2" stroke="#ff3b48" stroke-width="1.5" fill="none"/>
	{/if}
</svg>

<style>
	.timeline-glyph.pulse {
		animation: pulse-glow 1.4s ease-in-out infinite;
	}

	@keyframes pulse-glow {
		0%, 100% { opacity: 1; }
		50% { opacity: 0.6; }
	}
</style>
