import { useDoing } from "./doing.ts";
import { useStation } from "./station.tsx";
// Going on in a chat with a session the station's machine kept: its own Claude Code or Codex, run in a terminal. The
// new chat page offers them, when there are any, in a dialog, newest first; the chat runs on in the directory the
// session ran in, and its transcript is copied, so the one in the terminal is left as it was.
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { useApi, type MachineSaid, type MachineSession, type RuntimeKind, type Stamp } from "./api.ts";
import type { ModelOption } from "./core/shapes.ts";
import { ArrowLeft, Monitor } from "./icons.tsx";
import { Button, Dialog, RuntimeLogo, Time, Tip } from "./ui.tsx";
import { AgentAvatar, AgentWords, MessageName, MineBubble, MineMessage, OthersMessage } from "./Chat.tsx";
import { modelName, optionOf } from "./ModelTriple.tsx";
import * as conversationCss from "./styles/conversation.css.ts";
import { RUNTIME_LABEL } from "./format.ts";
import * as css from "./MachineSessions.css.ts";
import * as uiCss from "./ui.css.ts";
import * as waitingCss from "./styles/waiting.css.ts";

import { NAME } from "./channel.ts";
import { t } from "./i18n.ts";
// Times in words, still worked out here (they were the job lists' until those moved into the core).

/** A time span in words, as long ago: 12 秒前, 4 分钟前, 3 小时前, 2 天前. */
function spanAgo(ms: number): string {
  const s = Math.max(0, Math.round(ms / 1000));
  if (s < 60) return t("web-main.ago.seconds", { n: s });
  if (s < 3600) return t("web-main.ago.minutes", { n: Math.floor(s / 60) });
  if (s < 86400) return t("web-main.ago.hours", { n: Math.floor(s / 3600) });
  return t("web-main.ago.days", { n: Math.floor(s / 86400) });
}

/** How long ago: 刚刚, 12 秒前, 4 分钟前, 3 小时前, 昨天, 2 天前. */
function ago(at: number, now: number): string {
  const s = Math.round((now - at) / 1000);
  if (s < 5) return t("web-main.ago.now");
  if (s >= 86400 && s < 2 * 86400) return t("web-main.ago.yesterday");
  return spanAgo(now - at);
}

/** A clock time: 13:04 today, 9/27 13:04 before. */
function clock(at: number, now: number): string {
  const d = new Date(at);
  const hm = `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
  return new Date(now).toDateString() === d.toDateString() ? hm : `${d.getMonth() + 1}/${d.getDate()} ${hm}`;
}

/** Now, again every `every` ms: for the times in words. */
function useNow(every: number): number {
  const [now, setNow] = useState(Date.now);
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), every);
    return () => clearInterval(timer);
  }, [every]);
  return now;
}

/** `models`: the station's, for the agents' names and pictures in a preview; `name`: the station's, said for where they ran. */
export function MachineSessions({ name, models, onContinued }: { name: string; models: ModelOption[]; onContinued(key: string): void }) {
  const api = useApi();
  const [sessions, setSessions] = useState<MachineSession[] | null>(null);
  const [open, setOpen] = useState(false);
  /** The one being looked at before going on with it. */
  const [looking, setLooking] = useState<MachineSession | null>(null);
  const busy = useDoing("machineSessions.continue", { station: useStation().address });
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    let live = true;
    // A station from before this answers 404: nothing is offered.
    api.machineSessions().then((r) => { if (live) setSessions(r.sessions); }, () => { if (live) setSessions([]); });
    return () => { live = false; };
  }, [api]);
  if (!sessions?.length) return null;
  const close = () => { setOpen(false); setLooking(null); setError(null); };
  const go = async (s: MachineSession) => {
    setError(null);
    try {
      const { key } = await api.continueMachineSession(s.runtime, s.id);
      close();
      onContinued(key);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };
  // Its runtime, where it ran and how long ago, in a line (the core's).
  const meta = (s: MachineSession) => s.meta ?? "";
  return (
    <>
      <button type="button" className={css.offer} onClick={() => setOpen(true)}><Monitor size={14} />{t("web-main.machine.offer", { name: name || t("web-main.machine.this") })}</button>
      {looking ? (
        <Dialog open={open} wide onClose={close} title={looking.title ?? looking.first} description={meta(looking)}
          footer={<>
            <Button variant="ghost" icon={ArrowLeft} disabled={busy} onClick={() => { setLooking(null); setError(null); }}>{t("common.back")}</Button>
            <Button variant="primary" busy={busy} onClick={() => void go(looking)}>{looking.session ? t("web-main.machine.openChat") : t("web-main.machine.continue")}</Button>
          </>}>
          {error && <p className={uiCss.dialogError} role="alert">{error}</p>}
          <Preview runtime={looking.runtime} id={looking.id} models={models} />
        </Dialog>
      ) : (
        <Dialog open={open} wide onClose={close} title={t("web-main.machine.title", { name: name || t("web-main.machine.this") })}
          description={t("web-main.machine.description")}>
          <ul className={css.list}>
            {sessions.map((s) => (
              <li key={`${s.runtime}:${s.id}`}>
                <Tip label={s.first ?? undefined}><button type="button" className={css.row} onClick={() => setLooking(s)}>
                  <RuntimeLogo runtime={s.runtime} size={18} />
                  <span className={css.main}>
                    <span className={css.title}>{s.title ?? s.first}</span>
                    <span className={css.meta}>{meta(s)}</span>
                  </span>
                  {s.session ? <span className={css.already}>{t("web-main.machine.already", { app: NAME })}</span> : null}
                </button></Tip>
              </li>
            ))}
          </ul>
        </Dialog>
      )}
    </>
  );
}

/** What was said in a session, read only, drawn as the chat draws messages; the latest at the bottom (in view as it
 * opens). */
function Preview({ runtime, id, models }: { runtime: RuntimeKind; id: string; models: ModelOption[] }) {
  const api = useApi();
  const [shown, setShown] = useState<{ session: MachineSession; said: MachineSaid[]; total: number } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const end = useRef<HTMLDivElement>(null);
  const now = useNow(60_000);
  useEffect(() => {
    let live = true;
    api.machineSession(runtime, id).then(
      (r) => { if (live) setShown(r); },
      (e: unknown) => { if (live) setError(e instanceof Error ? e.message : String(e)); },
    );
    return () => { live = false; };
  }, [api, runtime, id]);
  useLayoutEffect(() => { end.current?.scrollIntoView({ block: "end" }); }, [shown]);
  if (error) return <p className={uiCss.dialogError} role="alert">{error}</p>;
  if (!shown) return <div className={css.previewWait}><span className={waitingCss.spinner} aria-hidden="true" />{t("web-main.reading")}</div>;
  const left = shown.total - shown.said.length;
  const model = shown.session.model;
  const option = optionOf(models, model);
  const name = model ? modelName(models, model) : RUNTIME_LABEL[runtime];
  const stamp = (at: number | null): Stamp | undefined => at == null ? undefined : { at, ago: ago(at, now), full: clock(at, now), until: "", past: true };
  return (
    <div className={css.preview}>
      {left > 0 && <p className={css.previewMore}>{t("web-main.machine.more", { n: left })}</p>}
      {shown.said.map((m, i) => m.person
        ? <MineMessage key={i}><MineBubble text={m.text} /><Time className={conversationCss.msgTime} stamp={stamp(m.at)} /></MineMessage>
        : (
          <OthersMessage key={i} avatar={<AgentAvatar maker={option?.maker} runtime={runtime} />} name={<MessageName>{name}</MessageName>} time={stamp(m.at)}>
            <AgentWords text={m.text} />
          </OthersMessage>
        ))}
      <div ref={end} />
    </div>
  );
}
