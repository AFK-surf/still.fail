// 外观: follow the system, or always light, or always dark — kept in this
// browser. The choice is data-theme on the root ("light"/"dark"; absent for the
// system), which the palette in styles/global.css.ts and the brand pictures follow.
import { useEffect, useState } from "react";

export type Appearance = "system" | "light" | "dark";
const KEY = "ember.appearance";
const EVENT = "ember-appearance";

export function readAppearance(): Appearance {
  // What the page shows, when it says: set from the choice before the first paint (index.html), or fixed by a page
  // that is always one (the official site is dark).
  const shown = document.documentElement.dataset.theme;
  if (shown === "light" || shown === "dark") return shown;
  const value = localStorage.getItem(KEY);
  return value === "light" || value === "dark" ? value : "system";
}

/** Puts the saved choice on the page; call once before the first render. */
export function applyAppearance(value: Appearance = readAppearance()): void {
  const root = document.documentElement;
  if (value === "system") delete root.dataset.theme;
  else root.dataset.theme = value;
}

export function setAppearance(value: Appearance): void {
  if (value === "system") localStorage.removeItem(KEY);
  else localStorage.setItem(KEY, value);
  applyAppearance(value);
  window.dispatchEvent(new Event(EVENT));
}

export function useAppearance(): [Appearance, (value: Appearance) => void] {
  const [value, set] = useState(readAppearance);
  useEffect(() => {
    const update = () => set(readAppearance());
    window.addEventListener(EVENT, update);
    window.addEventListener("storage", update);
    return () => {
      window.removeEventListener(EVENT, update);
      window.removeEventListener("storage", update);
    };
  }, []);
  return [value, setAppearance];
}

/** Whether the page shows dark now: the choice, or the system's when following it. */
export function useDark(): boolean {
  const [appearance] = useAppearance();
  const [system, setSystem] = useState(() => matchMedia("(prefers-color-scheme: dark)").matches);
  useEffect(() => {
    const media = matchMedia("(prefers-color-scheme: dark)");
    const update = () => setSystem(media.matches);
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, []);
  return appearance === "system" ? system : appearance === "dark";
}
