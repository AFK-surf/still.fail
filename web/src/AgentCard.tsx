// An agent of the chat in brief, over its avatar while it is pointed at (Hover, Peeks.tsx): what it runs, where it
// stands and for how long, and what the core says of it (the `agentCard` view, views/brief.ts): what it has done, cost
// and used, its account and what is left of it, its jobs, what is wrong.
import { createContext, useContext, type ReactElement } from "react";
import { useAgentCard, type ChatAgent } from "./api.ts";
import { useStation } from "./station.tsx";
import { Hover } from "./Peeks.tsx";
import { AgentMark, Tip } from "./ui.tsx";
import { EdgeChip } from "./components.tsx";
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

/**
 * What it runs and where it stands now (for how long), then what the core says of it (the `agentCard` view): the
 * figures that say most (cost, the cache's hit rate, how full its context is) large, side by side; its account with
 * what is left of it; the rest (its turns, tokens) in a quiet line; its jobs and what is wrong under them.
 */
function AgentCard({ agent: key }: { agent: string }) {
  const agent = useContext(ChatAgents).find((a) => a.session.key === key);
  const card = useAgentCard(useStation().address, key).value;
  if (!agent) return null;
  const { session: s, wait } = agent;
  const account = agent.account ?? agent.profile;
  const quota = agent.account?.quota?.state === "ok" ? agent.account.quota.windows : [];
  const context = card?.context;
  const quiet = [card?.work, card?.tokens].filter(Boolean).join(" · ");
  return (
    <div className={css.agentCard}>
      <div className={css.head}>
        <AgentMark maker={s.maker} runtime={s.runtime} badge={agent.badge} badgeText={s.badgeText} size={28} />
        <span className={css.name}>{s.agentText}</span>
      </div>
      <p className={css.status} data-tone={s.tone}>
        {s.statusText}
        {wait
          ? <span className={css.elapsed}> · <Waited since={wait.since} seconds={wait.seconds} /></span>
          : agent.since ? <span className={css.elapsed}> · <Elapsed since={agent.since} /></span> : null}
      </p>
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
