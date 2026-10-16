// Whether a part is drawn in the narrow app (a phone's way of doing things), apart from the app (app.tsx) so what only
// asks this (FilePreview.tsx, which a published chat's page has too) does not bring the app with it.
import { createContext, useContext } from "react";
import type { MobileApp } from "./app.tsx";

export const MobileContext = createContext<MobileApp | null>(null);

/** Whether this is drawn in the narrow app (a phone's way of doing things: ../annotate/ImageMarks.tsx). */
export function useNarrow(): boolean {
  return useContext(MobileContext) !== null;
}
