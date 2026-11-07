import { Toast } from "radix-ui";
import { createContext, useCallback, useContext, useState, type ReactNode } from "preact/compat";
import * as css from "./toast.css.ts";
import { Words, type WordsDrawn } from "./words.tsx";

/** Shows a toast; `words`: how its words are drawn where it was asked for (./words.tsx). */
type Show = (message: string, words?: WordsDrawn) => void;

const ToastContext = createContext<Show>(() => {});

/**
 * What a toast says. A write its station did not answer may have been done (the core's `unconfirmed`, client/core-ts/src/
 * station/sync.ts): said as not known, whatever the page put before it ("没能固定：不确定做没做成：…" → "固定：不确定做没做成：…").
 */
export function said(message: string): string {
  return message.replace(/^(?:没能|无法)([^：]*)：((?:不确定做没做成|无法确认是否成功)：)/, "$1：$2");
}

/** A short confirmation at the bottom of the screen, named after the action that happened. */
export function ToastProvider({ children }: { children: ReactNode }) {
  const [toast, setToast] = useState<{ id: number; message: string; words: WordsDrawn | undefined } | null>(null);
  const show = useCallback<Show>((message, words) => setToast({ id: Date.now(), message: said(message), words }), []);
  return (
    <ToastContext.Provider value={show}>
      <Toast.Provider duration={2600} swipeDirection="down">
        {children}
        {toast && (
          <Toast.Root key={toast.id} className={css.toast} onOpenChange={(open) => { if (!open) setToast(null); }}>
            <Toast.Title>{toast.words ? <toast.words text={toast.message} /> : toast.message}</Toast.Title>
          </Toast.Root>
        )}
        <Toast.Viewport className={css.toastViewport} />
      </Toast.Provider>
    </ToastContext.Provider>
  );
}

export function useToast(): (message: string) => void {
  const show = useContext(ToastContext);
  const words = useContext(Words);
  return useCallback((message: string) => show(message, words), [show, words]);
}

/** Why a call failed, in words. */
export function failure(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}
