// The station of the machine the desktop app is on ("<workspace>/<station>"), asked of the app once: its files can be
// shown in Finder (Peeks.tsx), and files dropped from Finder can be named by their path there (Chat.tsx). Null in a
// browser, or in an app that cannot say.
import { useEffect, useState } from "react";
import { useTopicSelect } from "./core/react.ts";
import type { StationView } from "./core/shapes.ts";

let asked: Promise<string | null> | null = null;

export function thisMachine(): Promise<string | null> {
  const desktop = window.stillfailDesktop;
  if (!desktop?.station) return Promise.resolve(null);
  asked ??= desktop.station.state().then((s) => {
    const v = s as { workspace?: string; station?: string } | null;
    return v?.workspace && v.station ? `${v.workspace}/${v.station}` : null;
  }, () => null);
  return asked;
}

/** The address of the station of the machine the page is on, once the app has said (null until then, or none). */
export function useThisMachineAddress(): string | null {
  const [here, setHere] = useState<string | null>(null);
  useEffect(() => {
    let live = true;
    void thisMachine().then((a) => { if (live) setHere(a); });
    return () => { live = false; };
  }, []);
  return here;
}

/** This machine's station, with its name, when it is one of the workspace of `station` (the page's): else null. */
export function useThisMachine(station: string): { station: string; name: string } | null {
  const here = useThisMachineAddress();
  const scope = station.split("/")[0] ?? "";
  const name = useTopicSelect<StationView[], string | null>(here && here.split("/")[0] === scope ? { topic: "stations", scope } : null, (s) => s.value?.find((x) => x.station === here)?.name ?? null);
  return here && name !== null ? { station: here, name } : null;
}
