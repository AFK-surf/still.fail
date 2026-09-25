// Which station a piece of the client talks to. On a station's own admin page
// there is one, reached over HTTP; in ember cloud a workspace has several,
// each over iroh, and one page shows them together. Components read the
// station from context: its transport, its id (which keys the data cache) and
// its base path (which prefixes links).
import { createContext, useContext } from "react";
import { transport, type Transport } from "./transport.ts";

export interface Station {
  /** "local" on a station's own page; the station's key in ember cloud. */
  id: string;
  name: string;
  /** Path prefix of this station's pages: "" locally, /w/<ws>/s/<id> in ember cloud. */
  base: string;
  transport: Transport;
  /** False when ember cloud has not heard from it lately; its data is not requested. */
  online: boolean;
  /** Where settings live: /settings locally, the workspace's settings in ember cloud. */
  settings: string;
}

export const LOCAL_STATION: Station = {
  id: "local", name: "", base: "", online: true, settings: "/settings",
  // Resolved on each call, so a transport set at startup applies.
  transport: { request: (...a) => transport().request(...a), events: (...a) => transport().events(...a) },
};

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
export const MeContext = createContext<Me>({ id: "local", email: null });

/** Whether something was created by whoever is looking. */
export function useIsMine(): (creator: { id: string; email?: string | null } | null | undefined) => boolean {
  const me = useContext(MeContext);
  return (creator) => Boolean(creator) && (creator!.id === me.id || (Boolean(me.email) && creator!.email?.toLowerCase() === me.email!.toLowerCase()));
}

const FILTER = "ember.onlyMine";
/** The "only mine" filter, remembered across pages. */
export function readOnlyMine(): boolean {
  return localStorage.getItem(FILTER) === "1";
}
export function writeOnlyMine(value: boolean): void {
  localStorage.setItem(FILTER, value ? "1" : "0");
  window.dispatchEvent(new Event("ember-filter"));
}

/** People by email, from ember cloud's member list; empty on a station's own page. */
export interface Person { name: string; email: string; picture: string }
export const PeopleContext = createContext<ReadonlyMap<string, Person>>(new Map());

export function usePerson(): (email: string | null | undefined) => Person | undefined {
  const people = useContext(PeopleContext);
  return (email) => (email ? people.get(email.toLowerCase()) : undefined);
}
