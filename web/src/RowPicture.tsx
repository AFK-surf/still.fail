// Who is in a chat, as its row in the chat list shows it (the sidebar's Sidebar.tsx, the phone's mobile/Home.tsx): the
// picture, its agents' marks or its people's faces as `lead` says (rowLead.ts), and at the title's end the other.
import type { ReactNode } from "react";
import type { ChatItem, Person, RowAgent } from "./api.ts";
import { Mark } from "./brand.tsx";
import { Avatar, ModelLogo, Tip } from "./ui.tsx";
import * as css from "./RowPicture.css.ts";

/**
 * Who is in a chat, as its row's picture: what leads (`lead`), its agents (one mark per maker) or its people, laid out
 * by Cluster (all of them on hover). With no one to lead (a station that does not say who, a chat with no agent yet),
 * the other, then ember's mark.
 */
export function RowPicture({ item, lead, box, className }: { item: ChatItem; lead: "agents" | "people"; box: 30 | 40; className: string }) {
  const people = item.people ?? [];
  const agents = item.agents;
  const byPeople = lead === "people" ? people.length > 0 : agents.length === 0 && people.length > 0;
  const groups = agentGroups(item);
  if (byPeople) {
    return (
      <Tip label={peopleLabel(item)}><span className={className}>
        <Cluster box={box} count={people.length} draw={(i, size) => {
          const p = people[i]!;
          return <Face key={p.id} person={p} size={size} starter={people.length > 1 && p.id === item.creator?.id} />;
        }} />
      </span></Tip>
    );
  }
  return (
    <Tip label={agents.map((a) => a.agentText).join("、") || undefined}><span className={className}>
      {groups.length === 0
        ? <span className={css.cell} style={{ inset: 0 }} aria-hidden="true"><Mark size={box === 30 ? 20 : 26} /></span>
        : <Cluster box={box} count={groups.length} draw={(i, size) => {
          const g = groups[i]!;
          return <ModelLogo key={g.key} maker={g.maker} runtime={g.runtime} size={size === box ? box - (box === 30 ? 4 : 12) : size - 4} />;
        }} />}
    </span></Tip>
  );
}

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
 * Where each of a picture's cells goes in its square ([left, top, size]), by its size (the sidebar's 30px, the phone's
 * 40px) and how many there are.
 */
const CELLS: Record<30 | 40, Record<number, [number, number, number][]>> = {
  30: {
    1: [[0, 0, 30]],
    2: [[0, 0, 18], [12, 12, 18]],
    3: [[8, 0, 14], [0, 16, 14], [16, 16, 14]],
    4: [[0, 0, 14], [16, 0, 14], [0, 16, 14], [16, 16, 14]],
  },
  40: {
    1: [[0, 0, 40]],
    2: [[0, 0, 24], [16, 16, 24]],
    3: [[11, 0, 18], [0, 22, 18], [22, 22, 18]],
    4: [[0, 0, 18], [22, 0, 18], [0, 22, 18], [22, 22, 18]],
  },
};

/**
 * Several in one picture: one fills it; two overlap corner to corner; three in a triangle, four in a square; more, the
 * fourth cell counts the rest.
 */
function Cluster({ box, count, draw }: { box: 30 | 40; count: number; draw: (index: number, size: number) => ReactNode }) {
  const cells = CELLS[box][Math.min(count, 4)]!;
  const more = count > 4 ? count - 3 : 0;
  const drawn = more ? cells.length - 1 : cells.length;
  return (
    <>
      {cells.map(([left, top, size], i) => (
        <span key={i} className={css.cell} data-overlap={count === 2 && i === 1 || undefined}
          style={{ left, top, width: size, height: size }} aria-hidden="true">
          {i < drawn ? draw(i, size) : <span className={css.more} style={{ fontSize: size >= 24 ? 12 : size >= 18 ? 10 : 9 }}>+{more}</span>}
        </span>
      ))}
    </>
  );
}

/**
 * What does not lead, small at the title's end: the agents beside the people; the people beside the agents, only when
 * someone other than the viewer is in the chat.
 */
export function RowAside({ item, lead, size, className }: { item: ChatItem; lead: "agents" | "people"; size: 16 | 18; className: string }) {
  const people = item.people ?? [];
  if (lead === "people" && people.length > 0) {
    const groups = agentGroups(item);
    if (groups.length === 0) return null;
    const shown = groups.slice(0, 3);
    const rest = groups.length - shown.length;
    return (
      <Tip label={item.agents.map((a) => a.agentText).join("、")} side="right"><span className={`${css.aside} ${className}`}>
        {shown.map((g) => (
          <span key={g.key} className={css.asideAgent}>
            <ModelLogo maker={g.maker} runtime={g.runtime} size={size - 4} />
          </span>
        ))}
        {rest > 0 && <span className={css.asideMore}>+{rest}</span>}
      </span></Tip>
    );
  }
  if (!people.some((p) => !p.shown.mine)) return null;
  const shown = people.slice(0, 3);
  return (
    <Tip label={peopleLabel(item)} side="right"><span className={`${css.aside} ${className}`}>
      {shown.map((p) => <Face key={p.id} person={p} size={size} starter={people.length > 1 && p.id === item.creator?.id} />)}
      {people.length > shown.length && <span className={css.asideMore}>+{people.length - shown.length}</span>}
    </span></Tip>
  );
}

/** A chat's people in words, who started it said: "小王 发起 · Lina、你". */
function peopleLabel(item: ChatItem): string {
  const people = item.people ?? [];
  const starter = people.find((p) => p.id === item.creator?.id);
  const rest = people.filter((p) => p !== starter).map((p) => p.shown.display);
  return [starter && `${starter.shown.display} 发起`, rest.join("、")].filter(Boolean).join(" · ");
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
