// What the share page has of web/src/draft.ts (in its place: web/vite.share.config.ts), for Viz.tsx: there is no
// composer to put a widget's words in.
import { createContext } from "react";

export const DraftKey = createContext<string | undefined>(undefined);

export function offerToDraft(_key: string, _offer: unknown): boolean {
  return false;
}
