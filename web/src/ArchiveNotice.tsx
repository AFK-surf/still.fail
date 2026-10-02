import { useAction } from "./action.ts";
import * as chatCss from "./styles/chat.css.ts";
import { t } from "./i18n.ts";

/** Keeps the draft in place while the chat is archived; restoring can be retried after an error. */
export function ArchiveNotice({ restore, offline, className }: { restore: () => Promise<unknown>; offline: boolean; className: string }) {
  const operation = useAction(restore);
  const busy = operation.busy;
  const error = operation.error?.message;
  const run = () => { if (!offline) void operation.run(); };
  return <div className={className} role="status">
    {t("web-main.archived.notice")}{" "}
    <button type="button" className={chatCss.textButton} onClick={() => void run()} disabled={busy || offline}>{busy ? t("web-main.archived.restoring") : t("web-main.archived.restore")}</button>
    {error && <span role="alert">{error}</span>}
  </div>;
}
