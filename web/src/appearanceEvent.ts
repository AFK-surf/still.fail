// What tells the page's parts that follow the appearance (theme.ts useDark) to read it again, on its own: the official
// site sets the appearance itself and says so with it, without the app's prefs and core (site/ThemeSwitch.tsx), so
// that its own script stays small.
export const APPEARANCE_EVENT = "stillfail-appearance";

/** Tells the page's parts that follow the appearance to read it again: a page that sets it itself (the official site). */
export function announceAppearance(): void {
  window.dispatchEvent(new Event(APPEARANCE_EVENT));
}
