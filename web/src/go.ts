// Going to a page, and reading which is open, without following which page is open: react-router's useNavigate
// (outside a data router) reads the location, and its navigation context is made anew at every page change too, so
// everything that only goes somewhere when pressed (a row of the sidebar, a shortcut) was drawn again with each. The
// router's history is taken once (GoKeeper, under the router) and these go through it.
import { useContext, useLayoutEffect } from "react";
import { UNSAFE_NavigationContext, type NavigateOptions, type To } from "react-router";

export interface Go {
  (to: To, options?: NavigateOptions): void;
  (delta: number): void;
}

interface History {
  push(to: To, state?: unknown, options?: NavigateOptions): void;
  replace(to: To, state?: unknown, options?: NavigateOptions): void;
  go(delta: number): void;
  createHref?(to: To): string;
  location?: { pathname: string };
}

let history: History | null = null;

/** Under the router, once: what useGo and useHere go through. */
export function GoKeeper(): null {
  const navigator = useContext(UNSAFE_NavigationContext).navigator as History;
  // Before anything under it is pressed, and again should the router be another.
  history ??= navigator;
  useLayoutEffect(() => { history = navigator; }, [navigator]);
  return null;
}

/** Goes to a page, as useNavigate's function does for a whole path (`/w/…`; nothing here goes by a path relative to its route). */
const go = ((to: To | number, options?: NavigateOptions) => {
  if (!history) return;
  if (typeof to === "number") return history.go(to);
  if (options?.replace) history.replace(to, options.state, options);
  else history.push(to, options?.state, options);
}) as Go;

/** The path of the page open now, read when asked (a click), not followed. */
const here = () => history?.location?.pathname ?? window.location.pathname;

/** The app's own address of `to` (with the router's base), read when asked. */
export function hrefOf(to: To): string {
  return history?.createHref?.(to) ?? (typeof to === "string" ? to : "/");
}

export function useGo(): Go {
  return go;
}

export function useHere(): () => string {
  return here;
}
