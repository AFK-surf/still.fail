import { globalStyle, style } from "@vanilla-extract/css";

/** Signing in. */
export const mSignIn = style({
  display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: "12px",
  padding: "calc(40px + var(--m-top)) 30px calc(40px + var(--m-foot))", textAlign: "center", overflowY: "auto",
  "@media": {
    // Wider than a phone: in the pages' column (app.css.ts mColumn).
    "(min-width: 680px)": { paddingInline: "max(72px, calc(50% - 340px))" },
  },
});
export const mGoogle = style({
  display: "flex", alignItems: "center", justifyContent: "center", gap: "10px", width: "100%", height: "50px",
  marginTop: "6px", border: "0", borderRadius: "25px", background: "var(--m-ink)", color: "var(--m-bg) !important",
  fontSize: "16px !important", fontWeight: "600", cursor: "pointer",
});
export const mGoogleMark = style({
  display: "inline-flex", alignItems: "center", justifyContent: "center", width: "24px", height: "24px",
  borderRadius: "50%", background: "#fff",
});
globalStyle(`${mSignIn} h1`, { margin: "10px 0 0", fontSize: "28px", fontWeight: "700", letterSpacing: "-0.5px" });
globalStyle(`${mSignIn} p`, { fontSize: "15px", color: "var(--m-muted)" });
globalStyle(`${mSignIn} small`, { fontSize: "12px", color: "var(--m-muted)" });
/** Why signing in could not start: in red, over the muted lines'. */
export const mSignInError = style({ fontSize: "14px" });
globalStyle(`${mSignIn} ${mSignInError}`, { color: "var(--m-red)" });
