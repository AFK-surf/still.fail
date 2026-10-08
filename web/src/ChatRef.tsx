// Referring to another chat from the composer: `@` and a few letters of its title list the station's chats (the core's
// `chatSearch`), and the one chosen goes into the text as a chip (chatRefs.ts), sent as a link, [its title](its page).
// The agent reads that chat by the link (the station's chat_read and session_history tools).
import { useEffect, useRef, type ReactNode, type RefObject } from "react";
import { useHref } from "react-router";
import { useChatSearch, useStations, type ChatItem } from "./api.ts";
import { Server } from "./icons.tsx";
import { scopeOf, useStation } from "./station.tsx";
import { ModelLogo, Time } from "./ui.tsx";
import { copyChatLink, REF_LINK, REF_MARK, shareLink, splitBy, stationOfLink } from "./chatRefs.ts";
import { failure } from "./toast.tsx";
import * as css from "./ChatRef.css.ts";

import { NAME } from "./channel.ts";
import { t } from "./i18n.ts";
/** How many chats the menu offers at once. */
const SHOWN = 8;

/** The `@words` the caret is at the end of, and where the `@` is; null when it is not in one. */
export function refAt(text: string, caret: number): { start: number; query: string } | null {
  const m = /(?:^|\s)@([^\s@[\]()]{0,40})$/.exec(text.slice(0, caret));
  return m ? { start: caret - m[1]!.length - 1, query: m[1]! } : null;
}

/**
 * A reference in a message: a chip that opens the chat (ChatPage opens its link in the page); one on another station of
 * the workspace says which after its title.
 */
export function RefChip({ title, href }: { title: ReactNode; href: string }) {
  const here = useStation().address;
  const there = stationOfLink(href);
  const elsewhere = there !== null && here.includes("/") && there !== here;
  const stations = useStations(scopeOf(here)).value;
  const name = elsewhere ? (stations?.find((s) => s.station === there)?.name ?? there.slice(there.indexOf("/") + 1, there.indexOf("/") + 9)) : null;
  return (
    <a className={css.refChip} href={href}>
      <span className={css.refChipHash}>@</span>{title}
      {name && <span className={css.refChipStation}><Server size={11} />{name}</span>}
    </a>
  );
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
 * Copying a chat's link from its row's menu (shareLink), to paste into another chat for its agent to read: `history`,
 * the link to its agent's execution history. `toast` says it is copied, or why not.
 */
export function useCopyChatLink(toast: (text: string) => void) {
  const root = useHref("/");
  return (item: Pick<ChatItem, "station" | "session" | "id" | "title">, history = false) => {
    // Its history named as such: pasted, its reference is told from the chat's own.
    const title = history ? t("web-main.chat.historyRefTitle", { title: item.title }) : item.title;
    void copyChatLink(title, shareLink(item, root, history)).then(
      () => toast(t(history ? "web-main.chat.historyLinkCopied" : "web-main.chat.linkCopied")),
      (e: unknown) => toast(t("web-main.chat.copyFailed", { error: failure(e) })),
    );
  };
}

/**
 * The chats `query` finds on this station's workspace (an agent reads one on any of its stations), titles first, but
 * not `here` (the chat written in); another station's say which. `found` hands them to the composer, whose keys move `active`.
 */
export function ChatRefMenu({ query, here, active, onPick, found }: {
  query: string; here: string | null; active: number;
  onPick(item: ChatItem): void;
  found(items: ChatItem[]): void;
}) {
  const station = useStation();
  const search = useChatSearch({ scope: scopeOf(station.address), query, exclude: here, limit: SHOWN });
  const items = search.value?.items;
  useEffect(() => found(items ?? []), [items]);
  const list = useRef<HTMLDivElement>(null);
  useEffect(() => { list.current?.querySelector(`[data-active]`)?.scrollIntoView({ block: "nearest" }); }, [active]);
  return (
    <div ref={list} className={css.refMenu} role="listbox" aria-label={t("web-main.chatRef.title")} onMouseDown={(e) => e.preventDefault()}>
      <div className={css.refHead}>{t("web-main.chatRef.title")}{query && <span className={css.refQuery}>{query}</span>}</div>
      {!items ? <p className={css.refEmpty}>{search.error ? t("web-main.chatRef.update", { app: NAME }) : t("web-main.reading")}</p>
        : items.length === 0 ? <p className={css.refEmpty}>{query ? t("web-main.chatRef.noMatch") : t("web-main.chatRef.none")}</p>
        : items.map((item, i) => {
          const agent = item.agents[0];
          return (
            <button type="button" key={item.id} className={css.refItem} role="option" aria-selected={i === active} data-active={i === active || undefined}
              onClick={(e) => { e.stopPropagation(); onPick(item); }}>
              <span className={css.refLogo}>{agent && <ModelLogo maker={agent.maker} runtime={agent.runtime} size={14} />}</span>
              <span className={css.refTitle}>{item.title}</span>
              {item.station !== station.address && <span className={css.refTime}>{item.stationName}</span>}
              <Time className={css.refTime} stamp={item.time?.lastActiveAt} fixed />
            </button>
          );
        })}
    </div>
  );
}
