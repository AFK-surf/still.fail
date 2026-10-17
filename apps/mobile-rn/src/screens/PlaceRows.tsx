// The rows of a place's list (PlacePage.tsx), as the desktop sidebar's (web SidebarList.tsx NavItem) and laid out as a
// chat's: a mark in a column of its own, the title and what is at that line's end, the lines under them starting where
// the title does; flat, under the chats' section headings. Only what is off is in colour.
import { useRef, type ReactNode } from "react";
import { Pressable, View } from "react-native";
import { app, MenuItem, MenuSpec } from "../AppState";
import { Icon, Icons } from "../ui/Icon";
import { T } from "../ui/Text";
import { useC, withAlpha } from "../ui/Theme";

/** What the page is and what it is for, said where its list is empty (the page has no note at its top). */
export function PlaceEmpty({ text, note }: { text: string; note?: string | null }) {
  const C = useC();
  return (
    <View style={{ alignSelf: "stretch", paddingHorizontal: 32, paddingVertical: 40, alignItems: "center", gap: 8 }}>
      <T size={14} color={C.muted} align="center">{text}</T>
      {note != null && <T size={13} color={C.subtle} align="center">{note}</T>}
    </View>
  );
}

const MARK = 16;
const GAP = 8;

/**
 * A row of a place's list, as the desktop sidebar's (web SidebarList.tsx NavItem) and laid out as a chat's: its `mark`
 * in a column of its own, its title and what is at that line's `end`, then `lines` under them from where the title
 * starts. `away`: what it is is not there now (its title faint). Pressed, the chats' pressed ground (no ripple).
 */
export function PlaceRow({ title, mark, onClick, away = false, end, lines }: {
  title: string;
  mark: ReactNode;
  onClick: (() => void) | null;
  away?: boolean;
  end?: ReactNode;
  lines?: ReactNode;
}) {
  const C = useC();
  return (
    <Pressable
      disabled={onClick == null}
      onPress={onClick ?? undefined}
      style={({ pressed }) => ({ alignSelf: "stretch", backgroundColor: pressed ? withAlpha(C.ink, 0.05) : "transparent", paddingLeft: 22, paddingRight: 16, paddingTop: 10, paddingBottom: 10 })}
    >
      <View style={{ height: 22, flexDirection: "row", alignItems: "center" }}>
        <View style={{ width: MARK, alignItems: "center", justifyContent: "center" }}>{mark}</View>
        <View style={{ width: GAP }} />
        <T size={16} line={22} color={C.ink} numberOfLines={1} style={{ flex: 1, minWidth: 0, opacity: away ? 0.5 : 1 }}>{title}</T>
        {end != null && <View style={{ paddingLeft: 8, flexDirection: "row", alignItems: "center", gap: 6 }}>{end}</View>}
      </View>
      <View style={{ paddingLeft: MARK + GAP }}>{lines}</View>
    </Pressable>
  );
}

/** A station's dot at a row's end: green while up, grey while away. */
export function OnlineDot({ online }: { online: boolean }) {
  const C = useC();
  return <View style={{ width: 7, height: 7, borderRadius: 3.5, backgroundColor: online ? C.green : C.subtle }} />;
}

/**
 * A filter in a place's top bar, as the chats' (Home.tsx): its menu under it, the chosen one ticked; the accent on the
 * icon while it narrows the list (anything but the first).
 */
export function BandFilter({ label, options, selected, onSelect }: { label: string; options: string[]; selected: number; onSelect: (i: number) => void }) {
  const C = useC();
  const box = useRef<View>(null);
  return (
    <View ref={box} collapsable={false} style={{ width: 34, height: 34, borderRadius: 17, overflow: "hidden" }}>
      <Pressable
        accessibilityLabel={`${label}: ${options[selected] ?? ""}`}
        android_ripple={{ color: withAlpha(C.ink, 0.1) }}
        onPress={() => box.current?.measureInWindow((x, y, width, height) => {
          // The menu is 180 wide (Sheet.tsx MenuHost): its right edge under the button's.
          const left = x + width - 180;
          app.menu = new MenuSpec({ left, top: y, right: left, bottom: y + height }, options.map((o, i) => new MenuItem(o, i === selected ? Icons.Check : null, () => onSelect(i))));
        })}
        style={{ width: 34, height: 34, alignItems: "center", justifyContent: "center" }}
      >
        <Icon icon={Icons.Filter} size={20} color={selected !== 0 ? C.accent : C.ink} />
      </Pressable>
    </View>
  );
}
