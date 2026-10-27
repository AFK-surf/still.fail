import { Wait } from "@stillfail/ui/icons.tsx";
import { useAction } from "./action.ts";
import { ComposerNotice, NoticeOffer } from "./ComposerNotice.tsx";
import type { ChatCacheCold } from "./core/shapes.ts";
import { t } from "./i18n.ts";

/** Its agent's prompt cache over (ChatView `cacheCold`, the core's words): going on reads its context again; a fresh
 * context instead (`session.clear` with `readBack`: it reads back what it needs), retried after an error; its station
 * going on afresh by itself (`auto`), nothing to tap. */
export function CacheColdNotice({ cold, afresh, offline }: { cold: ChatCacheCold; afresh: (session: string) => Promise<unknown>; offline: boolean }) {
  const operation = useAction(() => afresh(cold.session));
  const busy = operation.busy;
  return <ComposerNotice mark={<Wait size={16} />} error={operation.error?.message}
    offer={cold.auto ? undefined : <NoticeOffer onClick={() => { if (!offline) void operation.run(); }} disabled={busy || offline}>{busy ? t("web-main.chat.afreshBusy") : t("web-main.chat.afresh")}</NoticeOffer>}>
    {cold.text}
  </ComposerNotice>;
}
