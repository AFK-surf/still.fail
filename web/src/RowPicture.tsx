// Who is in a chat, as its row in the chat list shows it (the sidebar's Sidebar.tsx, the phone's mobile/Home.tsx): its
// agents' marks and its people's faces, small at the second line's end, in the order `lead` says (the chats view's
// `leading`).
import type { ChatItem, Person, RowAgent } from "./api.ts";
import { Avatar, ModelLogo, Tip } from "./ui.tsx";
import * as css from "./RowPicture.css.ts";
import { t } from "./i18n.ts";

/** A row's agents by their mark: those that look the same (one maker's models) are drawn once. */
function agentGroups(item: ChatItem) {
  const groups: { key: string; maker: RowAgent["maker"]; runtime: RowAgent["runtime"] }[] = [];
  for (const a of item.agents) {
    const key = a.maker?.id ?? a.runtime;
    if (!groups.some((g) => g.key === key)) groups.push({ key, maker: a.maker, runtime: a.runtime });
  }
  return groups;
}

/**
 * Who is in a chat, small at the end of its second line: its agents (one mark per maker) and its people, those that lead (`lead`)
 * first. The people only when they lead or someone other than the viewer is in the chat.
 */
export function RowAside({ item, lead, size, className }: { item: ChatItem; lead: "agents" | "people"; size: 16 | 18; className: string }) {
  const people = item.people ?? [];
  const groups = agentGroups(item);
  const withPeople = people.length > 0 && (lead === "people" || people.some((p) => !p.shown.mine));
  if (groups.length === 0 && !withPeople) return null;
  const shownAgents = groups.slice(0, 3);
  const agents = groups.length > 0 && (
    <Tip key="agents" label={item.agents.map((a) => a.agentText).join(t("web-main.list.separator"))} side="right"><span className={`${css.aside} ${className}`}>
      {shownAgents.map((g) => (
        <span key={g.key} className={css.asideAgent}>
          <ModelLogo maker={g.maker} runtime={g.runtime} size={size - 4} />
        </span>
      ))}
      {groups.length > shownAgents.length && <span className={css.asideMore}>+{groups.length - shownAgents.length}</span>}
    </span></Tip>
  );
  const shownPeople = people.slice(0, 3);
  const faces = withPeople && (
    <Tip key="people" label={item.peopleText ?? ""} side="right"><span className={`${css.aside} ${className}`}>
      {shownPeople.map((p) => <Face key={p.id} person={p} size={size} starter={people.length > 1 && p.id === item.creator?.id} />)}
      {people.length > shownPeople.length && <span className={css.asideMore}>+{people.length - shownPeople.length}</span>}
    </span></Tip>
  );
  return <>{lead === "people" ? [faces, agents] : [agents, faces]}</>;
}

/** A person's picture, round: their account's, else a lettered one; ringed when they started the chat. */
function Face({ person, size, starter }: { person: Person; size: number; starter?: boolean }) {
  const { shown } = person;
  return (
    <span className={css.face} data-starter={starter || undefined} style={{ width: size, height: size }}>
      {shown.picture
        ? <img src={shown.picture} alt="" width={size} height={size} referrerPolicy="no-referrer" />
        : <Avatar id={person.email ?? person.id} name={shown.name} size={size} />}
    </span>
  );
}
