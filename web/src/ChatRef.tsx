// Referring to another chat from the composer: `@` and a few letters of its title list the station's chats (the core's
// `chatSearch`), and the one chosen goes into the text as a chip (chatRefs.ts), sent as a link, [its title](its page).
// The agent reads that chat by the link (the station's chat_read and session_history tools).
import { useEffect, useRef, type ReactNode, type RefObject } from "react";
import { useChatSearch, type ChatItem } from "./api.ts";
import { scopeOf, useStation } from "./station.tsx";
import { ModelLogo, Time } from "./ui.tsx";
import { REF_LINK, REF_MARK, splitBy } from "./chatRefs.ts";
import * as css from "./ChatRef.css.ts";

/** How many chats the menu offers at once. */
const SHOWN = 8;

/** The `@words` the caret is at the end of, and where the `@` is; null when it is not in one. */
export function refAt(text: string, caret: number): { start: number; query: string } | null {
  const m = /(?:^|\s)@([^\s@[\]()]{0,40})$/.exec(text.slice(0, caret));
  return m ? { start: caret - m[1]!.length - 1, query: m[1]! } : null;
}

/** A reference in a message: a chip that opens the chat (ChatPage opens its link in the page). */
export function RefChip({ title, href }: { title: ReactNode; href: string }) {
  return <a className={css.refChip} href={href}><span className={css.refChipHash}>@</span>{title}</a>;
}

/** Plain text with its references (links to chats) drawn as chips. */
export function WithRefs({ text }: { text: string }) {
  return <>{splitBy(text, REF_LINK).map((part, i) => (typeof part === "string" ? part : <RefChip key={i} title={part[1]} href={part[2]!} />))}</>;
}

/**
 * The composer's text drawn under its (then see-through) text, each mark as a chip: the same letters in the same
 * places, so the caret and the selection keep to them. Its `[` and `]` are there but unseen, the chip's padding; the
 * `[` drawn before the `@` (the same width, so what follows keeps its place) to keep the `@` against the title.
 */
export function RefMirror({ text, className, mirror }: { text: string; className: string; mirror: RefObject<HTMLDivElement | null> }) {
  return (
    <div ref={mirror} className={`${className} ${css.refMirror}`} aria-hidden="true">
      {splitBy(text, REF_MARK).map((part, i) => (typeof part === "string" ? part : (
        <span key={i} className={css.refMark}><span className={css.refMarkHidden}>[</span>@{part[1]}<span className={css.refMarkHidden}>]</span></span>
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
 * The chats `query` finds on this station (another station's agents cannot read them), titles first, but not `here`
 * (the chat written in). `found` hands them to the composer, whose keys move `active`.
 */
export function ChatRefMenu({ query, here, active, onPick, found }: {
  query: string; here: string | null; active: number;
  onPick(item: ChatItem): void;
  found(items: ChatItem[]): void;
}) {
  const station = useStation();
  const search = useChatSearch({ scope: scopeOf(station.address), query, station: station.address, exclude: here, limit: SHOWN });
  const items = search.value?.items;
  useEffect(() => found(items ?? []), [items]);
  const list = useRef<HTMLDivElement>(null);
  useEffect(() => { list.current?.querySelector(`[data-active]`)?.scrollIntoView({ block: "nearest" }); }, [active]);
  return (
    <div ref={list} className={css.refMenu} role="listbox" aria-label="引用对话" onMouseDown={(e) => e.preventDefault()}>
      <div className={css.refHead}>引用对话{query && <span className={css.refQuery}>{query}</span>}</div>
      {!items ? <p className={css.refEmpty}>{search.error ? "更新 still.fail 后才能引用对话" : "正在读取…"}</p>
        : items.length === 0 ? <p className={css.refEmpty}>{query ? "没有标题里带这些字的对话" : "这台 station 上没有别的对话"}</p>
        : items.map((item, i) => {
          const agent = item.agents[0];
          return (
            <button type="button" key={item.id} className={css.refItem} role="option" aria-selected={i === active} data-active={i === active || undefined}
              onClick={(e) => { e.stopPropagation(); onPick(item); }}>
              <span className={css.refLogo}>{agent && <ModelLogo maker={agent.maker} runtime={agent.runtime} size={14} />}</span>
              <span className={css.refTitle}>{item.title}</span>
              <Time className={css.refTime} stamp={item.time?.lastActiveAt} fixed />
            </button>
          );
        })}
    </div>
  );
}
