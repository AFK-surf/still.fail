// The site's theme, in its bar: the system's, light or dark (light when none was chosen). The
// page's root says which (data-theme, set before the first paint by site/index.html), and the demo's app follows it.
import { Monitor, Moon, Sun } from "@stillfail/ui/icons.tsx";
import { useSyncExternalStore } from "react";
import { announceAppearance } from "../theme.ts";
import * as css from "./site.css.ts";
import { useSay } from "./words.ts";

export type SiteTheme = "system" | "light" | "dark";
const KEY = "stillfail.site.theme";

function read(): SiteTheme {
  const saved = localStorage.getItem(KEY) ?? localStorage.getItem("ember.site.theme");
  return saved === "system" || saved === "dark" ? saved : "light";
}

const listeners = new Set<() => void>();
function choose(theme: SiteTheme): void {
  localStorage.setItem(KEY, theme);
  const root = document.documentElement;
  // The whole page changes at once: what eases its own colour on hover (a button's background) does not ease into
  // the new theme behind the rest (site.css.ts), for the frame the theme changes in.
  root.dataset.themeSwitching = "";
  if (theme === "system") delete root.dataset.theme;
  else root.dataset.theme = theme;
  void root.offsetWidth;
  requestAnimationFrame(() => requestAnimationFrame(() => delete root.dataset.themeSwitching));
  for (const listener of listeners) listener();
  announceAppearance();
}

const CHOICES: { value: SiteTheme; icon: React.ReactNode }[] = [
  { value: "system", icon: <Monitor size={16} /> },
  { value: "light", icon: <Sun size={16} /> },
  { value: "dark", icon: <Moon size={16} /> },
];

export function ThemeSwitch() {
  const say = useSay().theme;
  // Built to HTML as the default; in the browser, what this visitor chose.
  const theme = useSyncExternalStore((l) => { listeners.add(l); return () => listeners.delete(l); }, read, () => "light" as SiteTheme);
  return (
    <div className={css.themeSwitch} role="radiogroup" aria-label={say.label}>
      {CHOICES.map((c) => (
        <button key={c.value} type="button" role="radio" aria-checked={theme === c.value} aria-label={say[c.value]} title={say[c.value]}
          className={css.themeChoice} onClick={() => choose(c.value)}>
          {c.icon}
        </button>
      ))}
    </div>
  );
}
