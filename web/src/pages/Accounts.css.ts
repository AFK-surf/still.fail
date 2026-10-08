import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

export const identityNameInput = style({ fontSize: vars.textTitle, fontWeight: "600", maxWidth: "360px" });
export const envTable = style({ display: "grid", gap: "8px" });
export const envRow = style({
  display: "grid", gridTemplateColumns: "minmax(120px, 1fr) minmax(140px, 1.5fr) auto", gap: "8px",
  "@media": {
    "(max-width: 700px)": {
      gridTemplateColumns: "1fr",
    },
  },
});
export const signIn = style({});
/** Codex's device sign-in: the code, large, then the one button that copies it and opens the page it goes into. */
export const deviceCode = style({ display: "grid", justifyItems: "start", gap: "10px" });
export const deviceCodeValue = style({
  fontSize: vars.textHeading, fontWeight: "600", letterSpacing: "0.08em", padding: "6px 12px", borderRadius: "10px",
  background: vars.hover, userSelect: "all",
});
export const modelChips = style({});
export const modelChip = style({
  display: "inline-flex", alignItems: "center", gap: "6px", padding: "4px 10px", borderRadius: "999px",
  background: vars.hover, fontSize: vars.textUi, lineHeight: "20px",
});
/** A profile's state under its name: the check, when, and checking again. */
export const profileState = style({ display: "flex", alignItems: "center", flexWrap: "wrap", gap: "8px" });
export const modelPoolFilter = style({ maxWidth: "240px", height: "30px" });
export const modelPoolGone = style({ fontSize: vars.textMeta });
/** The machine's own logins, offered where a first profile is asked for (pages/Accounts.tsx's MachineLoginOffers). */
export const machineLogins = style({ width: "100%", marginTop: "20px", display: "grid", gap: "4px", textAlign: "left" });
export const machineLoginsHead = style({ margin: "0", fontSize: vars.textMeta, color: vars.muted });
globalStyle(`${deviceCode} p`, { margin: "0", fontSize: vars.textUi });

/** A value beside its name in the share card (a station, the stations): muted, the button after it. */
export const shareValue = style({ display: "inline-flex", alignItems: "center", gap: "6px", color: vars.muted, fontSize: vars.textUi });
/** A station to pick in a dialog: a list row that is a button (no button look of its own). */
export const pickRow = style({
  width: "100%", border: "0", background: "none", font: "inherit", color: "inherit", textAlign: "left", cursor: "pointer",
  selectors: { "&:disabled": { cursor: "default", opacity: ".5" } },
});
/** The share card's rows, spaced as a card's rows are. */
export const shareRows = style({ display: "grid", gap: "14px", marginTop: "10px" });
