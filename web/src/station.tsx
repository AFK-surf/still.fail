// Which station a piece of the client talks to. On a station's own admin page
// there is one, "local"; in ember cloud a workspace has several, and one page
// shows them together. Components read the station from context: its address
// (how the client core names it) and its base path (which prefixes links).
import { createContext, useContext, useEffect, useState } from "react";

export interface Station {
  /** "local" on a station's own page; the station's key in ember cloud. */
  id: string;
  name: string;
  /** Path prefix of this station's pages: "" locally, /w/<ws>/s/<id> in ember cloud. */
  base: string;
  /** How the client core names it: "local", or "<workspace>/<station>". */
  address: string;
  /** False when ember cloud has not heard from it lately. */
  online: boolean;
  /** Where settings live: /settings locally, the workspace's settings in ember cloud. */
  settings: string;
}

export const LOCAL_STATION: Station = { id: "local", name: "", base: "", address: "local", online: true, settings: "/settings" };

/**
 * Where a station's profiles are listed: in ember cloud, the workspace's one Profile page (every station's, each with
 * its own add button); on a station's own page, its list.
 */
export function profilesPage(station: Station): string {
  return station.address === "local" ? "/settings/accounts" : `${station.settings}/profiles`;
}

/** Path prefix of a station's pages, from its address. */
export function stationBase(address: string): string {
  if (address === "local") return "";
  const [workspace, station] = address.split("/");
  return `/w/${workspace}/s/${station}`;
}

/** The scope a station belongs to: its workspace, or "local". */
export function scopeOf(address: string): string {
  return address === "local" ? "local" : address.split("/")[0]!;
}

export const StationContext = createContext<Station>(LOCAL_STATION);

export function useStation(): Station {
  return useContext(StationContext);
}

/** Builds links to this station's pages. */
export function useLink(): (path: string) => string {
  const { base } = useStation();
  return (path) => `${base}${path}`;
}

/** Who is looking: on a station's own page "local"; in ember cloud the account's email. */
export interface Me { id: string; email: string | null }

const FILTER = "ember.onlyMine";
/** The "only mine" filter, remembered across pages. */
export function readOnlyMine(): boolean {
  return localStorage.getItem(FILTER) === "1";
}
export function writeOnlyMine(value: boolean): void {
  localStorage.setItem(FILTER, value ? "1" : "0");
  window.dispatchEvent(new Event("ember-filter"));
}

export function useOnlyMine(): [boolean, (value: boolean) => void] {
  const [value, setValue] = useState(readOnlyMine);
  useEffect(() => {
    const update = () => setValue(readOnlyMine());
    window.addEventListener("ember-filter", update);
    return () => window.removeEventListener("ember-filter", update);
  }, []);
  return [value, writeOnlyMine];
}

/** People by email, from ember cloud's member list; empty on a station's own page. */
export interface Person { name: string; email: string; picture: string }
export const PeopleContext = createContext<ReadonlyMap<string, Person>>(new Map());

export function usePerson(): (email: string | null | undefined) => Person | undefined {
  const people = useContext(PeopleContext);
  return (email) => (email ? people.get(email.toLowerCase()) : undefined);
}
