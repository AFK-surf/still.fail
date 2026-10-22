// What a chat's agents and other chats' agents wrote each other (session_send): not said in the chat, read here (the
// core's `chatLetters` view). First the chats it wrote with, a row each, the last written with first; one opened, its
// letters both ways in the order written. The same on the wide screen (a tab beside the chat, pages/ChatPage.tsx) and
// the phone (a sheet, mobile/Chat.tsx).
import { useState } from "react";
import { useChatLetters } from "./api.ts";
import { StaticMessage } from "./Chat.tsx";
import { Empty, IconButton, Time } from "./ui.tsx";
import { Spinner, Waiting } from "@stillfail/ui/waiting.tsx";
import { ArrowLeft } from "@stillfail/ui/icons.tsx";
import { t } from "./i18n.ts";
import * as chatCss from "./Chat.css.ts";
import * as css from "./Letters.css.ts";

export function Letters({ station, thread, keeper }: { station: string; thread: number;
  /** The session that keeps the chat's files. */
  keeper: string }) {
  const view = useChatLetters(station, thread).value;
  const [opened, open] = useState<string | null>(null);
  if (!view || (view.chats.length === 0 && !view.whole)) return <Waiting shape="rows" fill />;
  if (view.chats.length === 0) return <Empty><p>{t("web-main.letters.none")}</p></Empty>;
  // Not all of the chat is here yet: more may come, older ones.
  const more = !view.whole && <div className={css.lettersMore}><Spinner /></div>;
  const chat = view.chats.find((c) => c.key === opened);
  if (!chat) {
    return (
      <div className={css.letters}>
        <div className={css.lettersList}>
          {view.chats.map((c) => (
            <button key={c.key} type="button" className={css.lettersRow} onClick={() => open(c.key)}>
              <span className={css.lettersRowHead}>
                <span className={css.lettersRowTitle}>{c.title}</span>
                <span className={css.lettersRowMeta}>{t("web-main.letters.count", { n: c.letters.length })} · <Time stamp={c.time?.lastActiveAt} /></span>
              </span>
              <span className={css.lettersRowLast}>{c.last}</span>
            </button>
          ))}
        </div>
        {more}
      </div>
    );
  }
  return (
    <div className={css.letters}>
      <div className={css.lettersHead}>
        <IconButton label={t("web-main.letters.back")} icon={ArrowLeft} onClick={() => open(null)} />
        {chat.link ? <a className={css.lettersName} href={chat.link}>{chat.title}</a> : <span className={css.lettersName}>{chat.title}</span>}
      </div>
      {/* Narrow wherever it shows: each name in line with its picture, as the phone's chat. */}
      <div className={`${css.lettersMessages} ${chatCss.chatMessages} ${chatCss.inlineHeads}`}>
        {chat.letters.map((m) => <StaticMessage key={m.seq} message={m} keeper={keeper} />)}
      </div>
      {more}
    </div>
  );
}
