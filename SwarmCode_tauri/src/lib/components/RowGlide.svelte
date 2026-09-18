<script lang="ts">
	// ---------------------------------------------------------------------------
	// RowGlide – animated row transitions for list items
	// Matches RowGlide.swift: smooth enter/exit/swap animations for list rows.
	// In Svelte this is implemented as a wrapper that applies CSS transitions
	// and swap animations to child elements keyed by their identity.
	// ---------------------------------------------------------------------------

	// ---------------------------------------------------------------------------
	// Props
	// ---------------------------------------------------------------------------

	interface Props {
		readonly?: boolean;
		animationDuration?: number;
	}

	let { readonly = false, animationDuration = 300 }: Props = $props();

	// ---------------------------------------------------------------------------
	// Track visible items for enter/exit animations
	// ---------------------------------------------------------------------------

	export interface GlideItem {
		id: string;
		data: Record<string, unknown>;
	}

	interface ContextProps {
		items: GlideItem[];
		onItemsChange: (items: GlideItem[]) => void;
	}

	let context: ContextProps | null = $state(null);

	// ---------------------------------------------------------------------------
	// Item tracking
	// ---------------------------------------------------------------------------

	let seenIds = $state<Set<string>>(new Set());
	let enteringIds = $state<Set<string>>(new Set());
	let exitingIds = $state<Set<string>>(new Set());

	function trackItems(items: GlideItem[]) {
		const currentIds = new Set(items.map((i) => i.id));

		// Find entering items
		const entering = new Set<string>();
		for (const item of items) {
			if (!seenIds.has(item.id)) {
				entering.add(item.id);
				// Schedule removal from entering set after animation
				setTimeout(() => {
					enteringIds.delete(item.id);
				}, animationDuration);
			}
		}

		// Find exiting items
		const exiting = new Set<string>();
		for (const oldId of seenIds) {
			if (!currentIds.has(oldId)) {
				exiting.add(oldId);
				// Schedule removal after animation
				setTimeout(() => {
					exitingIds.delete(oldId);
				}, animationDuration);
			}
		}

		enteringIds = entering;
		exitingIds = exiting;
		seenIds = currentIds;
	}

	$effect(() => {
		if (context) trackItems(context.items);
	});

	// ---------------------------------------------------------------------------
	// Direction tracking (for gliding effect)
	// ---------------------------------------------------------------------------

	let previousOrder = $state<string[]>([]);

	function itemDirection(id: string): 'enter' | 'exit' | 'stay' | 'swap' {
		if (enteringIds.has(id)) return 'enter';
		if (exitingIds.has(id)) return 'exit';
		const prevIndex = previousOrder.indexOf(id);
		const newIndex = context ? context.items.findIndex((i) => i.id === id) : -1;
		if (prevIndex >= 0 && newIndex >= 0 && prevIndex !== newIndex) return 'swap';
		return 'stay';
	}

	export function updateOrder(items: GlideItem[]) {
		previousOrder = items.map((i) => i.id);
	}
</script>

<script context="module">
	// Forward declaration slot-based API
</script>

{#if !readonly}
	<div class="glide-layer" style="--glide-duration: {animationDuration}ms;">
		{#if context}
			{#each context.items as item, index (item.id)}
				{@const dir = itemDirection(item.id)}
				<div
					class="glide-row"
					class:glide-enter={dir === 'enter'}
					class:glide-exit={dir === 'exit'}
					class:glide-swap={dir === 'swap'}
					style="--glide-index: {index};"
					role="listitem"
				>
					<slot {item} {index} direction={dir} />
				</div>
			{/each}
		{:else}
			<slot />
		{/if}
	</div>
{:else}
	<div class="glide-layer-static">
		<slot />
	</div>
{/if}

<style>
	/* ── Static (readonly) ── */

	.glide-layer-static {
		display: contents;
	}

	/* ── Animated layer ── */

	.glide-layer {
		display: contents;
	}

	.glide-row {
		--glide-duration: 300ms;
		transition:
			transform var(--glide-duration) cubic-bezier(0.22, 0.61, 0.36, 1),
			opacity var(--glide-duration) cubic-bezier(0.22, 0.61, 0.36, 1),
			max-height var(--glide-duration) cubic-bezier(0.22, 0.61, 0.36, 1),
			margin var(--glide-duration) cubic-bezier(0.22, 0.61, 0.36, 1),
			padding var(--glide-duration) cubic-bezier(0.22, 0.61, 0.36, 1);
	}

	/* ── Enter animation ── */

	.glide-enter {
		animation: glideEnter var(--glide-duration) cubic-bezier(0.22, 0.61, 0.36, 1) forwards;
	}

	@keyframes glideEnter {
		from {
			opacity: 0;
			transform: translateY(-12px) scale(0.96);
		}
		to {
			opacity: 1;
			transform: translateY(0) scale(1);
		}
	}

	/* ── Exit animation ── */

	.glide-exit {
		animation: glideExit var(--glide-duration) cubic-bezier(0.22, 0.61, 0.36, 1) forwards;
	}

	@keyframes glideExit {
		from {
			opacity: 1;
			transform: translateY(0) scale(1);
		}
		to {
			opacity: 0;
			transform: translateY(8px) scale(0.96);
		}
	}

	/* ── Swap (reorder) animation ── */

	.glide-swap {
		animation: glideSwap var(--glide-duration) cubic-bezier(0.22, 0.61, 0.36, 1) forwards;
	}

	@keyframes glideSwap {
		from {
			transform: scale(0.97);
			opacity: 0.7;
		}
		to {
			transform: scale(1);
			opacity: 1;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.glide-row {
			animation: none !important;
			transition: none !important;
		}
	}
</style>
