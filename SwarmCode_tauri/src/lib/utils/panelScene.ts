// ---------------------------------------------------------------------------
// PanelDragState – tracks pointer travel during a drag.
// Matches Swift PanelDragState: position, velocity, flick on release.
// ---------------------------------------------------------------------------

export interface PanelDrag {
	position: { x: number; y: number } | null;
	grab: { x: number; y: number } | null;
	vx: number;
	vy: number;
	lastMoveTime: number;
}

export function createDrag(): PanelDrag {
	return { position: null, grab: null, vx: 0, vy: 0, lastMoveTime: 0 };
}

const VELOCITY_SMOOTH = 0.4;
const VELOCITY_INSTANT = 0.6;
const FLICK_CARRY = 0.12;
const REST_BEFORE_DROP = 0.08;

export function dragMove(
	drag: PanelDrag,
	dx: number,
	dy: number
): { x: number; y: number } {
	const start = drag.grab ?? drag.position ?? { x: 0, y: 0 };
	if (!drag.grab) drag.grab = { ...start };
	const next = { x: start.x + dx, y: start.y + dy };

	if (drag.position) {
		const elapsed = (performance.now() - drag.lastMoveTime) / 1000;
		if (elapsed >= 0.004) {
			const ix = (next.x - drag.position.x) / elapsed;
			const iy = (next.y - drag.position.y) / elapsed;
			drag.vx = drag.vx * VELOCITY_SMOOTH + ix * VELOCITY_INSTANT;
			drag.vy = drag.vy * VELOCITY_SMOOTH + iy * VELOCITY_INSTANT;
		}
	} else {
		drag.vx = 0;
		drag.vy = 0;
	}

	drag.lastMoveTime = performance.now();
	drag.position = next;
	return next;
}

export function dragRelease(drag: PanelDrag): { x: number; y: number } | null {
	const pos = drag.position;
	const elapsed = (performance.now() - drag.lastMoveTime) / 1000;

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
// PanelScene – computes dock positions, reserves, corner snapping
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

export function dockedPosition(corner: string, layout: PanelLayout): { x: number; y: number } {
	const pw = panelWidth(layout);
	const ph = 280;
	const isLeading = corner.includes('leading');
	const isTop = corner.includes('top');

	const x = isLeading ? PANEL_SIDE_MARGIN : layout.paneWidth - pw - PANEL_SIDE_MARGIN;
	const vr = verticalRoom(layout);
	const y = isTop ? 8 : Math.max(8, layout.paneHeight - ph - PANEL_BOTTOM_MARGIN);

	return { x, y };
}

export function clampPosition(pos: { x: number; y: number }, layout: PanelLayout): { x: number; y: number } {
	const pw = panelWidth(layout);
	const ph = 280;

	return {
		x: Math.max(0, Math.min(layout.paneWidth - pw, pos.x)),
		y: Math.max(0, Math.min(layout.paneHeight - ph, pos.y))
	};
}

export function nearestCorner(pos: { x: number; y: number }, layout: PanelLayout): string {
	const pw = panelWidth(layout);
	const ph = 280;
	const midX = layout.paneWidth / 2;
	const midY = layout.paneHeight / 2;

	const isLeft = pos.x + pw / 2 < midX;
	const isTop = pos.y + ph / 2 < midY;

	if (isTop && isLeft) return 'top-leading';
	if (isTop && !isLeft) return 'top-trailing';
	if (!isTop && isLeft) return 'bottom-leading';
	return 'bottom-trailing';
}
