import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

/** Signing in. */
export const mSignIn = style({
  display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: "12px",
  padding: "calc(40px + var(--m-top)) 30px calc(40px + var(--m-foot))", textAlign: "center", overflowY: "auto",
  "@media": {
    // Wider than a phone: what it says kept to a column in the middle.
    "(min-width: 680px)": { paddingInline: "max(72px, calc(50% - 340px))" },
  },
});
export const mGoogle = style({
  display: "flex", alignItems: "center", justifyContent: "center", gap: "10px", width: "100%", height: "50px",
  marginTop: "6px", border: "0", borderRadius: "25px", background: "var(--m-ink)", color: "var(--m-bg) !important",
  fontSize: `${vars.textTitle} !important`, fontWeight: "600", cursor: "pointer",
});
export const mGoogleMark = style({
  display: "inline-flex", alignItems: "center", justifyContent: "center", width: "24px", height: "24px",
  borderRadius: "50%", background: "#fff",
});
globalStyle(`${mSignIn} h1`, { margin: "10px 0 0", fontSize: vars.textDisplay, fontWeight: "700", letterSpacing: "-0.5px" });
globalStyle(`${mSignIn} p`, { fontSize: vars.textBody, color: "var(--m-muted)" });
globalStyle(`${mSignIn} small`, { fontSize: vars.textLabel, color: "var(--m-muted)" });
/** Why signing in could not start: in red, over the muted lines'. */
export const mSignInError = style({ fontSize: vars.textControl });
globalStyle(`${mSignIn} ${mSignInError}`, { color: "var(--m-red)" });
