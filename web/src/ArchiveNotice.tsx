import { useAction } from "./action.ts";
import * as chatCss from "./styles/chat.css.ts";

/** Keeps the draft in place while the chat is archived; restoring can be retried after an error. */
export function ArchiveNotice({ restore, offline, className }: { restore: () => Promise<unknown>; offline: boolean; className: string }) {
  const operation = useAction(restore);
  const busy = operation.busy;
  const error = operation.error?.message;
  const run = () => { if (!offline) void operation.run(); };
  return <div className={className} role="status">
    已归档，还原后才能发送消息。{" "}
    <button type="button" className={chatCss.textButton} onClick={() => void run()} disabled={busy || offline}>{busy ? "正在还原…" : "还原对话"}</button>
    {error && <span role="alert">{error}</span>}
  </div>;
}
