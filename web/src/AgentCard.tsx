// An agent of the chat in brief, over its avatar while it is pointed at (Hover, Peeks.tsx), the same card wherever the
// avatar is (beside its messages, in the chat's bar): what it runs, where it stands and for how long, what it does now
// (with a stop for it alone), and what the core says of it (the `agentCard` view, views/brief.ts): what it has done,
// cost and used, its account and what is left of it, its jobs, what is wrong.
import { createContext, useContext, useLayoutEffect, useRef, type ReactElement, type RefObject } from "react";
import { useAgentCard, useApi, useLives, type ChatAgent } from "./api.ts";
import { useStation } from "./station.tsx";
import { Hover } from "./Peeks.tsx";
import { AgentMark, Tip } from "./ui.tsx";
import { Stop } from "./icons.tsx";
import { useAct } from "./toast.tsx";
import { useListMotion } from "./listMotion.ts";
import { reducedMotion } from "./motion.ts";
import { EdgeChip } from "./components.tsx";
import { t } from "./i18n.ts";
import { Elapsed, Waited } from "./Chat.tsx";
import * as css from "./AgentCard.css.ts";

/** The agents of the chat whose messages are drawn (ChatRows). */
export const ChatAgents = createContext<readonly ChatAgent[]>([]);

/** `children` (an agent's avatar) with its card while it is pointed at; as it is for an agent not of this chat. */
export function AgentHover({ agent, children }: { agent: string | null | undefined; children: ReactElement }) {
  const agents = useContext(ChatAgents);
  const of = agent ? agents.find((a) => a.session.key === agent) : undefined;
  if (!of) return children;
  return <Hover tile content={<AgentCard agent={of} />}>{children}</Hover>;
}

/**
 * `el`'s height goes from what it was at the last render to what this one gives it (lines coming and going), carrying
 * on from wherever it had got to; as it is the first time.
 */
function useHeightMotion(el: RefObject<HTMLElement | null>): void {
  const was = useRef<{ el: HTMLElement; height: number; run?: Animation } | null>(null);
  useLayoutEffect(() => {
    const box = el.current;
    const before = was.current;
    if (!box) return void (was.current = null);
    // Where it has got to, then its height at rest.
    const shown = box.offsetHeight;
    before?.run?.cancel();
    const height = box.offsetHeight;
    const from = before?.el === box ? (before.run ? shown : before.height) : height;
    was.current = { el: box, height };
    if (from === height || reducedMotion()) return;
    const run = box.animate([{ height: `${from}px` }, { height: `${height}px` }], { duration: 220, easing: "cubic-bezier(0.2, 0.7, 0.2, 1)" });
    was.current.run = run;
    void run.finished.then(() => { if (was.current?.run === run) delete was.current.run; }, () => {});
  });
}

/**
 * What it runs (with a stop for it alone while it works) and where it stands now (for how long), the latest three
 * things it did and what it does now, then what the core says of it (the `agentCard` view): the
 * figures that say most (cost, the cache's hit rate, how full its context is) large, side by side; its account with
 * what is left of it; the rest (its turns, tokens) in a quiet line; its jobs and what is wrong under them.
 */
export function AgentCard({ agent }: { agent: ChatAgent }) {
  const { session: s, wait } = agent;
  const station = useStation().address;
  const card = useAgentCard(station, s.key).value;
  const api = useApi();
  const act = useAct();
  const working = agent.status === "running" || agent.status === "queued";
  const now = useLives(station, [s.key]).get(s.key)?.activity?.now?.text;
  const recent = card?.recent ?? [];
  const doing = working && now && now !== recent.at(-1)?.text ? now : null;
  // A new line comes in under the others, which move up, the oldest going (listMotion.ts); the lines' height follows.
  const lines = useRef<HTMLOListElement>(null);
  useListMotion(lines);
  useHeightMotion(lines);
  const account = agent.account ?? agent.profile;
  const quota = agent.account?.quota?.state === "ok" ? agent.account.quota.windows : [];
  const context = card?.context;
  const quiet = [card?.work, card?.tokens].filter(Boolean).join(" · ");
  return (
    <div className={css.agentCard}>
      <div className={css.head}>
        <AgentMark maker={s.maker} runtime={s.runtime} badge={agent.badge} badgeText={s.badgeText} size={28} />
        <span className={css.name}>{s.agentText}</span>
        {working && (
          <button type="button" className={css.stop}
            onClick={() => act(api.stop(s.key), t("web-pages.chat.stop"), t("web-pages.chat.stopAsked"))}>
            <Stop size={11} fill="currentColor" />{t("web-pages.chat.stopTurn")}
          </button>
        )}
      </div>
      <p className={css.status} data-tone={s.tone}>
        {s.statusText}
        {wait
          ? <span className={css.elapsed}> · <Waited since={wait.since} seconds={wait.seconds} /></span>
          : agent.since ? <span className={css.elapsed}> · <Elapsed since={agent.since} /></span> : null}
      </p>
      {/* The latest of what it did, oldest first, then (unless that is the last of them) what it does now. */}
      {(recent.length > 0 || doing) && (
        <ol ref={lines} className={css.recent}>
          {recent.map((r) => <li key={r.key} data-flip={r.key}>{r.text}</li>)}
          {doing && <li key="now" data-flip="now" data-now="">{doing}</li>}
        </ol>
      )}
      {(card?.cost || card?.cache || context) && (
        <div className={css.tiles}>
          {card?.cost && <span className={css.tile}><b>{card.cost}</b><small>{t("web-main.chat.agentCard.cost")}</small></span>}
          {card?.cache && <span className={css.tile}><b>{card.cache.text}</b><small>{t("web-main.chat.agentCard.cache")}</small></span>}
          {/* How full, large; how much of how much on hover. */}
          {context && (context.unknown
            ? <span className={css.tile}><b>{context.text}</b><small>{t("web-main.chat.agentCard.context")}</small></span>
            : (
              <Tip label={context.text}>
                <span className={css.tile} data-level={context.level}><b>{Math.round(context.percent)}%</b><small>{t("web-main.chat.agentCard.context")}</small></span>
              </Tip>
            ))}
        </div>
      )}
      {(account || quota.length > 0) && (
        <div className={css.account}>
          <span className={css.accountName}>{account?.name}</span>
          <span className={css.chips}>
            {quota.map((w) => (
              <Tip key={w.label} label={<>{t("web-main.quota.left", { label: w.label, left: w.left })}{w.refills && <><br />{w.refills}</>}</>}>
                <EdgeChip fill={w.left} level={w.level} mark={quota.length > 1 ? w.mark : null} label={t("web-main.quota.left", { label: w.label, left: w.left })} small />
              </Tip>
            ))}
          </span>
        </div>
      )}
      {quiet && <p className={css.quiet}>{quiet}</p>}
      {(card?.jobs || (card?.attention.length ?? 0) > 0) && (
        <div className={css.notes}>
          {card?.jobs && <span>{card.jobs}</span>}
          {card?.attention.map((a, i) => <span key={i} data-level={a.level}>{a.text}</span>)}
        </div>
      )}
    </div>
  );
}
