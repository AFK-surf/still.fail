// What a chat's agents and other chats' agents wrote each other (session_send): not said in the chat, read here, by
// the other chat, both ways in the order written (the core's `chatLetters` view). The same on the wide screen (a tab
// beside the chat, pages/ChatPage.tsx) and the phone (a sheet, mobile/Chat.tsx).
import { useChatLetters } from "./api.ts";
import { StaticMessage } from "./Chat.tsx";
import { Empty } from "./ui.tsx";
import { Spinner, Waiting } from "@stillfail/ui/waiting.tsx";
import { t } from "./i18n.ts";
import * as chatCss from "./Chat.css.ts";
import * as css from "./Letters.css.ts";

export function Letters({ station, thread, keeper }: { station: string; thread: number;
  /** The session that keeps the chat's files. */
  keeper: string }) {
  const view = useChatLetters(station, thread).value;
  if (!view || (view.chats.length === 0 && !view.whole)) return <Waiting shape="messages" fill />;
  if (view.chats.length === 0) return <Empty><p>{t("web-main.letters.none")}</p></Empty>;
  return (
    // Narrow wherever it shows (a tab beside the chat, a sheet): each name in line with its picture, as the phone's chat.
    <div className={`${css.letters} ${chatCss.chatMessages} ${chatCss.inlineHeads}`}>
      {view.chats.map((c) => (
        <section key={c.link ?? c.title} className={css.lettersChat} aria-label={c.title}>
          <div className={css.lettersHead}>
            {c.link ? <a className={css.lettersName} href={c.link}>{c.title}</a> : <span className={css.lettersName}>{c.title}</span>}
            <span className={css.lettersCount}>{t("web-main.letters.count", { n: c.letters.length })}</span>
          </div>
          {c.letters.map((m) => <StaticMessage key={m.seq} message={m} keeper={keeper} />)}
        </section>
      ))}
      {/* Not all of the chat is here yet: more may come, older ones. */}
      {!view.whole && <div className={css.lettersMore}><Spinner /></div>}
    </div>
  );
}
