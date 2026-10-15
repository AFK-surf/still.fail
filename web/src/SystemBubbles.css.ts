// The app's own bubbles (SystemBubbles.tsx): at the page's bottom left, beside the rail (none on a narrow screen: the
// window's edge), the newest lowest, each rising in.
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { panel } from "./styles/glass.ts";
import { PANEL_PAD, TEXT_IN, surface } from "./styles/align.ts";
import { panelButton, panelIcon } from "./ui.css.ts";

export const stack = style({
  position: "fixed", zIndex: 150, left: "calc(env(safe-area-inset-left, 0px) + 12px)", bottom: "calc(env(safe-area-inset-bottom, 0px) + 12px)",
  display: "flex", flexDirection: "column", alignItems: "flex-start", gap: 8, maxWidth: "min(420px, calc(100vw - 24px))",
  pointerEvents: "none",
  "@media": {
    "(min-width: 701px)": {
      selectors: {
        ":root:has([data-rail]) &": { left: 68 },
        // Beside the closed bar (styles/shell.css.ts dock: 6 to 48), as far from it and from the window's foot as it
        // is from the window's edges (6), moved with it (brand.tsx moveSidebar).
        ':root:has([data-rail])[data-sidebar="closed"] &': { left: 54, bottom: "calc(env(safe-area-inset-bottom, 0px) + 6px)" },
      },
    },
  },
});
/** A bubble's room in the stack, opened and closed as it comes and goes (SystemBubbles.tsx): the bubble at its foot,
 * standing out over it while it is short. */
export const slot = style({
  display: "flex", flexDirection: "column", justifyContent: "flex-end", maxWidth: "100%",
  selectors: { "&[data-leaving]": { pointerEvents: "none" } },
});
globalStyle(`${slot}[data-leaving] *`, { pointerEvents: "none" });
export const bubble = style({
  // Its mark and its close on its first line; what can be done by the last line of its words, at their right.
  ...panel, display: "grid", gridTemplateColumns: "auto minmax(0, 1fr) auto auto", gridTemplateAreas: '"icon text act close"',
  columnGap: 6, maxWidth: "100%",
  // A small panel (docs/ui-panels.md): padded 6, its mark and words in by a row's padding more.
  ...surface(PANEL_PAD, 14), paddingInlineStart: PANEL_PAD + TEXT_IN, boxShadow: `0 8px 24px ${vars.shadow}`,
  color: vars.text, fontSize: vars.textUi, lineHeight: "20px", pointerEvents: "auto",
});
export const icon = style({ gridArea: "icon", alignSelf: "start", display: "grid", placeItems: "center", height: 28, marginRight: 4, color: vars.accent });
export const text = style({ gridArea: "text", display: "flex", flexDirection: "column", minWidth: 0, padding: "4px 0" });
export const line = style({
  color: vars.muted, fontSize: vars.textMeta, lineHeight: "18px", overflow: "hidden",
  display: "-webkit-box", WebkitBoxOrient: "vertical", WebkitLineClamp: 2,
});
/** Its one thing to do: a small panel's words to press (ui.css.ts panelButton, accent), by the last line of the words. */
export const action = style([panelButton, { gridArea: "act", alignSelf: "end", margin: "0 2px 2px 0" }]);
/** Both small (24) in rows 28 high: 2 in, so each stands as far from both edges of its corner (8), in the middle of its row. */
export const close = style([panelIcon, { gridArea: "close", alignSelf: "start", justifySelf: "end", margin: "2px 2px 0 0" }]);

// With words under its title: its close at the top right and what can be done under it, at the right of the last line.
globalStyle(`${bubble}:has(${line})`, { gridTemplateColumns: "auto minmax(0, 1fr) auto", gridTemplateAreas: '"icon text close" "icon text act"' });
globalStyle(`${bubble}:has(${line}) > ${action}`, { justifySelf: "end" });
