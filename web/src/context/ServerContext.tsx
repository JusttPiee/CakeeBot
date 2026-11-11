import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from "react";
import type { ServerInfo } from "../api/types";
import { useStatus } from "./StatusContext";

const SERVER_KEY = "cake.server";

interface ServerContextValue {
  /** The server picked in the sidebar. null only when the bot is in no server at all. */
  server: ServerInfo | null;
  servers: ServerInfo[];
  selectServer: (id: string) => void;
}

const ServerContext = createContext<ServerContextValue | null>(null);

function savedServerId(): string | null {
  try {
    return localStorage.getItem(SERVER_KEY);
  } catch {
    return null;
  }
}

/** Remembers which Discord server the Memory and AI channels pages are showing. */
export function ServerProvider({ children }: { children: ReactNode }) {
  const { status } = useStatus();
  const [selectedId, setSelectedId] = useState<string | null>(savedServerId);

  const selectServer = useCallback((id: string) => {
    setSelectedId(id);
    try {
      localStorage.setItem(SERVER_KEY, id);
    } catch {
      // Storage is blocked: the choice just lasts until the page is closed.
    }
  }, []);

  const value = useMemo(() => {
    const servers = status?.servers ?? [];
    // The remembered server, or the first one if the bot has left it since.
    const server = servers.find((candidate) => candidate.id === selectedId) ?? servers[0] ?? null;
    return { server, servers, selectServer };
  }, [status, selectedId, selectServer]);

  return <ServerContext.Provider value={value}>{children}</ServerContext.Provider>;
}

export function useServer(): ServerContextValue {
  const value = useContext(ServerContext);
  if (value === null) throw new Error("useServer must be used inside <ServerProvider>");
  return value;
}
