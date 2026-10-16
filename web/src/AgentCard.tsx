// An agent of the chat in brief, over its avatar while it is pointed at (Hover, Peeks.tsx), the same card wherever the
// avatar is (beside its messages, in the chat's bar): what it runs, where it stands and for how long, what it does now
// (with a stop for it alone), and what the core says of it (the `agentCard` view, views/brief.ts): what it has done,
// cost and used, its account and what is left of it, its jobs, what is wrong.
import { createContext, memo, useContext, useLayoutEffect, useRef, type ReactElement, type RefObject } from "react";
import { useAgentCard, useApi, type ChatAgent } from "./api.ts";
import type { AgentCardView } from "./core/shapes.ts";
import { useStation } from "./station.tsx";
import { Hover } from "./Peeks.tsx";
import { AgentMark, Tip } from "./ui.tsx";
import { Stop } from "./icons.tsx";
import { useAct } from "./toast.tsx";
import { reducedMotion } from "./motion.ts";
import { QuotaChip } from "./components.tsx";
import { t } from "./i18n.ts";
import { Elapsed, Waited } from "./Chat.tsx";
import * as css from "./AgentCard.css.ts";

/** The agents of the chat whose messages are drawn (ChatRows). */
export const ChatAgents = createContext<readonly ChatAgent[]>([]);
/**
 * Their keys, one a line: what an avatar beside a message needs to know (whether its agent is the chat's), the same
 * while they are, though the agents change with every message (their states, their times).
 */
export const ChatAgentKeys = createContext<string>("");

/** `children` (an agent's avatar) with its card while it is pointed at; as it is for an agent not of this chat. */
export function AgentHover({ agent, children }: { agent: string | null | undefined; children: ReactElement }) {
  const agents = useContext(ChatAgentKeys);
  if (!agent || !agents.split("\n").includes(agent)) return children;
  return <AgentHovered agent={agent}>{children}</AgentHovered>;
}

/**
 * Drawn again only for another agent: the chat's agents change with every message (their states, their times), and
 * what the card says of its agent is read by the card, while it shows.
 */
const AgentHovered = memo(function AgentHovered({ agent, children }: { agent: string; children: ReactElement }) {
  return <Hover tile content={<ChatAgentCard agent={agent} />}>{children}</Hover>;
});

/** The card of one of the chat's agents, by its key, as the agent is now. */
function ChatAgentCard({ agent }: { agent: string }) {
  const of = useContext(ChatAgents).find((a) => a.session.key === agent);
  return of ? <AgentCard agent={of} /> : null;
}

const LINES_MS = 240;
const LINES_EASE = "cubic-bezier(0.2, 0.7, 0.2, 1)";

/**
 * The lines of `list` (its children marked `data-line="<key>"`, `list` their offset parent, cut at its edges) run on
 * as they change, by moving alone (no line is resized, nor the list): those that stay go from where they were to where
 * they are, carrying on from wherever they had got to; a new one comes with them from beyond the edge, and one gone
 * leaves with them, as a copy. With none moved, new and gone fade in place. As they are the first time.
 */
function useLinesMotion(list: RefObject<HTMLElement | null>): void {
  // Each line's place at rest and, on its way there, the motion and what it started from (how far off, how faint).
  type Line = { el: HTMLElement; top: number; left: number; run?: Animation; y?: number; faint?: number };
  const was = useRef<{ box: HTMLElement; lines: Map<string, Line> } | null>(null);
  useLayoutEffect(() => {
    const box = list.current;
    const before = was.current?.box === box ? was.current.lines : null;
    if (!box) return void (was.current = null);
    const lines = new Map<string, Line>();
    for (const el of box.querySelectorAll<HTMLElement>(":scope > [data-line]")) lines.set(el.dataset.line!, { el, top: el.offsetTop, left: el.offsetLeft });
    was.current = { box, lines };
    if (!before) return;
    // Where a motion cut short had got to: how far from its place still, and how faint; then it is ended.
    const cut = (line: Line) => {
      const done = line.run ? line.run.effect?.getComputedTiming().progress ?? 1 : 1;
      line.run?.cancel();
      return { y: (line.y ?? 0) * (1 - done), faint: 1 - (1 - (line.faint ?? 1)) * (1 - done) };
    };
    if (reducedMotion()) return void before.forEach(cut);
    const timing = { duration: LINES_MS, easing: LINES_EASE };
    // How far the lines ran on (the first that stays tells): what comes and what goes moves as far.
    const stays = [...lines.keys()].find((key) => before.has(key));
    const shift = stays === undefined ? 0 : before.get(stays)!.top - lines.get(stays)!.top;
    for (const [key, line] of lines) {
      const old = before.get(key);
      const at = old ? cut(old) : { y: 0, faint: 0 };
      // From where it was drawn (its place then, and how far it still was from it), as faint as it was.
      const y = old ? old.top + at.y - line.top : shift;
      if (Math.abs(y) < 0.5 && at.faint === 1) continue;
      const run = line.el.animate([{ transform: `translateY(${y}px)`, opacity: at.faint }, { transform: "translateY(0)", opacity: 1 }], timing);
      Object.assign(line, { run, y, faint: at.faint });
      void run.finished.then(() => { if (line.run === run) delete line.run; }, () => {});
    }
    // One gone: a copy of it where it was drawn, leaving as far as the others ran on.
    for (const [key, old] of before) {
      if (lines.has(key)) continue;
      const at = cut(old);
      const ghost = old.el.cloneNode(true) as HTMLElement;
      delete ghost.dataset.line;
      ghost.setAttribute("aria-hidden", "true");
      Object.assign(ghost.style, { position: "absolute", top: `${old.top}px`, left: `${old.left}px`, right: "0", pointerEvents: "none" });
      box.appendChild(ghost);
      const run = ghost.animate([{ transform: `translateY(${at.y}px)`, opacity: at.faint }, { transform: `translateY(${at.y - shift}px)`, opacity: 0 }], { ...timing, fill: "forwards" });
      void run.finished.then(() => ghost.remove(), () => ghost.remove());
    }
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
  // Its latest lines, three at most (the core's): what it did, then what it does now. Three once it has done as much,
  // so their room stays as it is while they run on (useLinesMotion).
  const latest = card?.latest ?? [];
  const lines = useRef<HTMLOListElement>(null);
  useLinesMotion(lines);
  const account = agent.account ?? agent.profile;
  const quota = agent.account?.quota?.state === "ok" ? agent.account.quota.windows : [];
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
      {latest.length > 0 && (
        <ol ref={lines} className={css.recent}>
          {latest.map((r) => <li key={r.key} data-line={r.key} data-now={r.now ? "" : undefined}>{r.text}</li>)}
        </ol>
      )}
      {card && <UsageTiles card={card} />}
      {(account || quota.length > 0) && (
        <div className={css.account}>
          <span className={css.accountName}>{account?.name}</span>
          <span className={css.chips}>
            {quota.map((w) => (
              <Tip key={w.label} label={<>{t("web-main.quota.left", { label: w.label, left: w.left })}{w.refills && <><br />{w.refills}</>}</>}>
                <QuotaChip window={w} marked={quota.length > 1} small />
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

/**
 * The figures that say most of what an agent used (cost, the cache's hit rate, how full its context is), large, side
 * by side: in its card, and in its execution history's details (ChatPage.tsx). None before it has made a call.
 */
export function UsageTiles({ card }: { card: AgentCardView }) {
  const context = card.context;
  if (!card.cost && !card.cache && !context) return null;
  return (
    <div className={css.tiles}>
      {card.cost && <span className={css.tile}><b>{card.cost}</b><small>{t("web-main.chat.agentCard.cost")}</small></span>}
      {card.cache && <span className={css.tile}><b>{card.cache.text}</b><small>{t("web-main.chat.agentCard.cache")}</small></span>}
      {/* How full, large; how much of how much on hover. */}
      {context && (context.unknown
        ? <span className={css.tile}><b>{context.text}</b><small>{t("web-main.chat.agentCard.context")}</small></span>
        : (
          <Tip label={context.text}>
            <span className={css.tile} data-level={context.level}><b>{Math.round(context.percent)}%</b><small>{t("web-main.chat.agentCard.context")}</small></span>
          </Tip>
        ))}
    </div>
  );
}
