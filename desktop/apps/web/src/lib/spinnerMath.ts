/**
 * Staggered animation-delay values for the 3×3 WorkingSpinner grid.
 *
 * Rows pulse outward from the centre (row 0 → top, row 2 → bottom);
 * columns pulse left-to-right with a short horizontal spread.
 */

export function cellDelay(row: number, col: number): string {
  const rowOffset = (row - 1) * 0.12;  // -0.12, 0, +0.12
  const colOffset = col * 0.08;          // 0, 0.08, 0.16
  return `${(rowOffset + colOffset).toFixed(3)}s`;
}
