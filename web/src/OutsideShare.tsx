// A message that refers (`@`) to chats of the viewer's other workspaces (docs/chat-share.md): before it goes, the
// viewer is asked to share them with the workspace it is written in, so its agents can read them; shared (the core's
// `chat.xshareAdd`), it is sent. What it refers to is the core's to tell (`chat.outsideRefs`), the asking the pages'.
import { useEffect, useState, type ReactNode } from "react";
import { core } from "./core/react.ts";
import { scopeOf } from "./station.tsx";
import { Button, Dialog } from "./ui.tsx";
import { failure } from "@stillfail/ui/toast.tsx";
import * as css from "./ChatRef.css.ts";
import { t } from "./i18n.ts";

/** A chat of another workspace a message refers to, not shared with the one it is written in yet. */
export type Outside = { station: string; id: string; title: string; workspace: string; workspaceName: string; may: boolean };

/** The chats of other workspaces `text`, written on `station`, refers to and would share. */
export async function outsideOf(station: string, text: string): Promise<Outside[]> {
  if (!text.includes("@[") || !station.includes("/")) return [];
  const answer = (await core().call("chat.outsideRefs", { station, text })) as { chats?: Outside[] };
  return answer.chats ?? [];
}

/** Shares those the viewer may share with the workspace of `station` (the one written on, told first). */
export function shareOutside(chats: Outside[], station: string): Promise<unknown> {
  return Promise.all(chats.filter((c) => c.may).map((c) => core().call("chat.xshareAdd", { station: c.station, id: c.id, workspace: scopeOf(station), prefer: station })));
}

/** The chats asked about, each with whose it is, and those the viewer may not share said so. */
export function OutsideList({ chats }: { chats: Outside[] }) {
  return (
    <ul className={css.outsideList}>
      {chats.map((c) => (
        <li key={`${c.station}\t${c.id}`} className={css.outsideItem}>
          <span className={css.refChip}><span className={css.refChipHash}>@</span>{c.title}</span>
          <span className={css.refChipStation}>{t("web-main.outside.from", { name: c.workspaceName })}</span>
          {!c.may && <span className={css.outsideCannot}>{t("web-main.outside.cannot")}</span>}
        </li>
      ))}
    </ul>
  );
}

/**
 * The wide screen's asking: `ask(station, text)` answers whether to send (true at once when nothing needs sharing;
 * otherwise once the dialog's chats are shared, or the viewer sends anyway), the dialog `node` to place.
 */
export function useOutsideShare(): { ask(station: string, text: string): Promise<boolean>; node: ReactNode } {
  const [asking, setAsking] = useState<{ station: string; chats: Outside[]; answer(go: boolean): void } | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const ask = async (station: string, text: string) => {
    let chats: Outside[];
    try {
      chats = await outsideOf(station, text);
    } catch {
      chats = [];
    }
    if (chats.length === 0) return true;
    setError(null);
    return new Promise<boolean>((answer) => setAsking({ station, chats, answer }));
  };
  const close = (go: boolean) => {
    asking?.answer(go);
    setAsking(null);
    setBusy(false);
  };
  const sharable = asking?.chats.some((c) => c.may) ?? false;
  const confirm = async () => {
    if (!asking || busy) return;
    if (!sharable) return close(true);
    setBusy(true);
    try {
      await shareOutside(asking.chats, asking.station);
      close(true);
    } catch (e) {
      setBusy(false);
      setError(t("web-main.outside.failed", { error: failure(e) }));
    }
  };
  // Enter sent it, so Enter again says yes.
  useEffect(() => {
    if (!asking) return;
    const key = (e: KeyboardEvent) => {
      if (e.key === "Enter" && !e.isComposing && !e.shiftKey) {
        e.preventDefault();
        void confirm();
      }
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  });
  const node = asking && (
    <Dialog open onClose={() => close(false)} title={t("web-main.outside.title")} description={t("web-main.outside.lead")}
      footer={<>
        <Button variant="ghost" onClick={() => close(false)}>{t("common.cancel")}</Button>
        <Button variant="primary" busy={busy} onClick={() => void confirm()}>{sharable ? t("web-main.outside.share") : t("web-main.outside.anyway")}</Button>
      </>}>
      <OutsideList chats={asking.chats} />
      {error && <p className={css.outsideCannot} role="alert">{error}</p>}
    </Dialog>
  );
  return { ask, node };
}
