// A link to one of a station's screens in a message (an agent asking a person to take over: docs/remote-screens.md),
// as the core's `screenCard` topic says it: on a line of its own, a card as a file's (what the screen is by its mark,
// its title, the core's line about it); within a sentence, its title where the link was.
import type { ReactNode } from "react";
import { useTopic } from "../core/react.ts";
import type { ScreenCard as Card } from "../core/shapes.ts";
import { screenOfLink } from "../chatRefs.ts";
import { t } from "../i18n.ts";
import * as chatCss from "../Chat.css.ts";
import * as css from "./ScreenLink.css.ts";

function useCard(href: string): Card | null {
  const of = screenOfLink(href);
  return useTopic<Card>(of ? { topic: "screenCard", station: of.station, screen: of.screen } : null).value ?? null;
}

/** A screen's kind at a glance, as a file's sheet is drawn (Chat.tsx FileTile): a display, or the globe for a browser tab. */
function ScreenTile({ kind }: { kind: string | undefined }) {
  return (
    <svg className={chatCss.fileTile} width="30" height="36" viewBox="0 0 30 36" aria-hidden="true">
      {kind === "browser" ? (
        <>
          <circle cx="15" cy="18" r="11.25" />
          <path d="M3.75 18H26.25M15 6.75C11.75 10 10.25 14 10.25 18S11.75 26 15 29.25M15 6.75C18.25 10 19.75 14 19.75 18S18.25 26 15 29.25" />
        </>
      ) : kind === "desktop" ? (
        <>
          <rect x="3.75" y="8" width="22.5" height="15.5" rx="2.5" />
          <path d="M15 23.5V28.5M10.5 28.5H19.5" />
        </>
      ) : null}
    </svg>
  );
}

/** A link to a screen alone on its line: its card, opening its page (pages/ChatPage.tsx opens it in the app). `words`: the link's own, shown for its title. */
export function ScreenCard({ href, words }: { href: string; words: ReactNode | null }) {
  const card = useCard(href);
  return (
    <a className={`${chatCss.fileCardOpen} ${css.screenCard}`} href={href} data-gone={card?.gone || undefined}>
      <span className={chatCss.fileCard} data-card="">
        <ScreenTile kind={card?.kind} />
        <span className={chatCss.fileCardText}>
          <span className={chatCss.fileCardName}><span className={chatCss.fileCardStem}>{words ?? card?.title ?? " "}</span></span>
          <span className={`${chatCss.fileCardMeta} ${css.screenCardLine}`}>{card?.line ?? " "}</span>
        </span>
      </span>
    </a>
  );
}

/** A bare link to a screen within a sentence: the screen's title for its words. */
export function ScreenName({ href }: { href: string }) {
  const card = useCard(href);
  return <a href={href}>{card?.title ?? t("web-pages.screen.title")}</a>;
}
