import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { muted } from "../styles/shell.css.ts";
import { runtimeLogo } from "../ui.css.ts";
import { machineLogins } from "../pages/Accounts.css.ts";
import { btn } from "@stillfail/ui/styles/controls.css.ts";
import { BUTTON_CARD_CORNER, CARD_PAD, LIST_PAD, cardLook } from "../styles/pages.css.ts";
import { bleedStart } from "@stillfail/ui/styles/align.ts";
import { DIALOG_INNER, command, dialogBody } from "@stillfail/ui/parts.css.ts";

export const groupHead = style({});
export const stationHeading = style({ display: "inline-flex", alignItems: "center", gap: "6px" });
/** As the settings pages' cards (pages.css.ts card). */
// Its buttons reach its corners (the first station's form): its corner theirs (pages.css.ts BUTTON_CARD_CORNER).
export const onboardingCard = style({ width: "100%", textAlign: "left", padding: CARD_PAD, border: "0", ...cardLook, borderRadius: BUTTON_CARD_CORNER });
export const onboardingRow = style({ display: "flex", alignItems: "stretch", gap: "8px" });
/** An enrollment's command, and the wait for its station (EnrollSteps): spaced by itself, in a dialog's body as in a card. */
export const enroll = style({ display: "grid", gridTemplateColumns: "minmax(0, 1fr)", gap: "20px" });
/** The command under what to do with it. */
export const enrollStep = style({ display: "grid", gridTemplateColumns: "minmax(0, 1fr)", gap: "8px" });
/** 添加 station's two ways (a new machine, one of another workspace's): as wide as its options. */
export const addKinds = style({ justifySelf: "start" });
/** Which system's command it is (macOS and Linux's, Windows'): as wide as its options. */
export const enrollSystem = style({ justifySelf: "start" });
export const enrollLabel = style({ display: "flex", alignItems: "center", gap: "4px", margin: "0", fontSize: vars.textUi, fontWeight: "500" });
/** Calm, not a warning: a line around it, the spinner the only colour. */
export const enrollWait = style({
  display: "flex", alignItems: "center", gap: "12px", padding: "12px 16px",
  border: `1px dashed ${vars.lineStrong}`, borderRadius: vars.rField, cornerShape: vars.cornerShape,
});
/** A first profile to add, station by station (cloud/settings.tsx): where it goes is part of adding it. */
export const firstStations = style({ width: "100%", display: "grid", gap: "28px", textAlign: "left" });
export const firstStationRow = style({ display: "flex", alignItems: "center", gap: "10px", fontSize: vars.textUi });
export const firstStationName = style({
  flex: "1", minWidth: "0", fontWeight: "600", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const firstStation = style({});
globalStyle(`${groupHead} ${runtimeLogo}`, { alignSelf: "center" });
/** As tall as the field beside it. */
globalStyle(`${onboardingRow} ${btn}`, { height: "auto" });
globalStyle(`${enrollSystem} > button`, { whiteSpace: "nowrap", padding: "0 14px" });
globalStyle(`${enrollWait} strong`, { fontWeight: "600" });
globalStyle(`${enrollWait} ${muted}`, { fontSize: vars.textMeta });
globalStyle(`${enroll} ${command}`, { padding: "8px 8px 8px 16px", boxShadow: `inset 0 0 0 1px ${vars.line}` });
/** In a dialog the wait's corners are its command's (ui.css.ts DIALOG_INNER): the two boxes one under the other alike. */
globalStyle(`${dialogBody} ${enrollWait}`, { borderRadius: DIALOG_INNER });
/** A shell prompt before the command: what to do with it, at a glance. Not copied (the button copies the text). */
globalStyle(`${enroll} ${command} code::before`, { content: '"$ "', color: vars.muted, userSelect: "none" });
globalStyle(`${enrollStep}[data-shell="powershell"] ${command} code::before`, { content: '"PS> "' });
globalStyle(`${firstStation} ${machineLogins}`, { marginTop: "14px" });

/** A shared profile nobody can use now (the station signed in to its subscription is away): dimmed, its state said. */
export const profileAway = style({ opacity: ".55" });

/** An account's state on its page: its pill, what its check said. */
export const accountState = style({ display: "flex", alignItems: "center", gap: "8px", flexWrap: "wrap", marginBottom: "12px", fontSize: vars.textUi });

// ── a station's page (StationPage.tsx) ──
/** Its head: its mark's square, its name as the title, what it is to the viewer under it. */
export const workspaceHead = style({ display: "flex", alignItems: "center", gap: "16px", marginTop: "8px", marginBottom: "36px" });
export const workspaceFacts = style({
  display: "flex", flexWrap: "wrap", gap: "4px 0", margin: "2px 0 0", color: vars.muted, fontSize: vars.textUi, lineHeight: "20px",
});
globalStyle(`${workspaceFacts} > span + span::before`, { content: "\"·\"", margin: "0 8px", color: vars.subtle });
/**
 * Its name, renamed where it is: the title's own words, a field's ground only under the pointer or while typed in.
 */
export const titleField = style({
  width: "calc(100% + 8px)", minWidth: "0", marginBlock: "0", marginInlineEnd: "0", paddingBlock: "0", ...bleedStart(8), paddingInlineEnd: "8px", border: "0", outline: "none", background: "none", color: vars.text,
  font: "inherit", fontSize: vars.textHeading, lineHeight: "40px", height: "40px", fontWeight: "600",
  borderRadius: vars.rField, cornerShape: vars.cornerShape, transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:not(:disabled):hover": { background: vars.hover },
    "&:focus": { background: vars.hover, boxShadow: `inset 0 0 0 1.5px ${vars.fieldHover}` },
  },
});
/** How many, after a section's title. */
export const titleCount = style({ marginLeft: "8px", color: vars.subtle, fontWeight: "500" });

// ── the workspace's page (WorkspaceSettings) ──
/** Who the viewer is there and how many it holds, under its name. */
export const workspaceLead = style({ margin: "2px 0 0", color: vars.muted, fontSize: vars.textUi, lineHeight: "20px" });
/** How a row's thing stands at its end (its name, a member's role): muted, on one line. */
export const rowValue = style({ flex: "none", maxWidth: "50%", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", color: vars.muted, fontSize: vars.textUi });
export const rowChevron = style({ flex: "none", color: vars.subtle });
/** A field in a list card where its row was (adding a relay): in as a row's words. */
export const rowField = style({ padding: `10px ${CARD_PAD - LIST_PAD}px` });

// ── the settings' list in the sidebar (settings.tsx SettingsNav) ──────────────────────────────────────────────────

/** Two groups with no heading between them: a heading's room over the second (navHeading's 14 over it, 4 under). */
export const navApart = style({ height: 16 });
/** A row's name, as long as the row leaves it. */
export const navTitle = style({ flex: "1", minWidth: "0" });
/** How things stand at a row's end (the narrow screen's settings page says the same): the meta's size, muted, as wide
 *  as it is; its dot before it, 6 apart. */
export const navValue = style({
  display: "flex", alignItems: "center", gap: 6, flex: "none", fontSize: vars.textMeta, lineHeight: "18px", color: vars.muted, whiteSpace: "nowrap",
});
/** Something waits there: in red. */
export const navValueBad = style({ color: vars.red });

// ── 账号 (settings.tsx AccountSettings) ───────────────────────────────────────────────────────────────────────────

/** The account in view's name on its row: who it is, strong. */
export const accountName = style({ fontWeight: "600" });
/** 注销账号: a row that takes something away, in red. */
export const accountDelete = style({ color: vars.red });
