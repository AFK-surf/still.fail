// Styles are written in TypeScript beside what they style (Sidebar.css.ts for Sidebar.tsx, vanilla-extract): each class
// is scoped to its file, so no two can collide, and a rule for an element's state sits with the element's other rules.
// theme.css, app.css and mobile.css are the styles from before, in a layer (`legacy`) under these, being moved over.
//
// The palette, type sizes, radii and motion of theme.css, for those styles: `vars.muted` is `var(--muted)`. The values
// stay in theme.css, which switches them with the theme; this only names them.
import { createGlobalThemeContract } from "@vanilla-extract/css";

const names = [
  "font-body", "font-mono",
  "canvas", "sidebar", "list", "text", "muted", "subtle", "line", "line-strong", "hover", "selected", "paper",
  "accent", "accent-text", "accent-bg", "blue", "blue-bg", "code-inline", "green", "green-bg", "amber", "amber-bg",
  "red", "red-bg", "neutral-bg", "overlay", "shadow", "primary", "primary-hover", "on-primary", "field-hover",
  "field-focus", "online",
  "r-field", "r-card", "r-dialog", "r-nav", "r-menu", "r-option",
  "text-xs", "text-sm", "text-body", "text-md", "text-lg",
  "dur", "ease-out", "corner-shape", "corner-scale",
  // Set by the page as it runs: the sidebar's dragged width (ui.tsx's ResizeHandle).
  "sidebar-w",
] as const;

type Name = (typeof names)[number];
type Camel<S extends string> = S extends `${infer A}-${infer B}` ? `${A}${Capitalize<Camel<B>>}` : S;

const camel = (name: string) => name.replace(/-(\w)/g, (_, c: string) => c.toUpperCase());

export const vars = createGlobalThemeContract(
  Object.fromEntries(names.map((n) => [camel(n), n])) as { [N in Name as Camel<N>]: N },
  (value) => value ?? "",
);
