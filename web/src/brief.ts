// An execution history's steps and thoughts in brief (the core holds what a station pushed of them: what names them, docs/
// client-core.md): what is behind one is read whole as it shows, opened, on either page (History.tsx, mobile/History.tsx).
import { createContext, useContext, useEffect, useState } from "react";
import { failure } from "./toast.tsx";

/** Reads whole the transcript entries of a step or thought in brief (`history.detail`): its history's (api.ts). */
export const ReadWhole = createContext<(entries: number[]) => Promise<unknown>>(() => Promise.resolve());

/** How long what was read whole has to show before what is held is taken for all there is (it came back in brief). */
const SETTLE_MS = 1000;

/**
 * Where reading whole a step or thought shown in brief stands: it is read as it shows, and again when it is in brief anew
 * (its result came, in brief). `null` with nothing to wait for: it is whole, or was read and is in brief still a moment
 * later (what is held is all there is); else being read, or why it could not be (`error`).
 */
export function useWhole(brief: boolean, entries: number[]): { error: string | null } | null {
  const detail = useContext(ReadWhole);
  const key = entries.join(" ");
  const [read, setRead] = useState<{ key: string; error: string | null; settled: boolean } | null>(null);
  useEffect(() => {
    if (!brief) return;
    let gone = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    setRead({ key, error: null, settled: false });
    detail(entries).then(
      () => { if (!gone) timer = setTimeout(() => setRead({ key, error: null, settled: true }), SETTLE_MS); },
      (error: unknown) => { if (!gone) setRead({ key, error: failure(error), settled: false }); },
    );
    return () => { gone = true; clearTimeout(timer); };
  }, [brief, key]); // eslint-disable-line react-hooks/exhaustive-deps
  if (!brief || (read?.key === key && read.settled)) return null;
  return { error: read?.key === key ? read.error : null };
}
