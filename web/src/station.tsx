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
}

export const LOCAL_STATION: Station = {
  id: "local", name: "", base: "", online: true,
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
