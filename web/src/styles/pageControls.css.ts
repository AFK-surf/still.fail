// @stillfail/ui's controls (its styles/controls.css.ts) where the app's pages put them: in a settings card, a row of
// fields, the steps of signing in or of connecting. Right after the package's controls in the cascade (styles/index.ts).
import { globalStyle } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { bleedX } from "@stillfail/ui/styles/align.ts";
import { btn, btnDangerSolid, btnPrimary, input, steps } from "@stillfail/ui/styles/controls.css.ts";
import { inputRow } from "./additions.css.ts";
import { card } from "./pages.css.ts";
import { newChatStatus } from "../NewChat.css.ts";
import { signIn } from "../pages/Accounts.css.ts";
import { stepActions } from "../pages/Connect.css.ts";

/**
 * In a settings card (its grey ground and no line round it), a button that is not solid is its words and icon alone, its
 * words where the card's other words end (its padding taken back by its margin); hovered, the hover ink behind them as
 * everywhere (docs/ui-panels.md 悬停).
 */
globalStyle(`${card} ${btn}:not(${btnPrimary}, ${btnDangerSolid})`, {
  borderColor: "transparent", background: "transparent", paddingBlock: "0", ...bleedX(12),
});
globalStyle(`${card} ${btn}:not(${btnPrimary}, ${btnDangerSolid}):hover:not(:disabled)`, {
  background: vars.hover,
});
// Beside fields, a button's ground lines up with theirs: the text-card bleed would pull it into the card's corner.
globalStyle(`${card} ${inputRow} ${btn}`, { marginInline: 0 });
globalStyle(`${inputRow} ${input}`, { flex: "1" });
// A sign-in's steps: their numbers in their lines, so what is under them (the page's button, the code's field) stands
// where the card's words do.
globalStyle(`${signIn} ${steps}`, { gap: "14px", paddingLeft: "0", listStylePosition: "inside" });
globalStyle(`${steps} li > ${inputRow}`, { marginTop: "8px" });
globalStyle(`${steps} ${stepActions}`, { display: "flex", flexWrap: "wrap", gap: "8px", marginTop: "8px" });
/** After the package's field errors, and wins over them. */
globalStyle(newChatStatus, { minHeight: "1.5em", margin: "0", fontSize: vars.textMeta, color: vars.muted });
