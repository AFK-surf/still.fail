import { useAction } from "./action.ts";
import type { ChatCacheCold } from "./core/shapes.ts";
import * as chatCss from "./styles/chat.css.ts";
import { t } from "./i18n.ts";

/** Its agent's prompt cache over (ChatView `cacheCold`, the core's words): going on reads its context again; a fresh
 * context instead (`session.clear` with `readBack`: it reads back what it needs), retried after an error. */
export function CacheColdNotice({ cold, afresh, offline, className }: { cold: ChatCacheCold; afresh: (session: string) => Promise<unknown>; offline: boolean; className: string }) {
  const operation = useAction(() => afresh(cold.session));
  const busy = operation.busy;
  const error = operation.error?.message;
  return <div className={className} role="status">
    {cold.text}{" "}
    <button type="button" className={chatCss.textButton} onClick={() => { if (!offline) void operation.run(); }} disabled={busy || offline}>{busy ? t("web-main.chat.afreshBusy") : t("web-main.chat.afresh")}</button>
    {error && <span role="alert">{error}</span>}
  </div>;
}
