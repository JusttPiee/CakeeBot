import { motion } from "motion/react";
import type { ReactNode } from "react";
import { detailPanel, detailSection } from "../motion/presets";
import styles from "./DetailPanel.module.css";

/**
 * The animated box for one selected item (a person's note, an event...).
 * It slides in, and each <DetailSection> inside it follows a moment later (the "stagger").
 * Render it only once the item's data is there: the animation plays when it first appears.
 */
export function DetailPanel({ children }: { children: ReactNode }) {
  return (
    <motion.div className={styles.panel} variants={detailPanel} initial="hidden" animate="shown">
      {children}
    </motion.div>
  );
}

interface DetailSectionProps {
  /** An optional heading above the section. */
  title?: string;
  children: ReactNode;
}

/** One block of a DetailPanel. It takes its animation from the panel around it. */
export function DetailSection({ title, children }: DetailSectionProps) {
  return (
    <motion.section className={styles.section} variants={detailSection}>
      {title && <h2>{title}</h2>}
      {children}
    </motion.section>
  );
}
