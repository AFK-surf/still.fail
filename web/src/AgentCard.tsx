// An agent of the chat in brief, over its avatar while it is pointed at (Hover, Peeks.tsx): what it runs, where it
// stands and for how long, and what the core says of it (the `agentCard` view, views/brief.ts): what it has done, cost
// and used, its account and what is left of it, its jobs, what is wrong.
import { createContext, useContext, type ReactElement } from "react";
import { useAgentCard, type ChatAgent } from "./api.ts";
import { useStation } from "./station.tsx";
import { Hover } from "./Peeks.tsx";
import { AgentMark } from "./ui.tsx";
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

/** Where it stands now and for how long, then a row for each thing worth knowing of it, as the core words them (the
 * `agentCard` view): what it has done, cost and used, its account and quota, its jobs, what is wrong. */
function AgentCard({ agent: key }: { agent: string }) {
  const agent = useContext(ChatAgents).find((a) => a.session.key === key);
  const card = useAgentCard(useStation().address, key).value;
  if (!agent) return null;
  const { session: s, wait } = agent;
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
      {card && card.rows.length > 0 && (
        <dl className={css.rows}>
          {card.rows.map((r, i) => <div key={i} className={css.row}><dt>{r.label}</dt><dd data-level={r.level}>{r.value}</dd></div>)}
        </dl>
      )}
    </div>
  );
}
