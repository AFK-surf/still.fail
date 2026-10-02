// Which station a piece of the client talks to. A workspace has several, and
// one page shows them together. Components read the station from context: its
// address (how the client core names it) and its base path (which prefixes links).
import { createContext, useContext } from "react";
import { setPrefs, usePrefs } from "./prefs.ts";

export interface Station {
  /** The station's key in its workspace. */
  id: string;
  name: string;
  /** Path prefix of this station's pages: /w/<ws>/s/<id>. */
  base: string;
  /** How the client core names it: "<workspace>/<station>". */
  address: string;
  /** False when still.fail cloud has not heard from it lately. */
  online: boolean;
  /** Where settings live: the workspace's settings. */
  settings: string;
}

/** Where a station's profiles are listed: the workspace's one Profile page (every station's, each with its own add button). */
export function profilesPage(station: Station): string {
  return `${station.settings}/profiles`;
}

/** Path prefix of a station's pages, from its address. */
export function stationBase(address: string): string {
  const [workspace, station] = address.split("/");
  return `/w/${workspace}/s/${station}`;
}

/** The scope a station belongs to: its workspace. */
export function scopeOf(address: string): string {
  return address.split("/")[0]!;
}

// Every page that talks to a station is under one's provider (cloud/workspace.tsx); this is only a placeholder.
export const StationContext = createContext<Station>({ id: "", name: "", base: "", address: "", online: false, settings: "" });

export function useStation(): Station {
  return useContext(StationContext);
}

/** Builds links to this station's pages. */
export function useLink(): (path: string) => string {
  const { base } = useStation();
  return (path) => `${base}${path}`;
}

/** Who is looking: the account's email. */
export interface Me { id: string; email: string | null }

/** The "only mine" filter, kept on this device (prefs.ts). */
export function useOnlyMine(): [boolean, (value: boolean) => void] {
  return [usePrefs().onlyMine, (onlyMine) => setPrefs({ onlyMine })];
}

/** What the chat list shows: all, the viewer's (我参与的) or the watching ones (监控中), kept on this device (prefs.ts). */
export type ChatFilter = "all" | "mine" | "watching";

export function useChatFilter(): [ChatFilter, (value: ChatFilter) => void] {
  const prefs = usePrefs();
  const filter: ChatFilter = prefs.onlyWatching ? "watching" : prefs.onlyMine ? "mine" : "all";
  return [filter, (value) => setPrefs({ onlyMine: value === "mine", onlyWatching: value === "watching" })];
}

/** People by email, from still.fail cloud's member list. */
export interface Person { name: string; email: string; picture: string }
export const PeopleContext = createContext<ReadonlyMap<string, Person>>(new Map());

export function usePerson(): (email: string | null | undefined) => Person | undefined {
  const people = useContext(PeopleContext);
  return (email) => (email ? people.get(email.toLowerCase()) : undefined);
}
