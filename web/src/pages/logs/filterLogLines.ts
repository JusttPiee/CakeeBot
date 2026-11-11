// Deciding which log lines to show. A "pure" function: the same input always gives the same output,
// and it touches nothing else. That makes it easy to test without rendering anything.
import type { LogLine } from "../../api/types";

export interface LogFilter {
  kind: "all" | "chat" | "system";
  /** Only chat from this server. null = every server. System lines belong to no server and always pass. */
  serverName: string | null;
  /** Only lines that contain this text (in the place or the message), upper or lower case. */
  text: string;
}

export function filterLogLines(lines: LogLine[], filter: LogFilter): LogLine[] {
  const wanted = filter.text.trim().toLowerCase();
  return lines.filter((line) => {
    if (filter.kind !== "all" && line.kind !== filter.kind) return false;
    if (filter.serverName !== null && line.kind === "chat" && !isFromServer(line, filter.serverName)) return false;
    if (wanted !== "" && !`${line.place} ${line.text}`.toLowerCase().includes(wanted)) return false;
    return true;
  });
}

// A chat line's place is "Server name #channel". The " #" keeps "Test Server" from matching "Test Server 2".
function isFromServer(line: LogLine, serverName: string): boolean {
  return line.place.startsWith(`${serverName} #`);
}
