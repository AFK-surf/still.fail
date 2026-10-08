// An agent of the chat in brief, over its avatar while it is pointed at (Hover, Peeks.tsx): what it runs and on which
// account, where it stands and for how long, what it has done, its jobs, and what is worth a look. All from the chat's
// view (the core words it, views/brief.ts): nothing is asked of the station.
import { createContext, useContext, type ReactElement } from "react";
import type { ChatAgent } from "./api.ts";
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

/** Only what says something: where it stands now and for how long, what it has done here, its jobs at work, and what
 * is worth a look (a quota running out, an account that cannot run, the disk filling up); each line only when it has one. */
function AgentCard({ agent: key }: { agent: string }) {
  const agent = useContext(ChatAgents).find((a) => a.session.key === key);
  if (!agent) return null;
  const { session: s, wait } = agent;
  const account = agent.account ?? agent.profile;
  const quota = agent.account?.quotaLine;
  // A quota running out is in its account's line already.
  const attention = quota ? agent.attention.filter((a) => a.kind !== "quota") : agent.attention;
  return (
    <div className={css.agentCard}>
      <div className={css.head}>
        <AgentMark maker={s.maker} runtime={s.runtime} badge={agent.badge} badgeText={s.badgeText} size={28} />
        <span className={css.who}>
          <span className={css.name}>{s.agentText}</span>
          {account && <span className={css.sub}>{account.name}{quota && <span className={css.quota} data-level={quota.level}> · {quota.text}</span>}</span>}
        </span>
      </div>
      <p className={css.status} data-tone={s.tone}>
        {s.statusText}
        {wait
          ? <span className={css.elapsed}> · <Waited since={wait.since} seconds={wait.seconds} /></span>
          : agent.since ? <span className={css.elapsed}> · <Elapsed since={agent.since} /></span> : null}
      </p>
      {(agent.workText || agent.jobsText) && (
        <div className={css.lines}>
          {agent.workText && <span>{agent.workText}</span>}
          {agent.jobsText && <span>{agent.jobsText}</span>}
        </div>
      )}
      {attention.length > 0 && (
        <div className={css.lines}>
          {attention.map((a, i) => <span key={i} className={css.attention} data-level={a.quota?.level ?? (a.kind === "disk" ? "amber" : "red")}>{a.text}</span>)}
        </div>
      )}
    </div>
  );
}
