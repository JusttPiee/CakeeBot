// Volume levels, as Ruby sends them: a whole number from 0 (silent) to 100 (the original loudness).

// Keeps a volume between 0 and 100, rounded to a whole number.
// Anything that is not a number (missing, text...) gives `fallback` instead.
export function clampVolume(value, fallback = 50) {
  const number = Number(value);
  if (value === undefined || value === null || Number.isNaN(number)) return fallback;
  return Math.round(Math.min(100, Math.max(0, number)));
}

// The multiplier @discordjs/voice uses: 50 -> 0.5 (half as loud), 100 -> 1 (unchanged).
export function volumeGain(volume) {
  return volume / 100;
}
