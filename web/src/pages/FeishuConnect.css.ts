import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { DIALOG_INNER } from "@stillfail/ui/parts.css.ts";

/** A platform's mark in its choice, the size of a line of its title and note. */
export const platformMark = style({ display: "grid", placeItems: "center", flex: "none", width: "28px", height: "28px" });
/** Scanning: the QR code, and beside it where it stands and the way to open it on this device. */
export const scan = style({ display: "flex", alignItems: "center", gap: "24px", minHeight: "196px" });
export const qrPlace = style({
  display: "grid", placeItems: "center", flex: "none", width: "196px", height: "196px", borderRadius: DIALOG_INNER,
  cornerShape: vars.cornerShape, background: vars.neutralBg,
});
export const scanText = style({ display: "grid", gap: "10px", alignContent: "center", minWidth: "0", fontSize: vars.textUi });
export const scanBad = style({ color: vars.red });
export const scanOpen = style({ display: "flex", width: "max-content" });
/** The app's rows: their labels are wider than the run card's. */
export const appLabel = style({ width: "84px" });
export const mono = style({ fontFamily: vars.fontMono, overflowWrap: "anywhere" });
