import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { muted } from "../styles/shell.css.ts";
import { command, runtimeLogo } from "../ui.css.ts";
import { machineLogins } from "../pages/Accounts.css.ts";
import { btn } from "../styles/controls.css.ts";
import { cardLook } from "../styles/pages.css.ts";

export const groupHead = style({});
export const roleSelect = style({ width: "120px", flex: "none" });
export const stationHeading = style({ display: "inline-flex", alignItems: "center", gap: "6px" });
/** As the settings pages' cards (pages.css.ts card). */
export const onboardingCard = style({ width: "100%", textAlign: "left", padding: "18px 20px", border: "0", ...cardLook });
export const onboardingRow = style({ display: "flex", alignItems: "stretch", gap: "8px" });
/** 「添加这台 Mac」 under the first station's form (the desktop app's). */
export const firstThisMac = style({ marginTop: "12px" });
/** An enrollment's command, and the wait for its station (EnrollSteps): spaced by itself, in a dialog's body as in a card. */
export const enroll = style({ display: "grid", gridTemplateColumns: "minmax(0, 1fr)", gap: "20px" });
/** The command under what to do with it. */
export const enrollStep = style({ display: "grid", gridTemplateColumns: "minmax(0, 1fr)", gap: "8px" });
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
export const memoryStation = style({});
export const memoryStationName = style({ margin: "0 0 8px", fontSize: vars.textTitle, fontWeight: "600" });
globalStyle(`${groupHead} ${runtimeLogo}`, { alignSelf: "center" });
/** As tall as the field beside it. */
globalStyle(`${onboardingRow} ${btn}`, { height: "auto" });
globalStyle(`${enrollWait} strong`, { fontWeight: "600" });
globalStyle(`${enrollWait} ${muted}`, { fontSize: vars.textMeta });
globalStyle(`${enroll} ${command}`, { padding: "8px 8px 8px 16px", boxShadow: `inset 0 0 0 1px ${vars.line}` });
/** A shell prompt before the command: what to do with it, at a glance. Not copied (the button copies the text). */
globalStyle(`${enroll} ${command} code::before`, { content: '"$ "', color: vars.muted, userSelect: "none" });
globalStyle(`${enrollStep}[data-shell="powershell"] ${command} code::before`, { content: '"PS> "' });
globalStyle(`${firstStation} ${machineLogins}`, { marginTop: "14px" });

/** A shared profile nobody can use now (the station signed in to its subscription is away): dimmed, its state said. */
export const profileAway = style({ opacity: ".55" });

/** An account's state on its page: its pill, what its check said. */
export const accountState = style({ display: "flex", alignItems: "center", gap: "8px", flexWrap: "wrap", marginBottom: "12px", fontSize: vars.textUi });
