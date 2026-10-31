import { Wait } from "@stillfail/ui/icons.tsx";
import { useAction } from "./action.ts";
import { ComposerNotice, NoticeChoice } from "./ComposerNotice.tsx";
import type { ChatCacheCold } from "./core/shapes.ts";
import { t } from "./i18n.ts";

/** Its agent's prompt cache over (ChatView `cacheCold`, the core's words): what going on would read again, and the
 * choice of how it goes on as it is next started, by a message or a notice: 接着聊 or 换新上下文 (its context cleared,
 * told to read back what it needs), the one taken marked, the other pressed to take it any time (`session.settings`
 * `afresh`), as its chat chose or else its station is set. */
export function CacheColdNotice({ cold, setAfresh, offline }: { cold: ChatCacheCold; setAfresh: (session: string, afresh: boolean) => Promise<unknown>; offline: boolean }) {
  const operation = useAction((afresh: boolean) => setAfresh(cold.session, afresh));
  const held = operation.busy || offline;
  return <ComposerNotice mark={<Wait size={16} />} error={operation.error?.message}
    offer={<NoticeChoice held={held} options={[
      { label: t("web-main.chat.goOn"), taken: !cold.afresh, take: () => void operation.run(false) },
      { label: t("web-main.chat.afresh"), taken: cold.afresh, take: () => void operation.run(true) },
    ]} />}>
    {cold.text}
  </ComposerNotice>;
}
