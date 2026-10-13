// Going to a page without following which page is open: react-router's useNavigate (outside a data router) reads the
// location, so everything that only goes somewhere when pressed (a row of the sidebar, a shortcut) was drawn again with
// every page change. These read the router's history, which stays the same.
import { useContext, useMemo } from "react";
import { UNSAFE_NavigationContext, type NavigateOptions, type To } from "react-router";

export interface Go {
  (to: To, options?: NavigateOptions): void;
  (delta: number): void;
}

interface History {
  push(to: To, state?: unknown, options?: NavigateOptions): void;
  replace(to: To, state?: unknown, options?: NavigateOptions): void;
  go(delta: number): void;
  location?: { pathname: string };
}

/**
 * Goes to a page, as useNavigate's function does for a whole path (`/w/…`; nothing here goes by a path relative to its
 * route), and is the same function while the router is.
 */
export function useGo(): Go {
  const history = useContext(UNSAFE_NavigationContext).navigator as History;
  return useMemo(() => ((to: To | number, options?: NavigateOptions) => {
    if (typeof to === "number") return history.go(to);
    if (options?.replace) history.replace(to, options.state, options);
    else history.push(to, options?.state, options);
  }) as Go, [history]);
}

/** The path of the page open now, read when asked (a click), not followed. */
export function useHere(): () => string {
  const history = useContext(UNSAFE_NavigationContext).navigator as History;
  return useMemo(() => () => history.location?.pathname ?? window.location.pathname, [history]);
}
