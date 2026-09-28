import { globalStyle, style } from "@vanilla-extract/css";

/** Signing in. */
export const mSignIn = style({
  display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: "12px",
  padding: "calc(40px + var(--m-top)) 30px calc(40px + var(--m-foot))", textAlign: "center", overflowY: "auto",
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
