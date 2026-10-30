// A station's name in a line of words, its mark (./StationMark.tsx) before it when its workspace gave it one, as the
// chats' rows name it.
import { useMemo, type ReactNode } from "react";
import { Words, type WordsDrawn } from "@stillfail/ui/words.tsx";
import { useStationLook } from "./api.ts";
import { useTopicSelect } from "./core/react.ts";
import type { StationView } from "./core/shapes.ts";
import { StationMark } from "./StationMark.tsx";
import * as css from "./StationMark.css.ts";

export function StationNamed({ emoji, icon, name, size = 12 }: { emoji?: string | null | undefined; icon?: string | null | undefined; name: string; size?: number }) {
  return <>{(emoji || icon) && <StationMark emoji={emoji} icon={icon} size={size} className={css.inline} />}{name}</>;
}

/**
 * Its mark alone, by its address, before words about it: as the workspace's stations list has it; nothing without one.
 * `alone`: a picture of its own (a row's), the server icon without one.
 */
export function StationMarkAt({ station, size = 12, alone }: { station: string | null | undefined; size?: number; alone?: boolean }) {
  const look = useStationLook(station ?? null);
  if (alone) return <StationMark emoji={look?.emoji} icon={look?.icon} size={size} />;
  return look && (look.emoji || look.icon) ? <StationMark emoji={look.emoji} icon={look.icon} size={size} className={css.inline} /> : null;
}

/** Its name by its address, where only its name is at hand. */
export function StationNamedAt({ station, name, size }: { station: string | null | undefined; name: string; size?: number }) {
  return <><StationMarkAt station={station} {...(size ? { size } : {})} />{name}</>;
}

/** Words about a station (无法连接「fly」), its mark put before its name where they name it; the words alone otherwise. */
export function StationInWords({ station, text, size = 12 }: { station: string | null | undefined; text: string; size?: number }) {
  const look = useStationLook(station ?? null);
  return <LookInWords look={look} text={text} size={size} />;
}

/** The same with its look at hand (its name, emoji, icon). */
export function LookInWords({ look, text, size = 12 }: { look: Look | undefined; text: string; size?: number }) {
  const at = look && (look.emoji || look.icon) && look.name ? text.indexOf(look.name) : -1;
  if (!look || at < 0) return <>{text}</>;
  return <>{text.slice(0, at)}<StationNamed emoji={look.emoji} icon={look.icon} name={look.name} size={size} />{text.slice(at + look.name.length)}</>;
}

type Look = { name: string; emoji?: string | null | undefined; icon?: string | null | undefined };

/** A scope's stations that have a mark, as the words name them: the longer names first (one inside another's goes second). */
function useMarkedLooks(scope: string): Look[] {
  return useTopicSelect<StationView[], Look[]>({ topic: "stations", scope }, (s) => (s.value ?? [])
    .filter((v) => (v.emoji || v.icon) && v.name.trim().length > 0)
    .map((v) => ({ name: v.name, emoji: v.emoji, icon: v.icon }))
    .sort((a, b) => b.name.length - a.name.length), sameLooks);
}
const sameLooks = (a: Look[], b: Look[]) => a.length === b.length && a.every((x, i) => x.name === b[i]!.name && x.emoji === b[i]!.emoji && x.icon === b[i]!.icon);

/** Whether `name` at `at` in `text` stands as a word (not a part of a longer one: "Mac" in "MacBook"). */
const word = /[\p{L}\p{N}_]/u;
function standsAlone(text: string, at: number, name: string): boolean {
  const before = text[at - 1], after = text[at + name.length];
  const latin = (c: string | undefined) => c !== undefined && word.test(c) && c.charCodeAt(0) < 0x2e80;
  return !(latin(text[at]) && latin(before)) && !(latin(text[at + name.length - 1]) && latin(after));
}

/** Words of the app's (a toast, a wait's line), each of the scope's stations they name with its mark by its name. */
export function NamesMarked({ scope, text, size = 12 }: { scope: string; text: string; size?: number }) {
  const looks = useMarkedLooks(scope);
  if (looks.length === 0) return <>{text}</>;
  const out: ReactNode[] = [];
  let rest = text;
  for (let found = true; found && rest.length > 0;) {
    found = false;
    let best: { at: number; look: Look } | null = null;
    for (const look of looks) {
      for (let at = rest.indexOf(look.name); at >= 0; at = rest.indexOf(look.name, at + 1)) {
        if (!standsAlone(rest, at, look.name)) continue;
        if (!best || at < best.at) best = { at, look };
        break;
      }
    }
    if (best) {
      found = true;
      out.push(rest.slice(0, best.at), <StationNamed key={out.length} emoji={best.look.emoji} icon={best.look.icon} name={best.look.name} size={size} />);
      rest = rest.slice(best.at + best.look.name.length);
    }
  }
  out.push(rest);
  return <>{out}</>;
}

/** Below it, the shared parts' words (@stillfail/ui words.tsx: toasts, waits) name the scope's stations with their marks. */
export function StationWordsIn({ scope, children }: { scope: string; children: ReactNode }) {
  const drawn = useMemo<WordsDrawn>(() => function Named({ text }: { text: string }) { return <NamesMarked scope={scope} text={text} />; }, [scope]);
  return <Words.Provider value={drawn}>{children}</Words.Provider>;
}
