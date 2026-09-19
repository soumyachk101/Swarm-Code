<script lang="ts">
	// ---------------------------------------------------------------------------
	// PanelDragState – tracks pointer travel during a drag.
	// Matches Swift PanelDragState: position, velocity, flick on release.
	// ---------------------------------------------------------------------------

	export interface PanelDrag {
		/** Current position in pane coords, null at rest */
		position: { x: number; y: number } | null;
		/** Where the grab started */
		grab: { x: number; y: number } | null;
		/** Smoothed velocity (px/s) */
		vx: number;
		vy: number;
		lastMoveTime: number;
	}

	export function createDrag(): PanelDrag {
		return {
			position: null,
			grab: null,
			vx: 0,
			vy: 0,
			lastMoveTime: 0
		};
	}

	/** Smoothing factor for velocity (matches Swift 0.4/0.6 split) */
	const VELOCITY_SMOOTH = 0.4;
	const VELOCITY_INSTANT = 0.6;
	const FLICK_CARRY = 0.12; // seconds
	const REST_BEFORE_DROP = 0.08; // seconds

	export function dragMove(
		drag: PanelDrag,
		translation: { x: number; y: number },
		rest: { x: number; y: number },
		now: number
	): { x: number; y: number } {
		const start = drag.grab ?? rest;
		drag.grab = { ...start };
		const next = {
			x: start.x + translation.x,
			y: start.y + translation.y
		};

		if (drag.position) {
			const elapsed = (now - drag.lastMoveTime) / 1000;
			if (elapsed >= 0.004) {
				const instantX = (next.x - drag.position.x) / elapsed;
				const instantY = (next.y - drag.position.y) / elapsed;
				drag.vx = drag.vx * VELOCITY_SMOOTH + instantX * VELOCITY_INSTANT;
				drag.vy = drag.vy * VELOCITY_SMOOTH + instantY * VELOCITY_INSTANT;
			}
		} else {
			drag.vx = 0;
			drag.vy = 0;
		}

		drag.lastMoveTime = now;
		drag.position = next;
		return next;
	}

	export function dragRelease(drag: PanelDrag, now: number): { x: number; y: number } | null {
		const pos = drag.position;
		const elapsed = (now - drag.lastMoveTime) / 1000;

		drag.position = null;
		drag.grab = null;
		drag.vx = 0;
		drag.vy = 0;

		if (!pos) return null;
		if (elapsed >= REST_BEFORE_DROP) return pos;

		return {
			x: pos.x + drag.vx * FLICK_CARRY,
			y: pos.y + drag.vy * FLICK_CARRY
		};
	}

	// ---------------------------------------------------------------------------
	// PanelScene – computes dock positions and reserves for floating panels.
	// ---------------------------------------------------------------------------

	export interface PanelLayout {
		paneWidth: number;
		paneHeight: number;
		composerHeight: number;
		chromeHeight: number;
	}

	export const PANEL_WIDTH = 400;
	export const PANEL_MIN_WIDTH = 300;
	export const PANEL_GAP = 12;
	export const PANEL_SIDE_MARGIN = 20;
	export const PANEL_BOTTOM_MARGIN = 14;
	export const MIN_COMPOSER_WIDTH = 360;

	export function panelWidth(layout: PanelLayout): number {
		return Math.min(PANEL_WIDTH, Math.max(PANEL_MIN_WIDTH, layout.paneWidth - 2 * PANEL_SIDE_MARGIN));
	}

	export function sitsBesideComposer(layout: PanelLayout): boolean {
		const pw = panelWidth(layout);
		return layout.paneWidth - 2 * PANEL_SIDE_MARGIN - pw - PANEL_GAP >= MIN_COMPOSER_WIDTH;
	}

	export function composerReserve(layout: PanelLayout): number {
		return sitsBesideComposer(layout) ? panelWidth(layout) + PANEL_GAP : 0;
	}

	export function verticalRoom(layout: PanelLayout): number {
		return layout.paneHeight - layout.chromeHeight - (sitsBesideComposer(layout) ? PANEL_BOTTOM_MARGIN : layout.composerHeight + PANEL_GAP);
	}

	/** Docked position for a panel in a given corner */
	export function dockedPosition(corner: 'top-leading' | 'top-trailing' | 'bottom-leading' | 'bottom-trailing', layout: PanelLayout): { x: number; y: number } {
		const pw = panelWidth(layout);
		const isLeading = corner.includes('leading');
		const isTop = corner.includes('top');
		const vr = verticalRoom(layout);

		const x = isLeading ? PANEL_SIDE_MARGIN : layout.paneWidth - pw - PANEL_SIDE_MARGIN;
		const y = isTop ? 8 : Math.max(8, layout.paneHeight - 260 - 8); // 260 = approximate panel height

		return { x, y };
	}

	/** Clamp a position so the panel stays within the pane */
	export function clampPosition(pos: { x: number; y: number }, layout: PanelLayout): { x: number; y: number } {
		const pw = panelWidth(layout);
		const ph = 260;
		const vr = verticalRoom(layout);

		return {
			x: Math.max(0, Math.min(layout.paneWidth - pw, pos.x)),
			y: Math.max(0, Math.min(layout.paneHeight - ph, pos.y))
		};
	}

	/** Which corner is the panel closest to (for snap-back) */
	export function nearestCorner(pos: { x: number; y: number }, layout: PanelLayout): 'top-leading' | 'top-trailing' | 'bottom-leading' | 'bottom-trailing' {
		const pw = panelWidth(layout);
		const ph = 260;
		const midX = layout.paneWidth / 2;
		const midY = layout.paneHeight / 2;

		const isLeft = pos.x + pw / 2 < midX;
		const isTop = pos.y + ph / 2 < midY;

		if (isTop && isLeft) return 'top-leading';
		if (isTop && !isLeft) return 'top-trailing';
		if (!isTop && isLeft) return 'bottom-leading';
		return 'bottom-trailing';
	}
</script>
