// 外观: follow the system, or always light, or always dark — kept on this device by the core (prefs.ts). What shows is
// data-theme on the root ("light"/"dark"; absent for the system), which the palette in styles/global.css.ts and the
// brand pictures follow. index.html sets it before the first paint from the copy of the core's last value
// (`stillfail.appearance`), so a dark page never paints light first; the core's value then keeps it.
import { useEffect, useState } from "react";
import type { Appearance } from "./core/shapes.ts";
import { onPrefs, prefs, setPrefs, usePrefs } from "./prefs.ts";
import { followMotion } from "@stillfail/ui/motion.ts";
import { APPEARANCE_EVENT as EVENT, announceAppearance } from "./appearanceEvent.ts";

export type { Appearance };

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
  announceAppearance();
}

/** The page shows the appearance kept on this device from now on, and moves as its motion setting says; call once
 * before the first render. */
export function followAppearance(): void {
  applyAppearance(prefs().appearance);
  onPrefs(() => applyAppearance(prefs().appearance));
  onPrefs(followMotion(() => prefs().motion));
}

/** The choice kept on this device, and how to change it. */
export function useAppearance(): [Appearance, (value: Appearance) => void] {
  return [usePrefs((p) => p.appearance), (appearance) => setPrefs({ appearance })];
}

/** 动画: as the system asks (none), reduced or full on this device, and how to change it. */
export function useMotionSetting(): ["system" | "reduce" | "full", (value: "system" | "reduce" | "full") => void] {
  const motion = usePrefs((p) => p.motion);
  return [motion === "reduce" || motion === "full" ? motion : "system", (value) => setPrefs({ motion: value === "system" ? null : value })];
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
