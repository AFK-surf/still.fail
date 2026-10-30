// A link to a station's 共享调试 in a message (an agent asking for a person's phone: docs/adb-share.md), as the core's
// `adbCard` topic says it: on a line of its own, a card as a screen's is (screen/ScreenLink.tsx: a phone for its mark,
// 共享调试, how this phone's sharing with that station stands); within a sentence, 共享调试 where the link was. Only the
// Android app can lend its adb: here the card says so and opens nothing.
import { Phone } from "@stillfail/ui/icons.tsx";
import type { ReactNode } from "react";
import { useTopic } from "./core/react.ts";
import type { AdbCard as Card } from "./core/shapes.ts";
import { adbOfLink } from "./chatRefs.ts";
import { t } from "./i18n.ts";
import * as chatCss from "./Chat.css.ts";
import * as css from "./screen/ScreenLink.css.ts";

function useCard(href: string): Card | null {
  const station = adbOfLink(href);
  return useTopic<Card>(station ? { topic: "adbCard", station } : null).value ?? null;
}

/** A phone, drawn as a file's sheet is (Chat.tsx FileTile); in the accent while this phone is lent to that station. */
function PhoneTile({ sharing }: { sharing: boolean }) {
  return (
    <svg className={`${chatCss.fileTile} ${css.adbTile}`} data-sharing={sharing || undefined} width="24" height="24" viewBox="0 0 24 24" aria-hidden="true">
      <Phone size={24} stroke="inherit" />
    </svg>
  );
}

/** A link to a station's 共享调试 alone on its line: its card. `words`: the link's own, shown for its title. */
export function AdbCard({ href, words }: { href: string; words: ReactNode | null }) {
  const card = useCard(href);
  const inner = (
    <span className={chatCss.fileCard} data-card="">
      <PhoneTile sharing={card?.sharing === true} />
      <span className={chatCss.fileCardText}>
        <span className={chatCss.fileCardName}><span className={chatCss.fileCardStem}>{words ?? card?.title ?? " "}</span></span>
        <span className={`${chatCss.fileCardMeta} ${css.screenCardLine}`}>{card?.line ?? " "}</span>
      </span>
    </span>
  );
  if (card?.lendable === false) return <span className={css.screenCard}>{inner}</span>;
  return <a className={`${chatCss.fileCardOpen} ${css.screenCard}`} href={href}>{inner}</a>;
}

/** A bare link to a station's 共享调试 within a sentence: 共享调试 for its words. */
export function AdbName({ href }: { href: string }) {
  const card = useCard(href);
  return <a href={href}>{card?.title ?? t("web-pages.adb.title")}</a>;
}
