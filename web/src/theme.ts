// 外观: follow the system, or always light, or always dark — kept on this device by the core (prefs.ts). What shows is
// data-theme on the root ("light"/"dark"; absent for the system), which the palette in styles/global.css.ts and the
// brand pictures follow. index.html sets it before the first paint from the copy of the core's last value
// (`stillfail.appearance`), so a dark page never paints light first; the core's value then keeps it.
import { useEffect, useState } from "react";
import type { Appearance } from "./core/shapes.ts";
import { onPrefs, prefs, setPrefs, usePrefs } from "./prefs.ts";

export type { Appearance };
const EVENT = "stillfail-appearance";

/** What the page shows: its root's choice, or the system's when it says none. */
function shown(): Appearance {
  const theme = document.documentElement.dataset.theme;
  return theme === "light" || theme === "dark" ? theme : "system";
}

/** Puts a choice on the page. */
function applyAppearance(value: Appearance): void {
  const root = document.documentElement;
  if (value === shown()) return;
  if (value === "system") delete root.dataset.theme;
  else root.dataset.theme = value;
  window.dispatchEvent(new Event(EVENT));
}

/** The page shows the appearance kept on this device from now on; call once before the first render. */
export function followAppearance(): void {
  applyAppearance(prefs().appearance);
  onPrefs(() => applyAppearance(prefs().appearance));
}

/** Tells the page's parts that follow the appearance to read it again: a page that sets it itself (the official site). */
export function announceAppearance(): void {
  window.dispatchEvent(new Event(EVENT));
}

/** The choice kept on this device, and how to change it. */
export function useAppearance(): [Appearance, (value: Appearance) => void] {
  return [usePrefs().appearance, (appearance) => setPrefs({ appearance })];
}

/** Whether the page shows dark now: its choice, or the system's when following it. */
export function useDark(): boolean {
  const [appearance, setShown] = useState(shown);
  const [system, setSystem] = useState(() => matchMedia("(prefers-color-scheme: dark)").matches);
  useEffect(() => {
    const media = matchMedia("(prefers-color-scheme: dark)");
    const update = () => setSystem(media.matches);
    const again = () => setShown(shown());
    media.addEventListener("change", update);
    window.addEventListener(EVENT, again);
    return () => {
      media.removeEventListener("change", update);
      window.removeEventListener(EVENT, again);
    };
  }, []);
  return appearance === "system" ? system : appearance === "dark";
}
