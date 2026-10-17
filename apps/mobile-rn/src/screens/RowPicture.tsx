// Who is in a chat, as its row in the list shows it (web/src/RowPicture.tsx): its agents' marks and its people's faces,
// small at the second line's end, in the order `lead` says (the chats view's `leading`).
import { View, type StyleProp, type ViewStyle } from "react-native";
import type { ChatItem, Maker, Person } from "../../../../web/src/core/shapes.ts";
import { t } from "../i18n";
import { Avatar, MakerIcon } from "../ui/Parts";
import { T } from "../ui/Text";
import { useC } from "../ui/Theme";

/** A row's agents by their mark: those that look the same (one maker's models) are drawn once. */
interface AgentGroup { key: string; maker: Maker | undefined; runtime: string }

function agentGroups(item: ChatItem): AgentGroup[] {
  const seen = new Set<string>();
  const out: AgentGroup[] = [];
  for (const a of item.agents) {
    const key = a.maker?.id ?? a.runtime;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ key, maker: a.maker, runtime: a.runtime });
  }
  return out;
}

/**
 * A person, round: their account's picture, else a lettered one; ringed in ink when they started the chat. `ring`: the
 * line round the face (Compose's border on its box, drawn over it), in `ringColor`.
 */
function Face({ person, size, starter, style, ringColor }: { person: Person; size: number; starter: boolean; style?: StyleProp<ViewStyle>; ringColor: string | null }) {
  const C = useC();
  return (
    <View style={[{ width: size, height: size, alignItems: "center", justifyContent: "center" }, style]}>
      <Avatar id={person.email ?? person.id} name={person.shown.name} size={size} picture={person.shown.picture} />
      {starter && <View style={{ position: "absolute", left: -2, top: -2, width: size + 4, height: size + 4, borderRadius: (size + 4) / 2, borderWidth: 1.5, borderColor: C.ink }} />}
      {ringColor && <View style={{ position: "absolute", left: 0, top: 0, width: size, height: size, borderRadius: size / 2, borderWidth: 1.5, borderColor: ringColor }} />}
    </View>
  );
}

/**
 * Who is in a chat, small at the end of its second line: its agents (a mark per maker) and its people, those that lead first. The
 * people only when they lead or someone other than the viewer is in the chat.
 */
export function RowAside({ item, lead, style }: { item: ChatItem; lead: string; style?: StyleProp<ViewStyle> }) {
  const people = item.people ?? [];
  const groups = agentGroups(item);
  const withPeople = people.length > 0 && (lead === "people" || people.some((p) => !p.shown.mine));
  if (groups.length === 0 && !withPeople) return null;
  return (
    <View style={[{ flexDirection: "row", alignItems: "center", gap: 6 }, style]}>
      {lead === "people" ? (
        <>
          {withPeople && <Faces item={item} people={people} />}
          {groups.length > 0 && <Agents item={item} groups={groups} />}
        </>
      ) : (
        <>
          {groups.length > 0 && <Agents item={item} groups={groups} />}
          {withPeople && <Faces item={item} people={people} />}
        </>
      )}
    </View>
  );
}

function Agents({ item, groups }: { item: ChatItem; groups: AgentGroup[] }) {
  const C = useC();
  const rest = groups.length - 3;
  return (
    <View
      accessible
      accessibilityLabel={item.agents.map((a) => a.agentText).join(t("web-main.list.separator"))}
      style={{ flexDirection: "row", alignItems: "center", gap: 4 }}
    >
      {groups.slice(0, 3).map((g) => <MakerIcon key={g.key} maker={g.maker} runtime={g.runtime} size={14} />)}
      {rest > 0 && <T size={12} color={C.muted}>{`+${rest}`}</T>}
    </View>
  );
}

function Faces({ item, people }: { item: ChatItem; people: Person[] }) {
  const C = useC();
  const shown = people.slice(0, 3);
  return (
    <View accessible accessibilityLabel={item.peopleText ?? ""} style={{ flexDirection: "row", alignItems: "center" }}>
      {shown.map((p, i) => {
        const starter = people.length > 1 && p.id === item.creator?.id;
        return (
          <Face
            key={p.id}
            person={p}
            size={18}
            starter={starter}
            ringColor={starter ? null : C.bg}
            style={[i > 0 && { transform: [{ translateX: -3 * i }] }, starter && { zIndex: 1 }]}
          />
        );
      })}
      {people.length > shown.length && (
        <T size={12} color={C.muted} style={{ transform: [{ translateX: -3 * (shown.length - 1) + 3 }] }}>{`+${people.length - shown.length}`}</T>
      )}
    </View>
  );
}
