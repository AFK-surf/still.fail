import { style } from "@vanilla-extract/css";
import { glass } from "@stillfail/ui/styles/glass.ts";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

/** The notices over the composer: one over another, 8 apart, 8 over the composer. */
export const notices = style({ display: "flex", flexDirection: "column", gap: "8px", marginBottom: "8px" });

/**
 * A notice: a capsule as the composer's (its glass, its small shadow, round at its ends; the composer's capsule stands
 * 6 in from its left: its mark there), one line of quiet words, what it offers 16 from its end.
 */
export const notice = style({
  display: "flex", alignItems: "center", minHeight: "40px", padding: "4px 16px 4px 6px",
  borderRadius: "999px", ...glass, boxShadow: "0 1px 3px rgb(0 0 0 / .04)",
  color: vars.muted, fontSize: vars.textUi, lineHeight: "20px",
});
/** Its mark as wide as the composer's ＋ (32), in the middle of it. */
export const mark = style({ flex: "none", display: "grid", placeItems: "center", width: "32px", marginRight: "2px" });
export const words = style({ flex: "1", minWidth: "0", display: "flex", flexDirection: "column" });
export const failed = style({ color: vars.red });
export const choices = style({ flex: "none", marginLeft: "12px", display: "inline-flex", gap: "12px" });

/** An option not taken: quiet as the notice's words, pressed to take it. */
export const choice = style({
  display: "inline-flex", alignItems: "center", gap: "4px", padding: "0", border: "0", background: "none", font: "inherit",
  color: vars.muted, fontWeight: 400, cursor: "pointer",
  selectors: { "&:disabled": { cursor: "default" } },
});

/** The option taken: its ✓ before it, in the words' colour, a step heavier. */
export const taken = style([choice, { color: vars.text, fontWeight: 500, cursor: "default" }]);

export const offer = style({
  flex: "none", marginLeft: "12px", padding: "0", border: "0", background: "none", font: "inherit", fontWeight: 500,
  color: vars.text, cursor: "pointer",
  selectors: { "&:disabled": { color: vars.muted, cursor: "default" } },
});
