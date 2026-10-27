import { Archive } from "@stillfail/ui/icons.tsx";
import { useAction } from "./action.ts";
import { ComposerNotice, NoticeOffer } from "./ComposerNotice.tsx";
import { t } from "./i18n.ts";

/** Keeps the draft in place while the chat is archived; restoring can be retried after an error. */
export function ArchiveNotice({ restore, offline }: { restore: () => Promise<unknown>; offline: boolean }) {
  const operation = useAction(restore);
  const busy = operation.busy;
  return <ComposerNotice mark={<Archive size={16} />} error={operation.error?.message}
    offer={<NoticeOffer onClick={() => { if (!offline) void operation.run(); }} disabled={busy || offline}>{busy ? t("web-main.archived.restoring") : t("web-main.archived.restore")}</NoticeOffer>}>
    {t("web-main.archived.notice")}
  </ComposerNotice>;
}
