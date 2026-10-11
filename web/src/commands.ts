// What ⌘K's list offers besides chats and the keys' actions (Switcher.tsx): a page says what can be done from it now
// (its settings, updating its station) with useCommands, as it says what its keys do with useShortcut.
import { useEffect, useRef, type ComponentType } from "react";
import type { IconProps } from "./icons.tsx";

export interface Command {
  /** Its own among the list's ("settings/appearance"); also matched by what is typed. */
  id: string;
  label: string;
  icon: ComponentType<IconProps>;
  /** Other words it is found by (its name in English, as an id is). */
  words?: string;
  /** Only once something is typed: one of many alike (a settings page), or rarely wanted. */
  typed?: boolean;
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
