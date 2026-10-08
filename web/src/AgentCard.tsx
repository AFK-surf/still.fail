// An agent of the chat in brief, over its avatar while it is pointed at (Hover, Peeks.tsx): what it runs, where it
// stands, the account it runs on, where it came from and when it was last active, as the chat's info has them
// (ChatPage's AgentLine). All from the chat's view: nothing is asked of the station.
import { createContext, useContext, type ReactElement, type ReactNode } from "react";
import type { ChatAgent } from "./api.ts";
import { Hover } from "./Peeks.tsx";
import { AgentMark, ConnectKindIcon, Time } from "./ui.tsx";
import { t } from "./i18n.ts";
import * as css from "./AgentCard.css.ts";

/** The agents of the chat whose messages are drawn (ChatRows). */
export const ChatAgents = createContext<readonly ChatAgent[]>([]);

/** `children` (an agent's avatar) with its card while it is pointed at; as it is for an agent not of this chat. */
export function AgentHover({ agent, children }: { agent: string | null | undefined; children: ReactElement }) {
  const agents = useContext(ChatAgents);
  if (!agent || !agents.some((a) => a.session.key === agent)) return children;
  return <Hover tile content={<AgentCard agent={agent} />}>{children}</Hover>;
}

function AgentCard({ agent: key }: { agent: string }) {
  const agent = useContext(ChatAgents).find((a) => a.session.key === key);
  if (!agent) return null;
  const { session: s, connect } = agent;
  const account = agent.account ?? agent.profile;
  const quota = agent.account?.quotaLine;
  const row = (label: string, value: ReactNode) => <div className={css.row}><dt>{label}</dt><dd>{value}</dd></div>;
  return (
    <div className={css.agentCard}>
      <div className={css.head}>
        <AgentMark maker={s.maker} runtime={s.runtime} badge={agent.badge} badgeText={s.badgeText} size={28} />
        <span className={css.who}>
          <span className={css.name}>{s.agentText}</span>
          <span className={css.sub}>{[s.runtimeText, s.processText].filter(Boolean).join(" · ")}</span>
        </span>
      </div>
      <p className={css.status} data-tone={s.tone}>{s.statusText}</p>
      <dl className={css.rows}>
        {account && row(t("web-main.chat.agentCard.account"), <>{account.name}{quota && <span className={css.quota} data-level={quota.level}> · {quota.text}</span>}</>)}
        {connect && row(t("web-main.chat.agentCard.from"), <span className={css.inline}><ConnectKindIcon kind={connect.kind} size={12} />{connect.name}</span>)}
        {s.time?.lastActiveAt && row(t("web-main.chat.agentCard.active"), <Time stamp={s.time.lastActiveAt} fixed />)}
      </dl>
    </div>
  );
}
