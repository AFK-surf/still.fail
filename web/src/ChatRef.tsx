// Referring to another chat from the composer: `@` and a few letters of its title list the station's chats, and the one
// chosen goes into the text as a chip (chatRefs.ts), sent as a link, [its title](its page). The agent reads that chat
// by the link (the station's chat_read and session_history tools).
import { useEffect, useMemo, useRef, type ReactNode, type RefObject } from "react";
import { useHref } from "react-router";
import { useChats, type ChatItem } from "./api.ts";
import { scopeOf, stationBase, useStation } from "./station.tsx";
import { ModelLogo, Time, Tip } from "./ui.tsx";
import { REF_LINK, REF_MARK, refTitle, splitBy } from "./chatRefs.ts";
import * as css from "./ChatRef.css.ts";

/** How many chats the menu offers at once. */
const SHOWN = 8;

/** The `@words` the caret is at the end of, and where the `@` is; null when it is not in one. */
export function refAt(text: string, caret: number): { start: number; query: string } | null {
  const m = /(?:^|\s)@([^\s@[\]()]{0,40})$/.exec(text.slice(0, caret));
  return m ? { start: caret - m[1]!.length - 1, query: m[1]! } : null;
}

/** A chat as a reference names it: its title, and the link to its page. */
export interface ChatRef { title: string; link: string }

function refOf(item: ChatItem, root: string): ChatRef {
  const origin = /^https?:$/.test(location.protocol) ? location.origin : "";
  return { title: refTitle(item.title), link: `${origin}${root.replace(/\/$/, "")}${stationBase(item.station)}/chats/${encodeURIComponent(item.id)}` };
}

/** A reference in a message: a chip that opens the chat (ChatPage opens its link in the page). */
export function RefChip({ title, href }: { title: ReactNode; href: string }) {
  return <Tip label="打开这个对话"><a className={css.refChip} href={href}><span className={css.refChipHash}>@</span>{title}</a></Tip>;
}

/** Plain text with its references (links to chats) drawn as chips. */
export function WithRefs({ text }: { text: string }) {
  return <>{splitBy(text, REF_LINK).map((part, i) => (typeof part === "string" ? part : <RefChip key={i} title={part[1]} href={part[2]!} />))}</>;
}

/**
 * The composer's text drawn under its (then see-through) text, each mark as a chip: the same letters in the same
 * places, so the caret and the selection keep to them. Its `[` and `]` are there but unseen, the chip's padding.
 */
export function RefMirror({ text, className, mirror }: { text: string; className: string; mirror: RefObject<HTMLDivElement | null> }) {
  return (
    <div ref={mirror} className={`${className} ${css.refMirror}`} aria-hidden="true">
      {splitBy(text, REF_MARK).map((part, i) => (typeof part === "string" ? part : (
        <span key={i} className={css.refMark}>@<span className={css.refMarkHidden}>[</span>{part[1]}<span className={css.refMarkHidden}>]</span></span>
      )))}
      {"\u200b"}
    </div>
  );
}

/** The mark just before `caret` (a backspace there takes it whole), or null. */
export function markBefore(text: string, caret: number): number | null {
  const m = /@\[[^\]\n]{1,120}\]$/.exec(text.slice(0, caret));
  return m ? m.index : null;
}

/**
 * The chats `query` finds on this station (another station's agents cannot read them), the latest first, but not
 * `here` (the chat written in). `found` hands them, and the link of each, to the composer, whose keys move `active`.
 */
export function ChatRefMenu({ query, here, active, onPick, found }: {
  query: string; here: string | null; active: number;
  onPick(ref: ChatRef): void;
  found(items: { item: ChatItem; ref: ChatRef }[]): void;
}) {
  const station = useStation();
  const root = useHref("/");
  const chats = useChats(scopeOf(station.address), false).value;
  const items = useMemo(() => {
    const words = query.toLowerCase();
    return (chats?.days ?? [])
      .flatMap((day) => day.items)
      .filter((item) => item.station === station.address && item.id !== here)
      .filter((item) => !words || item.title.toLowerCase().includes(words) || item.agents.some((a) => a.agentText.toLowerCase().includes(words)))
      .slice(0, SHOWN)
      .map((item) => ({ item, ref: refOf(item, root) }));
  }, [chats, query, here, station.address, root]);
  useEffect(() => found(items), [items]);
  const list = useRef<HTMLDivElement>(null);
  useEffect(() => { list.current?.querySelector(`[data-active]`)?.scrollIntoView({ block: "nearest" }); }, [active]);
  return (
    <div ref={list} className={css.refMenu} role="listbox" aria-label="引用对话" onMouseDown={(e) => e.preventDefault()}>
      <div className={css.refHead}>引用对话{query && <span className={css.refQuery}>{query}</span>}</div>
      {!chats ? <p className={css.refEmpty}>正在读取…</p>
        : items.length === 0 ? <p className={css.refEmpty}>{query ? "没有标题里带这些字的对话" : "这台 station 上没有别的对话"}</p>
        : items.map(({ item, ref }, i) => {
          const agent = item.agents[0];
          return (
            <button type="button" key={item.id} className={css.refItem} role="option" aria-selected={i === active} data-active={i === active || undefined}
              onClick={(e) => { e.stopPropagation(); onPick(ref); }}>
              <span className={css.refLogo}>{agent && <ModelLogo maker={agent.maker} runtime={agent.runtime} size={14} />}</span>
              <span className={css.refTitle}>{item.title}</span>
              <Time className={css.refTime} stamp={item.time?.lastActiveAt} fixed />
            </button>
          );
        })}
    </div>
  );
}
