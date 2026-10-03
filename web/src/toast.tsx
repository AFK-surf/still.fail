import { Toast } from "radix-ui";
import { createContext, useCallback, useContext, useState, type ReactNode } from "react";
import * as css from "./toast.css.ts";
import { t } from "./i18n.ts";

const ToastContext = createContext<(message: string) => void>(() => {});

/**
 * What a toast says. A write its station did not answer may have been done (the core's `unconfirmed`, client/core-ts/src/
 * station/sync.ts): said as not known, whatever the page put before it ("没能固定：不确定做没做成：…" → "固定：不确定做没做成：…").
 */
export function said(message: string): string {
  return message.replace(/^没能([^：]*)：(不确定做没做成：)/, "$1：$2");
}

/** A short confirmation at the bottom of the screen, named after the action that happened. */
export function ToastProvider({ children }: { children: ReactNode }) {
  const [toast, setToast] = useState<{ id: number; message: string } | null>(null);
  const show = useCallback((message: string) => setToast({ id: Date.now(), message: said(message) }), []);
  return (
    <ToastContext.Provider value={show}>
      <Toast.Provider duration={2600} swipeDirection="down">
        {children}
        {toast && (
          <Toast.Root key={toast.id} className={css.toast} onOpenChange={(open) => { if (!open) setToast(null); }}>
            <Toast.Title>{toast.message}</Toast.Title>
          </Toast.Root>
        )}
        <Toast.Viewport className={css.toastViewport} />
      </Toast.Provider>
    </ToastContext.Provider>
  );
}

export function useToast(): (message: string) => void {
  return useContext(ToastContext);
}

/** Where `useToast` shows below it: the phone's own toast, in place of this one. */
export function ToastTo({ show, children }: { show: (message: string) => void; children: ReactNode }) {
  return <ToastContext.Provider value={show}>{children}</ToastContext.Provider>;
}

/** Why a call failed, in words. */
export function failure(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

/**
 * Lets what a person did go on by itself, and says how it ended: `没能<what>：<why>` when it failed, `done` (if any)
 * when it went through. `what` is said after "Couldn't" in English: a verb phrase, lowercase ("pin the chat"). What it does shows while under way where it is (doing.ts); this says only how it ended.
 */
export function useAct(): (doing: Promise<unknown>, what: string, done?: string) => void {
  const toast = useToast();
  return useCallback((doing, what, done) => {
    doing.then(() => { if (done) toast(done); }, (e) => toast(t((e as { code?: unknown } | null)?.code === "unconfirmed" ? "web-main.act.unconfirmed" : "web-main.act.failed", { what, error: failure(e) })));
  }, [toast]);
}
