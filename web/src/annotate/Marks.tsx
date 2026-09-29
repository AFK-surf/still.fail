// Marking a web service's page in a preview beside a chat, for its agent: picking what on the page is meant (the
// preview's frame does the picking and the picture, frame.ts), saying something about each right where it is, then
// putting it all into the chat's draft: the whole page's screenshot with the marks numbered, and a quote per mark
// saying where it is. Each mark is a numbered pin on its element's corner, what is said about it in a frosted bubble
// beside the pin; they follow the page as it scrolls (the frame says where the marks are).
import { useCallback, useEffect, useRef, useState, type RefObject } from "react";
import { Close, Edit, Send, Trash } from "../icons.tsx";
import { offerToDraft, type DraftQuote } from "../draft.ts";
import type { Picked } from "./frame.ts";
import * as css from "./Marks.css.ts";
import * as pagesCss from "../styles/pages.css.ts";
import { Tip } from "../ui.tsx";

interface Mark { picked: Picked; comment: string }
interface Box { x: number; y: number; width: number; height: number }

type Said =
  | { event: "picked"; mark: Picked }
  | { event: "focus"; n: number }
  | { event: "at"; at: (Box & { n: number })[] }
  | { event: "off" | "reset" }
  | { event: "shot"; id: number; png?: ArrayBuffer; error?: string };

/**
 * The marks of the preview in `frame` (at `origin`, told apart by `nonce`), for the chat whose draft is `draftKey`.
 * `able`: its frame can (the frame said so). Gives the bar's button, what takes the address's place in the bar while
 * marking, and what shows over the page.
 */
export function useMarks({ frame, origin, nonce, name, draftKey, able }:
  { frame: RefObject<HTMLIFrameElement | null>; origin: string | null; nonce: string; name: string; draftKey: string | undefined; able: boolean }) {
  const [marking, setMarking] = useState(false);
  const [marks, setMarks] = useState<Mark[]>([]);
  const [at, setAt] = useState<Map<number, Box>>(new Map());
  const [editing, setEditing] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const shots = useRef(new Map<number, (said: { png?: ArrayBuffer; error?: string }) => void>());
  const shot = useRef(0);
  const on = able && draftKey !== undefined;
  // How wide the page is, for which side of a pin its bubble goes.
  const layer = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(Infinity);
  const shown = on && marks.length > 0;
  useEffect(() => {
    const el = layer.current;
    if (!el) return;
    const observer = new ResizeObserver(() => setWidth(el.clientWidth));
    observer.observe(el);
    return () => observer.disconnect();
  }, [shown]);

  const tell = useCallback((data: Record<string, unknown>) => {
    if (origin) frame.current?.contentWindow?.postMessage({ type: "ember-preview-annotate", ...data }, origin);
  }, [origin, frame]);

  useEffect(() => {
    if (!origin) return;
    const onMessage = (event: MessageEvent) => {
      if (event.origin !== origin || event.source !== frame.current?.contentWindow || event.data?.nonce !== nonce) return;
      if (event.data?.type !== "ember-preview-annotated") return;
      const said = event.data as Said;
      if (said.event === "picked") {
        setMarks((all) => [...all, { picked: said.mark, comment: "" }]);
        setAt((now) => new Map(now).set(said.mark.n, said.mark.rect));
        setEditing(said.mark.n);
        setError(null);
      } else if (said.event === "focus") setEditing(said.n);
      else if (said.event === "at") setAt(new Map(said.at.map(({ n, ...box }) => [n, box])));
      else if (said.event === "off") setMarking(false);
      else if (said.event === "reset") { setMarks([]); setEditing(null); }
      else if (said.event === "shot") {
        shots.current.get(said.id)?.(said);
        shots.current.delete(said.id);
      }
    };
    window.addEventListener("message", onMessage);
    return () => window.removeEventListener("message", onMessage);
  }, [origin, nonce, frame]);

  const mark = (value: boolean) => { setMarking(value); tell({ on: value }); };
  const remove = (n: number) => { setMarks((all) => all.filter((m) => m.picked.n !== n)); setEditing(null); tell({ remove: n }); };
  const leave = () => { setMarks([]); setEditing(null); setError(null); tell({ clear: true }); mark(false); };

  const send = async () => {
    if (!draftKey || !marks.length) return;
    setBusy(true);
    setError(null);
    setEditing(null);
    try {
      const id = ++shot.current;
      const got = await new Promise<{ png?: ArrayBuffer; error?: string }>((done) => {
        shots.current.set(id, done);
        tell({ capture: id });
      });
      if (!got.png) throw new Error(got.error ?? "没有截到图");
      const stamp = new Date().toTimeString().slice(0, 8).replaceAll(":", "");
      const file = new File([got.png], `${name}-标注-${stamp}.png`, { type: "image/png" });
      const quotes: DraftQuote[] = marks.map((m) => ({
        id: `mark-${nonce}-${stamp}-${m.picked.n}`, author: `网页 ${name} 标注 ${m.picked.n}`, role: "page", text: where(m.picked), comment: m.comment,
      }));
      if (!offerToDraft(draftKey, { files: [file], quotes })) throw new Error("这个对话现在不能发消息");
      leave();
    } catch (e) {
      setError(`没能放进对话：${e instanceof Error ? e.message : String(e)}`);
    } finally {
      setBusy(false);
    }
  };

  const button = on ? (
    <Tip label={marking ? "停止点选（Esc）" : "标注页面上的元素，发给 agent"}><button type="button" className={pagesCss.iconBtn} aria-pressed={marking} aria-label="标注"
      onClick={() => mark(!marking)}>
      <Edit size={14} strokeWidth={1.75} />
    </button></Tip>
  ) : null;

  const active = on && (marking || marks.length > 0);
  // In the address's place while marking: what to do, then how many, and putting them into the chat.
  const address = active ? (
    <div className={css.mode} role="status">
      <span className={css.modeDot} data-on={marking || undefined} aria-hidden="true" />
      {error
        ? <Tip label={error}><span className={css.modeError}>{error}</span></Tip>
        : <span className={css.modeText}>
            {marks.length ? `已标注 ${marks.length} 处` : "点选页面上的元素"}
            {marking && <span>{marks.length ? "可以继续点选" : "↑ ↓ 换一层 · Esc 停止"}</span>}
          </span>}
      <Tip label="取消标注"><button type="button" className={css.modeBtn} onClick={leave} disabled={busy} aria-label="取消标注"><Close size={12} strokeWidth={2} /></button></Tip>
      <button type="button" className={css.modeSend} onClick={() => void send()} disabled={busy || !marks.length} aria-busy={busy}>
        <Send size={12} strokeWidth={2} />{busy ? "截图中…" : "放进对话"}
      </button>
    </div>
  ) : null;

  const over = active && marks.length > 0 ? (
    <div className={css.layer} ref={layer}>
      {marks.map((m) => {
        const box = at.get(m.picked.n) ?? m.picked.rect;
        const open = editing === m.picked.n;
        // The pin's point on the element's top-left corner (kept in sight at the page's edges).
        const pin = { x: Math.max(2, box.x), y: Math.max(24, box.y) };
        return (
          <div key={m.picked.n}>
            <div className={css.outline} data-open={open || undefined} style={{ left: box.x, top: box.y, width: box.width, height: box.height }} />
            <Tip label={m.comment || m.picked.kind}><button type="button" className={css.pin} data-open={open || undefined} style={{ left: pin.x, top: pin.y }}
              aria-label={`标注 ${m.picked.n}`} onClick={() => setEditing(open ? null : m.picked.n)}>{m.picked.n}</button></Tip>
            {open
              ? <Note mark={m} x={pin.x} y={pin.y}
                  onComment={(comment) => setMarks((all) => all.map((x) => (x.picked.n === m.picked.n ? { ...x, comment } : x)))}
                  onDone={() => setEditing(null)} onRemove={() => remove(m.picked.n)} />
              : m.comment && <button type="button" className={css.said} style={
                  // Beside the pin, on its left when the right has too little room.
                  width - pin.x - 36 >= Math.min(220, pin.x - 14)
                    ? { left: pin.x + 28, top: pin.y - 23, maxWidth: width - pin.x - 36 }
                    : { right: width - pin.x + 6, top: pin.y - 23, maxWidth: pin.x - 14 }}
                  onClick={() => setEditing(m.picked.n)}>{m.comment}</button>}
          </div>
        );
      })}
    </div>
  ) : null;

  return { button, address, over };
}

/** What is said about one mark, in a bubble beside its pin. */
function Note({ mark, x, y, onComment, onDone, onRemove }:
  { mark: Mark; x: number; y: number; onComment(comment: string): void; onDone(): void; onRemove(): void }) {
  return (
    <div className={css.note} style={{ left: `clamp(8px, ${x + 28}px, calc(100% - 288px))`, top: `clamp(8px, ${y - 28}px, calc(100% - 44px))` }}>
      <input className={css.noteInput} autoFocus value={mark.comment} placeholder={`对这个${mark.picked.kind}说点什么`} aria-label={`标注 ${mark.picked.n} 的说明`}
        onChange={(e) => onComment(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === "Enter" && !e.nativeEvent.isComposing) { e.preventDefault(); onDone(); }
          else if (e.key === "Escape") { e.preventDefault(); if (mark.comment) onDone(); else onRemove(); }
        }} />
      <span className={css.noteKey} aria-hidden="true">↵</span>
      <Tip label="删掉这处标注"><button type="button" className={css.noteRemove} aria-label="删掉这处标注" onClick={onRemove}><Trash size={14} strokeWidth={1.75} /></button></Tip>
    </div>
  );
}

/** Where a mark is, as the agent reads it with the screenshot (the first line is also what the composer shows). */
function where(p: Picked): string {
  const lines = [
    `${p.kind ?? p.label}${p.text ? `「${p.text}」` : ""}`,
    `元素：${p.label} · 选择器：${p.selector}`,
    `页面：${p.path}（视口 ${p.viewport.width}×${p.viewport.height}），在整页截图的 (${p.page.x}, ${p.page.y}) 处，${p.page.width}×${p.page.height}`,
  ];
  if (p.component) lines.push(`组件：${p.component}`);
  return lines.join("\n");
}
