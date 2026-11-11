// The app's animation style in one place: "lively", with a small bounce at the end.
// Components pass these to Motion's <motion.div variants={...}> instead of inventing their own numbers.
// People who turned on "reduce motion" get none of it (see <MotionConfig> in App.tsx).
import type { Variants } from "motion/react";

/** A curve that overshoots a little before settling: that is what reads as a bounce. */
export const EASE_BOUNCE = [0.34, 1.56, 0.64, 1] as const;
export const DETAIL_SECONDS = 0.35;
export const STAGGER_SECONDS = 0.05;

/** The panel on the right of a list: slides in from the right, and its children follow one by one. */
export const detailPanel: Variants = {
  hidden: { opacity: 0, x: 16 },
  shown: {
    opacity: 1,
    x: 0,
    transition: { duration: DETAIL_SECONDS, ease: EASE_BOUNCE, staggerChildren: STAGGER_SECONDS },
  },
};

/** A child of the panel above (one section of a form): rises into place. */
export const detailSection: Variants = {
  hidden: { opacity: 0, y: 6 },
  shown: { opacity: 1, y: 0, transition: { duration: DETAIL_SECONDS, ease: EASE_BOUNCE } },
};

/** A row that can appear and disappear (a fact, a toast): pops in, slides out. */
export const popRow: Variants = {
  hidden: { opacity: 0, y: 10, scale: 0.96 },
  shown: { opacity: 1, y: 0, scale: 1, transition: { duration: DETAIL_SECONDS, ease: EASE_BOUNCE } },
  gone: { opacity: 0, x: 24, transition: { duration: 0.2 } },
};
