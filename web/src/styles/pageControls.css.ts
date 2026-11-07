// @stillfail/ui's controls (its styles/controls.css.ts) where the app's pages put them: in a settings card, a row of
// fields, the steps of signing in or of connecting. Right after the package's controls in the cascade (styles/index.ts).
import { globalStyle } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { bleedX } from "@stillfail/ui/styles/align.ts";
import { btn, btnDangerSolid, btnPrimary } from "@stillfail/ui/styles/controls.css.ts";
import { card } from "./pages.css.ts";

/**
 * In a settings card (its grey ground and no line round it), a button that is not solid is its words and icon alone, its
 * words where the card's other words end (its padding taken back by its margin); hovered, the hover ink behind them as
 * everywhere (mbui ui/hand_moves.mbt).
 */
globalStyle(`${card} ${btn}:not(${btnPrimary}, ${btnDangerSolid})`, {
  borderColor: "transparent", background: "transparent", paddingBlock: "0", ...bleedX(12),
});
globalStyle(`${card} ${btn}:not(${btnPrimary}, ${btnDangerSolid}):hover:not(:disabled)`, {
  background: vars.hover,
});
