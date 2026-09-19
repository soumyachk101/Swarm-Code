<script lang="ts">
	// ---------------------------------------------------------------------------
	// PaneTopVeil – fades the timeline behind the chrome row area.
	// Matches Swift PaneTopVeil.swift.
	// ---------------------------------------------------------------------------
</script>

<div class="pane-top-veil" aria-hidden="true"></div>

<style>
	.pane-top-veil {
		position: absolute;
		top: 0;
		left: 0;
		right: 0;
		height: 70px;
		background: linear-gradient(to bottom, var(--surface-1), transparent);
		pointer-events: none;
		z-index: 2;
	}
</style>
