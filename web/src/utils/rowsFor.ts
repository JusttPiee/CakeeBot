const MIN_ROWS = 4;
const MAX_ROWS = 18;
const CHARACTERS_PER_ROW = 80; // a rough guess at how much text fits on one line of the box

/** How tall a text box should be to show its text without scrolling (within reason). */
export function rowsFor(text: string): number {
  const rows = text.split("\n").reduce((total, line) => total + Math.max(1, Math.ceil(line.length / CHARACTERS_PER_ROW)), 0);
  return Math.min(MAX_ROWS, Math.max(MIN_ROWS, rows + 1));
}
