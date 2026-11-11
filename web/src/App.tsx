import { MotionConfig } from "motion/react";
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import styles from "./App.module.css";
import { ConnectionBanner } from "./components/ConnectionBanner";
import { EmptyState } from "./components/EmptyState";
import { Sidebar } from "./components/Sidebar";
import { ToastProvider } from "./components/Toast";
import { ServerProvider } from "./context/ServerContext";
import { StatusProvider, useStatus } from "./context/StatusContext";
import { LanguageProvider, useT } from "./i18n/LanguageContext";
import { ChannelsPage } from "./pages/ChannelsPage";
import { ConfigPage } from "./pages/config/ConfigPage";
import { LogsPage } from "./pages/logs/LogsPage";
import { MemoryPage } from "./pages/memory/MemoryPage";
import { TokenNeededPage } from "./pages/TokenNeededPage";

/**
 * The whole app. The "providers" wrapped around it each share one thing with every component inside:
 * the language, the bot's status, the toast messages. <MotionConfig reducedMotion="user"> switches
 * the animations off for people who asked their system for less motion.
 */
export function App() {
  return (
    <LanguageProvider>
      <StatusProvider>
        <ToastProvider>
          <MotionConfig reducedMotion="user">
            <BrowserRouter>
              <Frame />
            </BrowserRouter>
          </MotionConfig>
        </ToastProvider>
      </StatusProvider>
    </LanguageProvider>
  );
}

// Decides what fills the window: the token page, a "connecting" line, or the real app.
function Frame() {
  const t = useT();
  const { status, needsToken, connection } = useStatus();

  if (needsToken) return <TokenNeededPage />;

  if (status === null) {
    // Nothing from the bot yet: either the very first answer is on its way, or the bot is off.
    return (
      <div className={styles.shell}>
        <div className={styles.main}>
          <ConnectionBanner />
          <EmptyState text={t(connection === "ok" ? "connection.connecting" : "connection.reconnecting")} />
        </div>
      </div>
    );
  }

  return (
    <ServerProvider>
      <div className={styles.shell}>
        <Sidebar />
        <div className={styles.main}>
          <ConnectionBanner />
          {/* While the bot is away the page stays visible, only dimmed: never a blank screen */}
          <main className={`${styles.page} ${connection === "ok" ? "" : styles.dimmed}`}>
            <Pages />
          </main>
        </div>
      </div>
    </ServerProvider>
  );
}

// Which page belongs to which address. React Router swaps them without reloading the browser page.
function Pages() {
  return (
    <Routes>
      <Route path="/memory/:tab" element={<MemoryPage />} />
      <Route path="/memory" element={<Navigate to="/memory/people" replace />} />
      <Route path="/channels" element={<ChannelsPage />} />
      <Route path="/config" element={<ConfigPage />} />
      <Route path="/logs" element={<LogsPage />} />
      <Route path="*" element={<Navigate to="/memory/people" replace />} />
    </Routes>
  );
}
