import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { pillInner, surfaceCorner } from "@stillfail/ui/styles/align.ts";
import { mButton } from "./parts.css.ts";
import { mField } from "./styles/lists.css.ts";

export const mMono = style({
  fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace", fontSize: vars.textUi, overflow: "hidden",
  textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const mProfileNote = style({ padding: "8px 24px", fontSize: vars.textMeta, color: "var(--m-muted)" });
/** The step after a profile is added (PickModelsScreen): skipping and done side by side at the screen's foot. */
export const mPickFoot = style({ display: "flex", gap: "10px", flex: "none", padding: "10px 16px calc(var(--m-foot) + 12px)" });
globalStyle(`${mPickFoot} > button`, { flex: "1", justifyContent: "center" });
export const mRowQuota = style({ display: "flex", marginTop: "6px" });
/** An account at the top of its card: where it stands, then (in trouble) why and what to do, 12 apart. */
export const mAccount = style({ display: "flex", flexDirection: "column", gap: "12px", flex: "1", minWidth: "0" });
/** Its state under its line: a dot, its words and when it was checked; coloured only when something is off. */
export const mAccountState = style({
  display: "inline-flex", alignItems: "center", gap: "6px",
  selectors: { '&[data-tone="red"]': { color: "var(--m-red)" }, '&[data-tone="amber"]': { color: "var(--m-warn)" } },
});
/** What a trouble says and its buttons, 10 apart. */
export const mTrouble = style({ display: "flex", flexDirection: "column", alignItems: "flex-start", gap: "10px" });
globalStyle(`${mTrouble} > p`, { margin: "0" });
/** When an allowance was read: 12 under its windows. */
export const mQuotaRead = style({ margin: "12px 0 0", fontSize: vars.textCaption, color: "var(--m-muted)" });
export const mDeviceCode = style({
  alignSelf: "flex-start", padding: "8px 14px", borderRadius: `calc(10px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  background: "var(--m-chip)",
  fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace", fontSize: vars.textHeading, letterSpacing: "2px",
});
export const mEnvRow = style({
  display: "grid", gridTemplateColumns: "minmax(0, 1fr) minmax(0, 1.3fr) auto", gap: "6px", alignItems: "center",
});
export const mDetails = style({});
globalStyle(`${mDetails} summary`, { fontSize: vars.textMeta, color: "var(--m-muted)", cursor: "pointer", padding: "4px 0" });

/** The profile's allowance: the PC's dials (QuotaBars), inside the card. */
export const mQuotaDials = style({ padding: "16px 16px 14px" });

/** A subscription's sign-in card: its buttons the card's width, their words centred; cancelling a sign-in under way is
 *  words under them, centred and grey, not one more button as loud. */
export const mSignIn = style({});
/** On the add pages, whose body already keeps 18 from the sides: the card to them, as their lists are. */
export const mFlowCard = style({ width: "100%", margin: "0" });
globalStyle(`${mSignIn} > ${mButton}`, { justifyContent: "center" });
globalStyle(`${mSignIn} > ${mDeviceCode}`, { alignSelf: "stretch", textAlign: "center" });
/** Its top: where the account stands, and while signing in, cancelling it at that line's end (grey words, not a button as loud). */
export const mSignInHead = style({ display: "flex", alignItems: "flex-start", gap: "8px" });
globalStyle(`${mSignInHead} > :first-child`, { flex: "1", minWidth: "0" });
export const mSignInCancel = style({
  display: "inline-flex", alignItems: "center", gap: "6px", flex: "none", minHeight: "24px",
  padding: "0", border: "0", background: "none", color: "var(--m-muted) !important", fontSize: `${vars.textUi} !important`,
  cursor: "pointer",
  selectors: { "&:disabled": { cursor: "default" } },
});
/** Signed in or not: its button, and signing in by hand beside it. */
export const mSignInActions = style({ display: "flex", alignItems: "center", gap: "16px" });
/** A step of a sign-in: its number in a small round, its words beside it; what it has (a button) under its words. */
export const mStep = style({ display: "flex", gap: "10px", margin: "0", fontSize: vars.textUi, lineHeight: "20px" });
export const mStepN = style({
  display: "inline-flex", alignItems: "center", justifyContent: "center", flex: "none", width: "20px", height: "20px", marginTop: "0",
  borderRadius: "50%", background: "var(--m-chip)", fontSize: vars.textCaption, fontWeight: "600",
});
export const mStepBody = style({ paddingLeft: "30px" });
/** The code's field and what sends it, on one line. */
export const mCodeRow = style({ display: "flex", alignItems: "center", gap: "8px" });
/** A sign-in card with its buttons at its foot (or the code's field and what sends it): they sit in its bottom corners,
 *  as far from its foot as from its sides, and its corner is taken from them (docs/ui-panels.md, align.ts pillInner);
 *  the field beside a button is as high and rounded as it is. */
const SIGN_IN_PAD = 16;
const SIGN_IN_PILL = 38;
globalStyle(`${mSignIn}:has(> ${mButton}:last-child), ${mSignIn}:has(> ${mSignInActions}:last-child), ${mSignIn}:has(> ${mCodeRow}:last-child)`, {
  paddingBottom: `${SIGN_IN_PAD}px`, borderRadius: surfaceCorner(SIGN_IN_PAD, pillInner(SIGN_IN_PAD, SIGN_IN_PILL, vars.cornerScale)),
});
globalStyle(`${mSignIn} > ${mCodeRow}:last-child > ${mField}`, {
  height: `${SIGN_IN_PILL}px`, paddingBlock: "0", borderRadius: pillInner(SIGN_IN_PAD, SIGN_IN_PILL, vars.cornerScale),
});
/** A key's profile: where it stands, atop its key's rows on one card. */
export const mHeadRow = style({ padding: "14px 16px" });
