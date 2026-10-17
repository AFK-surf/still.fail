// What the shared parts ask of the app they are drawn in (App.kt's AppState is it), so ui/ needs nothing of the app's
// pages. The app's store (src/AppState.ts `app`) is it.
import { createContext, useContext } from "react";
import type { CoreClient } from "../../../../web/src/core/client.ts";
import { app, type MenuSpec } from "../AppState";

export interface UiHost {
  /** The core, for what a part fetches itself (a picture by its URL). */
  readonly core: CoreClient;

  /** Opens a link as the app does (still.fail's own in the app, the rest by the system); `orElse` when it cannot. */
  follow(url: string, orElse: () => void): void;

  /** Says something at the bottom of the screen for a moment. */
  note(text: string): void;

  /** The long-press menu open over everything (Sheet.tsx MenuHost), or none. */
  menu: MenuSpec | null;
}

/**
 * The app is the host (AppState is a UiHost, as AppState.kt is), unless something provides another. Null by default,
 * the app read when asked: this module loads inside AppState's own imports, before `app` is made.
 */
export const LocalUi = createContext<UiHost | null>(null);

/** LocalUi.current. */
export function useUi(): UiHost {
  return useContext(LocalUi) ?? app;
}
