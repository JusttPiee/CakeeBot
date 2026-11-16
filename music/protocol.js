// The "protocol" is how Ruby and this program talk: one JSON object per line.
// Ruby writes commands to our stdin, we write events to our stdout.

const KNOWN_OPS = ["join", "play", "pause", "resume", "stop", "leave", "volume"];

// Turns one line of text from Ruby into a command object.
// Returns null when the line is not valid JSON, has an unknown op, or has no guild.
export function parseCommandLine(line) {
  let data;
  try {
    data = JSON.parse(line);
  } catch {
    return null;
  }
  if (data === null || typeof data !== "object") return null;
  if (!KNOWN_OPS.includes(data.op)) return null;
  if (typeof data.guild !== "string" || data.guild === "") return null;
  return data;
}

// Builds the text for one event: JSON followed by a newline.
export function eventLine(name, fields = {}) {
  return JSON.stringify({ event: name, ...fields }) + "\n";
}

// Sends one event to Ruby.
// stdout is ONLY for protocol lines (Ruby reads every line as JSON),
// so anything else we want to print must go through log() below.
export function sendEvent(name, fields = {}) {
  process.stdout.write(eventLine(name, fields));
}

// Writes a debug message to stderr, which Ruby does not parse.
export function log(...parts) {
  console.error("[music]", ...parts);
}
