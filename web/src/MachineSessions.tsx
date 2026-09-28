// Going on in a chat with a session the station's machine kept: its own Claude Code or Codex, run in a terminal. The
// new chat page offers them, when there are any, in a dialog, newest first; the chat runs on in the directory the
// session ran in, and its transcript is copied, so the one in the terminal is left as it was.
import { useEffect, useState } from "react";
import { useApi, type MachineSession } from "./api.ts";
import { Monitor } from "./icons.tsx";
import { Dialog, RuntimeLogo } from "./ui.tsx";
import { ago, useNow } from "./Jobs.tsx";
import { RUNTIME_LABEL } from "./format.ts";
import * as css from "./MachineSessions.css.ts";
import * as uiCss from "./ui.css.ts";
import * as waitingCss from "./styles/waiting.css.ts";

/** The directory as people know it: the home directory as ~. */
function shortPath(path: string): string {
  return path.replace(/^\/(Users|home)\/[^/]+(?=\/|$)/, "~");
}

export function MachineSessions({ onContinued }: { onContinued(key: string): void }) {
  const api = useApi();
  const [sessions, setSessions] = useState<MachineSession[] | null>(null);
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const now = useNow(60_000);
  useEffect(() => {
    let live = true;
    // A station from before this answers 404: nothing is offered.
    api.machineSessions().then((r) => { if (live) setSessions(r.sessions); }, () => { if (live) setSessions([]); });
    return () => { live = false; };
  }, [api]);
  if (!sessions?.length) return null;
  const go = async (s: MachineSession) => {
    setBusy(s.id);
    setError(null);
    try {
      const { key } = await api.continueMachineSession(s.runtime, s.id);
      setOpen(false);
      onContinued(key);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(null);
    }
  };
  return (
    <>
      <button type="button" className={css.offer} onClick={() => setOpen(true)}><Monitor size={14} />接着本机终端里的会话</button>
      <Dialog open={open} wide onClose={() => setOpen(false)} title="接着本机的会话"
        description="这台机器上的 Claude Code 和 Codex 在终端里跑过的会话。选一个，就在它原来的目录里接着聊；终端里的那个不受影响。">
        {error && <p className={uiCss.dialogError} role="alert">{error}</p>}
        <ul className={css.list}>
          {sessions.map((s) => (
            <li key={`${s.runtime}:${s.id}`}>
              <button type="button" className={css.row} disabled={busy !== null} onClick={() => void go(s)} title={s.first ?? undefined}>
                <RuntimeLogo runtime={s.runtime} size={18} />
                <span className={css.main}>
                  <span className={css.title}>{s.title ?? s.first}</span>
                  <span className={css.meta}>{RUNTIME_LABEL[s.runtime]} · {shortPath(s.cwd)} · {ago(s.updatedAt, now)}</span>
                </span>
                {busy === s.id ? <span className={waitingCss.spinner} aria-label="正在接过来" /> : s.session ? <span className={css.already}>已在 ember 里</span> : null}
              </button>
            </li>
          ))}
        </ul>
      </Dialog>
    </>
  );
}
