import { AnimatePresence, motion } from "motion/react";
import { createContext, useCallback, useContext, useRef, useState, type ReactNode } from "react";
import { popRow } from "../motion/presets";
import styles from "./Toast.module.css";

type ToastKind = "ok" | "error";

interface ToastMessage {
  id: number;
  text: string;
  kind: ToastKind;
}

/** Show a short message in the corner of the screen. It goes away by itself. */
export type ShowToast = (text: string, kind?: ToastKind) => void;

const ToastContext = createContext<ShowToast | null>(null);

const VISIBLE_MS = 2500;
const VISIBLE_ERROR_MS = 5000; // errors stay longer: they need to be read

/** Wrap the app in this once (see App.tsx). Any component can then call useToast(). */
export function ToastProvider({ children }: { children: ReactNode }) {
  const [messages, setMessages] = useState<ToastMessage[]>([]);
  const nextId = useRef(1);

  const show = useCallback<ShowToast>((text, kind = "ok") => {
    const id = nextId.current++;
    setMessages((current) => [...current, { id, text, kind }]);
    setTimeout(
      () => setMessages((current) => current.filter((message) => message.id !== id)),
      kind === "error" ? VISIBLE_ERROR_MS : VISIBLE_MS,
    );
  }, []);

  return (
    <ToastContext.Provider value={show}>
      {children}
      <div className={styles.stack} aria-live="polite">
        {/* AnimatePresence lets a toast play its "gone" animation before it is removed from the page */}
        <AnimatePresence>
          {messages.map((message) => (
            <motion.div
              key={message.id}
              className={`${styles.toast} ${message.kind === "error" ? styles.error : ""}`}
              variants={popRow}
              initial="hidden"
              animate="shown"
              exit="gone"
            >
              {message.text}
            </motion.div>
          ))}
        </AnimatePresence>
      </div>
    </ToastContext.Provider>
  );
}

export function useToast(): ShowToast {
  const show = useContext(ToastContext);
  if (show === null) throw new Error("useToast must be used inside <ToastProvider>");
  return show;
}
