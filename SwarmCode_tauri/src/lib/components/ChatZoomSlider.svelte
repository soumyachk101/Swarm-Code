<script lang="ts">
	// ---------------------------------------------------------------------------
	// ChatZoomSlider – inline zoom control in the chrome row.
	// Matches Swift ChatZoomSlider.swift.
	// ---------------------------------------------------------------------------

	interface Props {
		zoom: number;
		onChange: (zoom: number) => void;
	}

	let { zoom = 1.0, onChange }: Props = $props();

	const zoomLevels = [0.85, 0.925, 1.0, 1.1, 1.25];
	const currentIndex = $derived(Math.max(0, zoomLevels.findIndex(z => z >= zoom)));

	function step(dir: -1 | 1) {
		const next = Math.max(0, Math.min(zoomLevels.length - 1, currentIndex + dir));
		onChange(zoomLevels[next]);
	}
</script>

<div class="zoom-slider" role="slider" aria-label="Chat zoom" aria-valuenow={zoom}>
	<button class="zoom-btn" onclick={() => step(-1)} disabled={currentIndex === 0} title="Zoom out">
		<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
			<circle cx="11" cy="11" r="7"/>
			<line x1="21" y1="21" x2="16.65" y2="16.65"/>
			<line x1="8" y1="11" x2="14" y2="11"/>
		</svg>
	</button>
	<div class="zoom-track">
		<div class="zoom-fill" style="width: {(currentIndex / (zoomLevels.length - 1)) * 100}%"></div>
	</div>
	<button class="zoom-btn" onclick={() => step(1)} disabled={currentIndex === zoomLevels.length - 1} title="Zoom in">
		<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5">
			<circle cx="11" cy="11" r="7"/>
			<line x1="21" y1="21" x2="16.65" y2="16.65"/>
			<line x1="11" y1="8" x2="11" y2="14"/>
			<line x1="8" y1="11" x2="14" y2="11"/>
		</svg>
	</button>
</div>

<style>
	.zoom-slider {
		display: inline-flex;
		align-items: center;
		gap: 4px;
	}

	.zoom-btn {
		display: inline-flex;
		align-items: center;
		justify-content: center;
		width: 20px;
		height: 20px;
		border: none;
		background: transparent;
		color: var(--text-tertiary);
		border-radius: 4px;
		cursor: pointer;
		padding: 0;
		transition: all 0.15s;
	}

	.zoom-btn:hover:not(:disabled) {
		background: var(--surface-3);
		color: var(--text-primary);
	}

	.zoom-btn:disabled {
		opacity: 0.2;
		cursor: not-allowed;
	}

	.zoom-track {
		width: 48px;
		height: 4px;
		border-radius: 2px;
		background: var(--surface-4);
		overflow: hidden;
		position: relative;
	}

	.zoom-fill {
		position: absolute;
		top: 0;
		left: 0;
		height: 100%;
		background: var(--accent);
		border-radius: 2px;
		transition: width 0.15s ease;
	}
</style>
