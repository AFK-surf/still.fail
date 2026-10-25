// What ⌘K's list offers besides chats and the keys' actions (Switcher.tsx): a page says what can be done from it now
// (its settings, updating its station) with useCommands, as it says what its keys do with useShortcut. The core names
// what it knows by its id (`commands.find`: updating, relaying a chat) and finds what is typed among them all.
import { useEffect, useRef, type ComponentType } from "react";
import type { IconProps } from "@stillfail/ui/icons.tsx";

export interface Command {
  /** Its own among the list's ("settings/appearance"); also matched by what is typed. */
  id: string;
  icon: ComponentType<IconProps>;
  /** One the core does not name (a settings page, a station's files): its name, its part of ⌘K's list, the other
   *  words it is found by (its name in English, as an id is), and whether only once something is typed. */
  label?: string;
  group?: "chat" | "update" | "settings";
  words?: string;
  typed?: boolean;
  /** What the core's name of it takes: the version an update goes to, the station updated. */
  version?: string;
  station?: string;
  run(): void;
}

const lists = new Set<{ current: Command[] }>();

/** The commands offered while this component is mounted, as last given. */
export function useCommands(commands: Command[]): void {
  const latest = useRef(commands);
  latest.current = commands;
  useEffect(() => {
    lists.add(latest);
    return () => { lists.delete(latest); };
  }, []);
}

/** The commands offered now. */
export function commands(): Command[] {
  return [...lists].flatMap((list) => list.current);
}
