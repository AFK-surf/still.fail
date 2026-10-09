// An agent of the chat in brief, over its avatar while it is pointed at (Hover, Peeks.tsx): what it runs, where it
// stands and for how long, and what the core says of it (the `agentCard` view, views/brief.ts): what it has done, cost
// and used, its account and what is left of it, its jobs, what is wrong.
import { createContext, useContext, type ReactElement } from "react";
import { useAgentCard, type ChatAgent } from "./api.ts";
import { useStation } from "./station.tsx";
import { Hover } from "./Peeks.tsx";
import { AgentMark } from "./ui.tsx";
import { EdgeChip, QuotaRing, Ring } from "./components.tsx";
import { t } from "./i18n.ts";
import { Elapsed, Waited } from "./Chat.tsx";
import * as css from "./AgentCard.css.ts";

/** The agents of the chat whose messages are drawn (ChatRows). */
export const ChatAgents = createContext<readonly ChatAgent[]>([]);

/** `children` (an agent's avatar) with its card while it is pointed at; as it is for an agent not of this chat. */
export function AgentHover({ agent, children }: { agent: string | null | undefined; children: ReactElement }) {
  const agents = useContext(ChatAgents);
  if (!agent || !agents.some((a) => a.session.key === agent)) return children;
  return <Hover tile content={<AgentCard agent={agent} />}>{children}</Hover>;
}

/** Which way the card is drawn, while one is picked (`?card=a|b|c`). */
const VARIANT = typeof location === "undefined" ? "a" : new URLSearchParams(location.search).get("card") ?? "a";

/**
 * What it runs and where it stands now (for how long), then what the core says of it (the `agentCard` view): the
 * figures that say most (cost, the cache's hit rate, how full its context is) and what is left of its account, drawn;
 * the rest (its turns, tokens, account) in a quiet line; its jobs and what is wrong under them.
 */
function AgentCard({ agent: key }: { agent: string }) {
  const agent = useContext(ChatAgents).find((a) => a.session.key === key);
  const card = useAgentCard(useStation().address, key).value;
  if (!agent) return null;
  const { session: s, wait } = agent;
  const account = agent.account ?? agent.profile;
  const quota = agent.account?.quota?.state === "ok" ? agent.account.quota.windows : [];
  const cost = card?.cost;
  const quiet = [card?.work, card?.tokens, account?.name].filter(Boolean).join(" · ");
  const status = (
    <p className={css.status} data-tone={s.tone}>
      {s.statusText}
      {wait
        ? <span className={css.elapsed}> · <Waited since={wait.since} seconds={wait.seconds} /></span>
        : agent.since ? <span className={css.elapsed}> · <Elapsed since={agent.since} /></span> : null}
    </p>
  );
  const notes = (card?.jobs || (card?.attention.length ?? 0) > 0) && (
    <div className={css.notes}>
      {card?.jobs && <span>{card.jobs}</span>}
      {card?.attention.map((a, i) => <span key={i} data-level={a.level}>{a.text}</span>)}
    </div>
  );
  return (
    <div className={css.agentCard} data-variant={VARIANT}>
      <div className={css.head}>
        <AgentMark maker={s.maker} runtime={s.runtime} badge={agent.badge} badgeText={s.badgeText} size={28} />
        <span className={css.name}>{s.agentText}</span>
        {VARIANT !== "a" && cost && <span className={css.headCost}>{cost}</span>}
      </div>
      {status}
      {VARIANT === "a" && (cost || card?.cache || card?.context) && (
        <div className={css.tiles}>
          {cost && <span className={css.tile}><b>{cost}</b><small>{t("web-main.chat.agentCard.cost")}</small></span>}
          {card?.cache && <span className={css.tile}><b>{card.cache.text}</b><small>{t("web-main.chat.agentCard.cache")}</small></span>}
          {card?.context && <span className={css.tile} data-level={card.context.level}><b>{card.context.unknown ? card.context.text : `${Math.round(card.context.percent)}%`}</b><small>{t("web-main.chat.agentCard.context")}{card.context.unknown ? "" : ` · ${card.context.text}`}</small></span>}
        </div>
      )}
      {VARIANT === "a" && (account || quota.length > 0) && (
        <div className={css.account}>
          <span className={css.accountName}>{account?.name}</span>
          <span className={css.chips}>{quota.map((w) => <EdgeChip key={w.label} fill={w.left} level={w.level} mark={quota.length > 1 ? w.mark : null} label={t("web-main.quota.left", { label: w.label, left: w.left })} small bare />)}</span>
        </div>
      )}
      {VARIANT === "b" && (
        <div className={css.rings}>
          {card?.cache && <span className={css.ringCell}><Ring percent={Math.round(card.cache.percent)} level="ok" size={36} label="" /><small>{t("web-main.chat.agentCard.cache")}</small></span>}
          {card?.context && !card.context.unknown && <span className={css.ringCell}><Ring percent={Math.round(card.context.percent)} level={card.context.level} size={36} label="" /><small>{t("web-main.chat.agentCard.context")}</small></span>}
          {quota.map((w) => <span key={w.label} className={css.ringCell}><QuotaRing left={w.left} level={w.level} size={36} /><small>{w.label}</small></span>)}
        </div>
      )}
      {VARIANT === "c" && (
        <div className={css.bars}>
          {card?.cache && <Bar label={t("web-main.chat.agentCard.cache")} percent={card.cache.percent} level="ok" text={card.cache.text} />}
          {card?.context && <Bar label={t("web-main.chat.agentCard.context")} percent={card.context.unknown ? 0 : card.context.percent} level={card.context.level} text={card.context.text} />}
          {quota.map((w) => <Bar key={w.label} label={w.label} percent={w.left} level={w.level} text={t("web-main.chat.agentCard.left", { left: w.left })} />)}
        </div>
      )}
      {(VARIANT === "a" ? [card?.work, card?.tokens].filter(Boolean).join(" · ") : quiet) && (
        <p className={css.quiet}>{VARIANT === "a" ? [card?.work, card?.tokens].filter(Boolean).join(" · ") : quiet}</p>
      )}
      {notes}
    </div>
  );
}

function Bar({ label, percent, level, text }: { label: string; percent: number; level: string; text: string }) {
  return (
    <div className={css.bar} data-level={level}>
      <span className={css.barLabel}>{label}</span>
      <span className={css.barTrack}><i style={{ width: `${Math.max(0, Math.min(100, percent))}%` }} /></span>
      <span className={css.barText}>{text}</span>
    </div>
  );
}
