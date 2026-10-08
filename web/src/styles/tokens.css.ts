// Styles are written in TypeScript beside what they style (Chat.css.ts for Chat.tsx, vanilla-extract): each class is
// scoped to its file, so no two can collide, and a rule for an element's state sits with the element's other rules.
// What several components share is in styles/ (the phone's in mobile/styles/); styles/index.ts loads them all, in
// the order they cascade.
//
// The palette, type sizes, radii and motion (styles/global.css.ts gives them their values, per theme), for those
// styles: `vars.muted` is `var(--muted)`.
import { createGlobalThemeContract } from "@vanilla-extract/css";

const names = [
  "font-body", "font-mono",
  "canvas", "raised", "sidebar", "list", "text", "muted", "subtle", "line", "line-strong", "hover", "selected", "paper",
  "accent", "accent-text", "accent-bg", "blue", "blue-bg", "code-inline", "green", "green-bg", "amber", "amber-bg",
  "red", "red-bg", "neutral-bg", "overlay", "shadow", "primary", "primary-hover", "on-primary", "field-hover",
  "field-focus", "online",
  "r-field", "r-card", "r-dialog", "r-nav", "r-menu", "r-option",
  // Type sizes, by what the text is (global.css.ts gives them their values; the phone's are its own, mobile/styles/root.css.ts).
  // A style says one of these, never a size of its own (scripts/check.sh).
  "text-micro", "text-caption", "text-label", "text-secondary", "text-control", "text-body", "text-input", "text-title",
  "text-heading", "text-display",
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
