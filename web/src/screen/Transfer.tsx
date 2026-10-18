// What goes between a screen a person drives and this device (docs/remote-screens.md, "Clipboard and files"): a copy
// made on the screen put on this device's clipboard (at once where the browser lets it, else offered with a press), a
// paste here set on the screen's clipboard and pasted there (`screen.clipboard`), and files dropped on the screen (or
// picked) put on its machine with the drive's upload, where it says (`drop`): how each goes, where it went, its path to
// paste there and the machine's file manager to show it in.
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { core } from "../core/react.ts";
import type { ScreenDrop } from "../core/shapes.ts";
import { Close, File as FileIcon, Retry, Upload } from "@stillfail/ui/icons.tsx";
import { panelEdge } from "@stillfail/ui/styles/controls.css.ts";
import { PanelButton, PanelIconButton } from "../ui.tsx";
import { bytesOf } from "../api.ts";
import { cancel, retry, sizeOf, upload, useUploads, type Upload as Up } from "../drive/model.ts";
import { t } from "../i18n.ts";
import * as css from "./Transfer.css.ts";

/** A copy made on the screen: its text, or its picture. */
export type Clip = { text: string } | { png: Blob };

/** Puts a clip on this device's clipboard; fails where the browser will not (no focus, no gesture, no permission). */
export async function putClip(clip: Clip): Promise<void> {
  if ("text" in clip) return navigator.clipboard.writeText(clip.text);
  await navigator.clipboard.write([new ClipboardItem({ "image/png": clip.png })]);
}

/** A copy made on the screen as the core says it (`{clipboard}`, the PNG's bytes beside it); null when it is none. */
export function clipOf(value: { type?: string; text?: string } | undefined, bytes: Uint8Array | undefined): Clip | null {
  if (value?.type === "text" && typeof value.text === "string" && value.text !== "") return { text: value.text };
  if (value?.type === "png" && bytes && bytes.length > 0) return { png: new Blob([bytes as Uint8Array<ArrayBuffer>], { type: "image/png" }) };
  return null;
}

/** What a paste here sets on the screen's clipboard, of the types it carries (a PNG first, else text); null: none. */
export async function pasted(data: Pick<DataTransfer, "files" | "getData">, types: readonly string[]): Promise<{ text: string } | { png: Uint8Array } | null> {
  const png = types.includes("png") ? [...data.files].find((f) => f.type === "image/png") : undefined;
  if (png) return { png: await bytesOf(png) };
  const text = data.getData("text/plain");
  return text && types.includes("text") ? { text } : null;
}

/** A copy made on the screen this browser would not put on the clipboard by itself: offered, a press puts it there. */
export function CopiedNote({ clip, onDone }: { clip: Clip; onDone: (put: boolean) => void }) {
  const [failed, setFailed] = useState(false);
  const what = "text" in clip ? clip.text.replace(/\s+/g, " ").trim() : "";
  return (
    <div className={css.copied} role="status">
      <span className={css.copiedText}>
        {"text" in clip ? <><span className={css.copiedWhat}>{t("web-pages.screen.copiedText")}</span>{what}</> : t("web-pages.screen.copiedImage")}
      </span>
      <PanelButton tone="accent" onClick={() => { putClip(clip).then(() => onDone(true), () => setFailed(true)); }}>
        {failed ? t("web-pages.screen.copyAgain") : t("web-pages.screen.copyHere")}
      </PanelButton>
      <PanelIconButton label={t("common.close")} onClick={() => onDone(false)}><Close size={14} /></PanelIconButton>
    </div>
  );
}

/** A file sent to the screen's machine and there now: where. */
type Sent = { key: string; name: string; path: string };

/** Sending files to a screen's machine (where its `drop` says): those going, and those there, until put away. */
export function useSends(station: string, drop: ScreenDrop | undefined) {
  const folder = drop?.folder ?? null;
  const going = useUploads(station, folder, "");
  const [sent, setSent] = useState<Sent[]>([]);
  const keys = useRef(new Set<string>());
  const send = useCallback((files: File[]) => {
    if (folder === null || files.length === 0) return;
    for (const file of files) {
      const made = upload(station, folder, "", [file], {
        keepBoth: true,
        done: (name) => setSent((was) => [...was, { key: made[0] ?? name, name, path: joinFolder(folder, name) }]),
      });
      for (const k of made) keys.current.add(k);
    }
  }, [station, folder]);
  // Only those sent from here (another page's uploads into the same folder are its own).
  const mine = useMemo(() => going.filter((u) => keys.current.has(u.key)), [going]);
  const clear = useCallback(() => {
    for (const u of mine) if (u.state !== "sending") cancel(u.key);
    setSent([]);
  }, [mine]);
  return { going: mine, sent, send, clear };
}

/** A path on the machine of a file in its folder (macOS and Linux paths: `/`; Windows': `\`). */
export function joinFolder(folder: string, name: string): string {
  const sep = folder.includes("\\") && !folder.includes("/") ? "\\" : "/";
  return folder.endsWith(sep) ? folder + name : folder + sep + name;
}

/** The folder's name as a person reads it (its last component). */
export function folderName(folder: string): string {
  return folder.split(/[/\\]/).filter(Boolean).at(-1) ?? folder;
}

/** The files sent to the screen's machine: each as it goes, failed (again, or let go), or there (paste its path there,
 *  show it in the file manager). */
export function SendsPanel({ drop, going, sent, onPastePath, onReveal, onClose }: {
  drop: ScreenDrop;
  going: readonly Up[];
  sent: readonly Sent[];
  onPastePath: (path: string) => void;
  onReveal: (path: string) => void;
  onClose: () => void;
}) {
  const list = useRef<HTMLDivElement>(null);
  const count = going.length + sent.length;
  // The newest in sight.
  useEffect(() => { list.current?.scrollTo({ top: list.current.scrollHeight }); }, [count]);
  return (
    <div className={css.sends} role="region" aria-label={t("web-pages.screen.sends")}>
      <div className={`${css.sendsHead} ${panelEdge}`}>
        <span className={css.sendsTitle}>{t("web-pages.screen.sendsTo", { folder: folderName(drop.folder) })}</span>
        <PanelIconButton label={t("common.close")} onClick={onClose}><Close size={14} /></PanelIconButton>
      </div>
      <div ref={list} className={`${css.sendsList} ${panelEdge}`}>
        {sent.map((s) => (
          <div key={s.key} className={css.send}>
            <FileIcon size={18} strokeWidth={1.6} />
            <span className={css.sendWords}>
              <span className={css.sendName}>{s.name}</span>
              <span className={css.sendLine}><span className={css.sendPath} title={s.path}><bdi dir="ltr">{s.path}</bdi></span></span>
            </span>
            <span className={css.sendTools}>
              <PanelButton tone="accent" onClick={() => onPastePath(s.path)}>{t("web-pages.screen.pastePath")}</PanelButton>
              {drop.reveal && <PanelButton tone="quiet" onClick={() => onReveal(s.path)}>{t("web-pages.screen.reveal")}</PanelButton>}
            </span>
          </div>
        ))}
        {going.map((u) => (
          <div key={u.key} className={css.send}>
            <Upload size={18} strokeWidth={1.6} />
            <span className={css.sendWords}>
              <span className={css.sendName}>{u.name}</span>
              {u.state === "failed" ? <span className={css.sendLine}><span className={css.sendFailed} title={u.error}>{t("web-pages.drive.uploadFailed", { error: u.error ?? "" })}</span></span> : (
                <span className={css.sendLine}>
                  <span className={css.bar}><span style={{ transform: `scaleX(${u.size ? u.sent / u.size : 0})` }} /></span>
                  <span className={css.sizes}>{t("web-pages.drive.uploading", { sent: sizeOf(u.sent), size: sizeOf(u.size) })}</span>
                </span>
              )}
            </span>
            <span className={css.sendTools}>
              {u.state === "failed" && <PanelIconButton label={t("web-pages.drive.retry")} onClick={() => retry(u.key)}><Retry size={14} /></PanelIconButton>}
              <PanelIconButton label={t("common.cancel")} onClick={() => cancel(u.key)}><Close size={14} /></PanelIconButton>
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

/** A file dragged over the screen: where it will go. */
export function DropVeil({ title, drop }: { title: string; drop: ScreenDrop }) {
  return (
    <div className={css.veil} aria-hidden="true">
      <Upload size={24} />
      <span>{t("web-pages.screen.dropHere", { name: title })}</span>
      <span className={css.veilWhere}>{drop.folder}</span>
    </div>
  );
}
