// Referring to another chat from the composer: `@` and a few letters of its title list the station's chats (the core's
// `chatSearch`), and the one chosen goes into the text as a chip (chatRefs.ts), sent as a link, [its title](its page).
// The agent reads that chat by the link (the station's chat_read and session_history tools).
import { Fragment, useEffect, useRef, type ReactNode, type RefObject } from "react";
import { hrefOf } from "./go.ts";
import { stationApi, useChats, useChatSearch, useStationCall, useStationLook, type ChatItem } from "./api.ts";
import { ChatMark, stateLine } from "./ChatMark.tsx";
import { StationMark } from "./StationMark.tsx";
import { scopeOf, useStation } from "./station.tsx";
import type { AccountWorkspaces } from "./cloud/api.ts";
import { useTopicSelect } from "./core/react.ts";
import { ModelLogo, Time, WaitLine } from "./ui.tsx";
import { chatOfLink, copyChatLink, REF_LINK, REF_MARK, shareLink, splitBy, stationOfLink } from "./chatRefs.ts";
import { failure } from "@stillfail/ui/toast.tsx";
import * as css from "./ChatRef.css.ts";
import * as hover from "./Hover.css.ts";
import { CardSkeleton, Hover } from "./Peeks.tsx";

import { NAME } from "./channel.ts";
import { t } from "./i18n.ts";
/** How many chats the menu offers at once. */
const SHOWN = 8;

/** The `@words` the caret is at the end of, and the mark before it (a backspace takes it whole): the core's reading. */
export { markBefore, refAt } from "../../client/core-ts/src/refLinks.ts";

/**
 * A reference in a message: a chip that opens the chat (ChatPage opens its link in the page); one on another station of
 * the workspace says which after its title, one of another workspace which workspace. `title` null: a bare link, titled
 * as the list names its chat.
 */
export function RefChip({ title, href }: { title: ReactNode | null; href: string }) {
  const here = useStation().address;
  const there = stationOfLink(href);
  const elsewhere = there !== null && here.includes("/") && there !== here;
  const outside = elsewhere && here.includes("/") && scopeOf(there) !== scopeOf(here);
  // Only how its station looks, followed: not each change of the stations' views.
  const found = useStationLook(elsewhere && !outside ? there : null);
  // One of another workspace's (shared with this one, docs/chat-share.md) says that workspace's name.
  const workspace = useTopicSelect<AccountWorkspaces[], string | undefined>(outside ? { topic: "workspaces" } : null, (s) => s.value?.flatMap((a) => a.workspaces).find((w) => w.id === scopeOf(there!))?.name);
  const name = !elsewhere ? null : outside ? (workspace ?? scopeOf(there).slice(0, 8)) : (found?.name ?? there.slice(there.indexOf("/") + 1, there.indexOf("/") + 9));
  return (
    <Hover content={<RefPreview href={href} here={here} station={name} emoji={found?.emoji} icon={found?.icon} />}>
      <a className={css.refChip} href={href}>
        <span className={css.refChipHash}>@</span>{title ?? <RefTitle href={href} here={here} />}
        {name && <span className={css.refChipStation}>{!outside && <StationMark emoji={found?.emoji} icon={found?.icon} size={11} className={css.refChipStationIcon} />}{name}</span>}
      </a>
    </Hover>
  );
}

/** The chats references' cards last showed, by link. */
const seenChats = new Map<string, ChatItem>();

/** The chat a link names, as the workspace's list has it (or, while the list comes, as last seen); `listed`: the list is in. */
function useRefChat(href: string, here: string): { of: { station: string; id: string; history: string } | null; item: ChatItem | undefined; listed: boolean } {
  const relative = /\/chats\/([^/?#\s]+)/.exec(href);
  const of = chatOfLink(href) ?? (relative ? { station: here, id: safeDecode(relative[1]!), history: /[?&]history=/.test(href) ? "?" : "" } : null);
  const chats = useChats(scopeOf(here), false).value;
  const found = of && chats?.days.flatMap((d) => d.items).find((i) => i.station === of.station && (i.id === of.id || i.session === of.id));
  if (found) {
    seenChats.delete(href);
    seenChats.set(href, found);
    if (seenChats.size > 200) seenChats.delete(seenChats.keys().next().value!);
  }
  // While the list comes (the card opened again), the chat as last seen: no bars each time.
  return { of, item: found ?? (chats ? undefined : seenChats.get(href)), listed: !!chats };
}

/** A bare link's title (the link written as it is, not `[its title](link)`): the chat's, as the list has it; else its key. */
function RefTitle({ href, here }: { href: string; here: string }) {
  const { of, item } = useRefChat(href, here);
  return <>{item?.title || of?.id || href}</>;
}

/**
 * What a reference's chat is, while it is pointed at: its title, state and when it was last active, where it is, and the
 * last thing said (or where it stands) — from the workspace's list, so a chat not in it (archived, or not this
 * workspace's) says only that.
 */
function RefPreview({ href, here, station, emoji, icon }: { href: string; here: string; station: string | null; emoji?: string | null | undefined; icon?: string | null | undefined }) {
  const { of, item, listed } = useRefChat(href, here);
  if (!item) return listed ? <p className={hover.note}>{t("web-main.chatRef.previewGone")}</p> : <CardSkeleton />;
  const state = stateLine(item);
  return (
    <div className={hover.rich}>
      {/* Its title on one line with its mark and age, as a file's card has its name. */}
      <div className={hover.fileTitle}>
        <ChatMark item={item} inline />
        <span className={hover.title}>{item.title}</span>
        <Time className={hover.fileTime} stamp={item.time?.lastActiveAt} fixed />
      </div>
      {(station || of?.history) && (
        <div className={hover.meta}>
          <span className={hover.ref}>
            {station && <><StationMark emoji={emoji} icon={icon} size={11} className={hover.refIcon} />{station}{of?.history ? " · " : ""}</>}
            {of?.history ? t("web-main.chatRef.previewHistory") : ""}
          </span>
        </div>
      )}
      {(state ?? item.last?.preview) && <p className={hover.excerpt}>{state ?? item.last?.preview}</p>}
    </div>
  );
}

const safeDecode = (s: string) => {
  try {
    return decodeURIComponent(s);
  } catch {
    return s;
  }
};

/** Plain text with its references (links to chats) drawn as chips; the words between them as `words` draws them. */
export function WithRefs({ text, words = (part) => part }: { text: string; words?: (part: string) => ReactNode }) {
  return <>{splitBy(text, REF_LINK).map((part, i) => (typeof part === "string" ? <Fragment key={i}>{words(part)}</Fragment> : <RefChip key={i} title={part[1]} href={part[2]!} />))}</>;
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



/**
 * Copying a chat's link (shareLink), to paste into another chat for its agent to read: from its row's menu, or from an
 * agent's execution history (`history`: that agent, at one of its entries). `toast` says it is copied, or why not.
 */
export function useCopyChatLink(toast: (text: string) => void) {
  // Read when copied, not followed: every row and history entry that can copy a link was drawn again at each page change.
  return (item: Pick<ChatItem, "station" | "session" | "id" | "title">, history?: { key: string; entry?: number | undefined }) => {
    // Its history named as such: pasted, its reference is told from the chat's own.
    const title = history ? t("web-main.chat.historyRefTitle", { title: item.title }) : item.title;
    void copyChatLink(title, shareLink(item, hrefOf("/"), history)).then(
      () => toast(t(history ? "web-main.chat.historyLinkCopied" : "web-main.chat.linkCopied")),
      (e: unknown) => toast(t("web-main.chat.copyFailed", { error: failure(e) })),
    );
  };
}

/**
 * Copying where the agents' sessions keep their transcripts on the station's machine (`keys`: theirs), one per line,
 * to open them or hand them to another tool. `toast` says it is copied, that none is written yet, or why not.
 */
export function useCopyTranscripts(station: string, toast: (text: string) => void) {
  const api = stationApi(useStationCall(station));
  return (keys: string[]) => {
    void Promise.all(keys.map((key) => api.transcriptPath(key)))
      .then(async (paths) => {
        const found = paths.filter((p): p is string => p !== null);
        if (found.length === 0) return toast(t("web-main.chat.transcriptNone"));
        await navigator.clipboard.writeText(found.join("\n"));
        toast(found.length > 1 ? t("web-main.chat.transcriptsCopied", { n: found.length }) : t("web-main.chat.transcriptCopied"));
      })
      .catch((e: unknown) => toast(t("web-main.chat.copyFailed", { error: failure(e) })));
  };
}

/**
 * The chats `query` finds on this station's workspace (an agent reads one on any of its stations), titles first, but
 * not `here` (the chat written in); another station's say which; then the viewer's other workspaces', saying whose. `found` hands them to the composer, whose keys move `active`.
 */
export function ChatRefMenu({ query, here, active, onPick, found }: {
  query: string; here: string | null; active: number;
  onPick(item: ChatItem): void;
  found(items: ChatItem[]): void;
}) {
  const station = useStation();
  // The viewer's other workspaces' too (`elsewhere`), after this one's, each saying whose: one referred to is shared
  // with this workspace as the message goes (OutsideShare.tsx).
  const search = useChatSearch({ scope: scopeOf(station.address), query, station: station.address, exclude: here, limit: SHOWN, elsewhere: true });
  const items = search.value?.items;
  useEffect(() => found(items ?? []), [items]);
  const list = useRef<HTMLDivElement>(null);
  useEffect(() => { list.current?.querySelector(`[data-active]`)?.scrollIntoView({ block: "nearest" }); }, [active]);
  return (
    <div ref={list} className={css.refMenu} role="listbox" aria-label={t("web-main.chatRef.title")} onMouseDown={(e) => e.preventDefault()}>
      <div className={css.refHead}>{t("web-main.chatRef.title")}{query && <span className={css.refQuery}>{query}</span>}</div>
      {!items ? search.error ? <p className={css.refEmpty}>{t("web-main.chatRef.update", { app: NAME })}</p> : <WaitLine className={css.refEmpty} />
        : items.length === 0 ? <p className={css.refEmpty}>{query ? t("web-main.chatRef.noMatch") : t("web-main.chatRef.none")}</p>
        : items.map((item, i) => {
          const agent = item.agents[0];
          return (
            <button type="button" key={`${item.station}\t${item.id}`} className={css.refItem} role="option" aria-selected={i === active} data-active={i === active || undefined}
              onClick={(e) => { e.stopPropagation(); onPick(item); }}>
              <span className={css.refLogo}>{agent && <ModelLogo maker={agent.maker} runtime={agent.runtime} size={14} />}</span>
              {/* Another station's: its name after the title, as a reference to it shows it (the row keeps its three columns). */}
              <span className={css.refTitleCell}>
                <span className={css.refTitle}>{item.title}</span>
                {item.outside ? <span className={css.refChipStation}>{item.outside}</span>
                  : item.otherStation && <span className={css.refChipStation}><StationMark emoji={item.stationEmoji} icon={item.stationIcon} size={11} className={css.refChipStationIcon} />{item.stationName}</span>}
              </span>
              <Time className={css.refTime} stamp={item.time?.lastActiveAt} fixed />
            </button>
          );
        })}
    </div>
  );
}
