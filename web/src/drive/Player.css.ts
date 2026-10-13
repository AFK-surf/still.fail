import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { glass } from "../FilePreview.css.ts";
import { spinner as turning } from "../styles/waiting.css.ts";

/** The player fills its page (the phone's, or the desktop's main pane), dark as the chat's video viewer. */
export const player = style({ position: "absolute", inset: "0", userSelect: "none", WebkitUserSelect: "none" });
export const stage = style({ position: "absolute", inset: "0", display: "grid", placeItems: "center" });
export const media = style({
  display: "block", width: "100%", height: "100%", objectFit: "contain", background: "#000",
  selectors: { "&[data-audio]": { position: "absolute", inset: "0", opacity: "0" } },
});
globalStyle(`${media}::cue`, { background: "rgba(0, 0, 0, .55)", color: "#fff", fontFamily: vars.fontBody });

/** A song has no picture: its mark and its name. */
export const cover = style({
  display: "grid", justifyItems: "center", gap: "16px", padding: "0 32px", color: "rgba(255, 255, 255, .7)", textAlign: "center",
});
globalStyle(`${cover} span`, { color: vars.text, fontSize: vars.textTitle, fontWeight: "600", overflowWrap: "anywhere" });

/** The way back and its name, floating at the top as a preview's bar does; it fades with the controls. */
export const head = style({
  ...glass,
  position: "absolute", zIndex: "3", top: "calc(var(--m-top, 0px) + max(12px, env(safe-area-inset-top)))", left: "50%", transform: "translateX(-50%)",
  display: "flex", alignItems: "center", gap: "8px", width: "max-content", maxWidth: "min(100% - 24px, 1080px)", height: "44px", boxSizing: "border-box",
  padding: "0 16px 0 6px", borderRadius: `calc(14px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, color: vars.text,
  opacity: "0", pointerEvents: "none", transition: `opacity 320ms ${vars.easeOut}`,
  selectors: { "&[data-awake]": { opacity: "1", pointerEvents: "auto", transitionDuration: "120ms" } },
  "@media": { "(prefers-reduced-motion: reduce)": { transition: "none" } },
});
export const name = style({ display: "flex", alignItems: "baseline", gap: "10px", minWidth: "0" });
globalStyle(`${name} b`, { minWidth: "0", fontSize: vars.textBody, fontWeight: "600", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${name} small`, { flex: "none", color: vars.muted, fontSize: vars.textMeta, fontVariantNumeric: "tabular-nums" });
/** Play, and the way back: in the text's colour, not the quieter one of the rest. */
export const bright = style({ color: `${vars.text} !important` });

export const note = style({ display: "grid", justifyItems: "center", gap: "14px", padding: "0 32px", color: vars.muted, fontSize: vars.textMeta, textAlign: "center" });
export const noteButton = style({
  display: "inline-flex", alignItems: "center", gap: "6px", height: "36px", padding: "0 16px", border: "0", borderRadius: "999px",
  background: "rgba(255, 255, 255, .12)", color: vars.text, fontSize: vars.textUi, cursor: "pointer",
});
export const spinner = style([turning, { position: "absolute", width: "28px", height: "28px", pointerEvents: "none" }]);
/** What of it has come: a lighter band under the played part. */
export const buffered = style({ position: "absolute", top: "0", bottom: "0", background: "rgba(255, 255, 255, .22)" });
