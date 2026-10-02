// The site's theme, in its bar: the system's, light or dark (dark when none was chosen: the site's own look). The
// page's root says which (data-theme, set before the first paint by site/index.html), and the demo's app follows it.
import { useSyncExternalStore } from "react";
import { announceAppearance } from "../theme.ts";
import * as css from "./site.css.ts";

export type SiteTheme = "system" | "light" | "dark";
const KEY = "stillfail.site.theme";

function read(): SiteTheme {
  const saved = localStorage.getItem(KEY) ?? localStorage.getItem("ember.site.theme");
  return saved === "system" || saved === "light" ? saved : "dark";
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

const ICON = { width: 16, height: 16, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", strokeWidth: 1.75, strokeLinecap: "round", strokeLinejoin: "round", "aria-hidden": true } as const;
const CHOICES: { value: SiteTheme; label: string; icon: React.ReactNode }[] = [
  { value: "system", label: "跟随系统", icon: <svg {...ICON}><path d="M8 3.5H16Q20.5 3.5 20.5 8V12Q20.5 16 16 16H8Q3.5 16 3.5 12V8Q3.5 3.5 8 3.5Z M12 16V20.5 M8 20.5H16" /></svg> },
  { value: "light", label: "浅色", icon: <svg {...ICON}><circle cx="12" cy="12" r="4" /><path d="M12 2.5V4.5 M12 19.5V21.5 M2.5 12H4.5 M19.5 12H21.5 M5.3 5.3L6.7 6.7 M17.3 17.3L18.7 18.7 M5.3 18.7L6.7 17.3 M17.3 6.7L18.7 5.3" /></svg> },
  { value: "dark", label: "深色", icon: <svg {...ICON}><path d="M20 14.5A8.5 8.5 0 0 1 9.5 4 A8.5 8.5 0 1 0 20 14.5Z" /></svg> },
];

export function ThemeSwitch() {
  // Built to HTML as the default; in the browser, what this visitor chose.
  const theme = useSyncExternalStore((l) => { listeners.add(l); return () => listeners.delete(l); }, read, () => "dark" as SiteTheme);
  return (
    <div className={css.themeSwitch} role="radiogroup" aria-label="主题">
      {CHOICES.map((c) => (
        <button key={c.value} type="button" role="radio" aria-checked={theme === c.value} aria-label={c.label} title={c.label}
          className={css.themeChoice} onClick={() => choose(c.value)}>
          {c.icon}
        </button>
      ))}
    </div>
  );
}
