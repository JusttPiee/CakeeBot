import { useState } from "react";
import { deleteSummary, listSummaries } from "../../api/memory";
import type { ChannelSummary } from "../../api/types";
import { ConfirmButton } from "../../components/ConfirmButton";
import { DetailPanel, DetailSection } from "../../components/DetailPanel";
import { ListDetail } from "../../components/ListDetail";
import { LoadProblem } from "../../components/LoadProblem";
import { useToast } from "../../components/Toast";
import { useApi } from "../../hooks/useApi";
import { useT } from "../../i18n/LanguageContext";
import { errorMessage } from "../../utils/errorMessage";
import styles from "./MemoryPage.module.css";

/**
 * The Channels tab: the rolling summary Cake keeps of each AI channel.
 * Read-only, because Cake rewrites a summary every time old messages drop out of its chat memory.
 * Deleting one makes Cake forget the older part of that channel's conversation.
 */
export function SummariesTab({ serverId }: { serverId: string }) {
  const t = useT();
  const toast = useToast();
  const summaries = useApi(() => listSummaries(serverId), [serverId]);
  const [selectedId, setSelectedId] = useState<string | null>(null);

  if (summaries.error && !summaries.data) return <LoadProblem error={summaries.error} onRetry={summaries.reload} />;
  if (!summaries.data) return <p className="muted">{t("common.loading")}</p>;

  const selected = summaries.data.find((summary) => summary.channel_id === selectedId) ?? null;

  // "# general", or "Channel 123" when the channel was deleted on Discord
  const nameOf = (summary: ChannelSummary) =>
    summary.channel_name ? `# ${summary.channel_name}` : t("memory.summaries.unknownChannel", { id: summary.channel_id });

  const remove = async (summary: ChannelSummary) => {
    try {
      await deleteSummary(serverId, summary.channel_id);
      toast(t("common.deleted"));
      setSelectedId(null);
      summaries.reload();
    } catch (error) {
      toast(t("common.failed", { message: errorMessage(error) }), "error");
    }
  };

  const renderSummary = (summary: ChannelSummary) => (
    <>
      <div className={styles.rowTitle}>{nameOf(summary)}</div>
      <div className={styles.rowText}>{t("memory.summaries.updated", { time: summary.updated })}</div>
    </>
  );

  return (
    <ListDetail
      items={summaries.data}
      getKey={(summary) => summary.channel_id}
      renderItem={renderSummary}
      selectedKey={selectedId}
      onSelect={setSelectedId}
      emptyText={t("memory.summaries.empty")}
      detail={
        selected === null ? null : (
          <DetailPanel key={selected.channel_id}>
            <DetailSection>
              <h1>{nameOf(selected)}</h1>
              <p className="muted">{t("memory.summaries.updated", { time: selected.updated })}</p>
            </DetailSection>
            <DetailSection>
              <p className={styles.readOnlyText}>{selected.text}</p>
              <p className="help">{t("memory.summaries.readOnly")}</p>
            </DetailSection>
            <DetailSection>
              <div className="actions">
                <ConfirmButton
                  label={t("memory.summaries.delete")}
                  confirmLabel={t("memory.summaries.deleteConfirm")}
                  onConfirm={() => void remove(selected)}
                  danger
                />
              </div>
            </DetailSection>
          </DetailPanel>
        )
      }
    />
  );
}
