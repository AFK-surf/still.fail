import { useState } from "react";

/** Keeps the draft in place while the chat is archived; restoring can be retried after an error. */
export function ArchiveNotice({ restore, offline, className }: { restore: () => Promise<unknown>; offline: boolean; className: string }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const run = async () => {
    if (busy || offline) return;
    setBusy(true);
    setError(null);
    try { await restore(); }
    catch (error) { setError(error instanceof Error ? error.message : String(error)); }
    finally { setBusy(false); }
  };
  return <div className={className} role="status">
    已归档，还原后才能发送消息。{" "}
    <button type="button" onClick={() => void run()} disabled={busy || offline}>{busy ? "正在还原…" : "还原对话"}</button>
    {error && <span role="alert">{error}</span>}
  </div>;
}
