import { useState } from "react";
import { listChannels, setChannelAi } from "../api/channels";
import type { ChannelInfo } from "../api/types";
import { EmptyState } from "../components/EmptyState";
import { LoadProblem } from "../components/LoadProblem";
import { SearchBox } from "../components/SearchBox";
import { useToast } from "../components/Toast";
import { Toggle } from "../components/Toggle";
import { useServer } from "../context/ServerContext";
import { useApi } from "../hooks/useApi";
import { useT } from "../i18n/LanguageContext";
import { errorMessage } from "../utils/errorMessage";
import styles from "./ChannelsPage.module.css";

/** The AI channels page: one switch per text channel of the picked server. */
export function ChannelsPage() {
  const t = useT();
  const { server } = useServer();
  if (server === null) return <EmptyState text={t("server.none")} />;

  return (
    <>
      <h1>
        {t("channels.title")} · {server.name}
      </h1>
      <p className="muted">{t("channels.intro")}</p>
      <ChannelList key={server.id} serverId={server.id} />
    </>
  );
}

/**
 * The list of switches. A click is shown at once and sent to the bot in the background
 * (an "optimistic update"): if the bot refuses, the switch goes back and a message explains why.
 */
export function ChannelList({ serverId }: { serverId: string }) {
  const t = useT();
  const toast = useToast();
  const channels = useApi(() => listChannels(serverId), [serverId]);
  const [search, setSearch] = useState("");
  // Switches that were clicked and are waiting for the bot: channel id => the state we are showing meanwhile
  const [waiting, setWaiting] = useState<Record<string, boolean>>({});
  // Switches the bot has agreed to since the list was loaded: channel id => the new state
  const [agreed, setAgreed] = useState<Record<string, boolean>>({});

  if (channels.error && !channels.data) return <LoadProblem error={channels.error} onRetry={channels.reload} />;
  if (!channels.data) return <p className="muted">{t("common.loading")}</p>;

  const isOn = (channel: ChannelInfo) => waiting[channel.id] ?? agreed[channel.id] ?? channel.ai_on;
  const stopWaiting = (channelId: string) =>
    setWaiting((current) => Object.fromEntries(Object.entries(current).filter(([id]) => id !== channelId)));

  const switchAi = async (channel: ChannelInfo, on: boolean) => {
    setWaiting((current) => ({ ...current, [channel.id]: on })); // show it right away
    try {
      await setChannelAi(serverId, channel.id, on);
      setAgreed((current) => ({ ...current, [channel.id]: on }));
    } catch (error) {
      toast(t("common.failed", { message: errorMessage(error) }), "error");
    } finally {
      stopWaiting(channel.id); // on failure this puts the switch back to what the bot has
    }
  };

  const wanted = search.trim().toLowerCase();
  const shown = channels.data.filter((channel) => channel.name.toLowerCase().includes(wanted));
  const onCount = channels.data.filter(isOn).length;

  return (
    <>
      <div className={styles.toolbar}>
        <SearchBox value={search} onChange={setSearch} placeholder={t("channels.search")} />
        <span className="muted">{t("channels.count", { count: onCount })}</span>
      </div>

      {shown.length === 0 && (
        <EmptyState text={t(channels.data.length === 0 ? "channels.empty" : "channels.noMatch")} />
      )}
      <ul className={styles.list}>
        {shown.map((channel) => (
          <li key={channel.id} className={`${styles.channel} ${channel.readable ? "" : styles.unreadable}`}>
            <span className={styles.name}>
              <span className={styles.hash}>#</span>
              {channel.name}
            </span>
            {!channel.readable && <span className="help">{t("channels.unreadable")}</span>}
            {isOn(channel) && <span className={styles.on}>{t("channels.on")}</span>}
            <Toggle
              checked={isOn(channel)}
              onChange={(on) => void switchAi(channel, on)}
              label={t("channels.toggle", { name: channel.name })}
              disabled={!channel.readable || channel.id in waiting}
            />
          </li>
        ))}
      </ul>
    </>
  );
}
