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
export const enrollWait = style({
  display: "flex", alignItems: "center", gap: "12px", marginTop: "16px", padding: "12px 14px",
  borderRadius: vars.rField, cornerShape: vars.cornerShape,
  background: `color-mix(in srgb, ${vars.accent} 9%, transparent)`,
});
/** A first profile to add, station by station (cloud/settings.tsx): where it goes is part of adding it. */
export const firstStations = style({ width: "100%", display: "grid", gap: "28px", textAlign: "left" });
export const firstStationRow = style({ display: "flex", alignItems: "center", gap: "10px", fontSize: vars.textSm });
export const firstStationName = style({
  flex: "1", minWidth: "0", fontWeight: "600", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const firstStation = style({});
export const memoryStation = style({});
export const memoryStationName = style({ margin: "0 0 8px", fontSize: vars.textMd, fontWeight: "600" });
globalStyle(`${groupHead} ${runtimeLogo}`, { alignSelf: "center" });
/** As tall as the field beside it. */
globalStyle(`${onboardingRow} ${btn}`, { height: "auto" });
globalStyle(`${onboardingCard} ${command}`, { marginTop: "8px" });
globalStyle(`${enrollWait} strong`, { fontWeight: "600" });
globalStyle(`${enrollWait} ${muted}`, { fontSize: vars.textXs });
globalStyle(`${firstStation} ${machineLogins}`, { marginTop: "14px" });

/** A shared profile nobody can use now (the station signed in to its subscription is away): dimmed, its state said. */
export const profileAway = style({ opacity: ".55" });

/** An account's state on its page: its pill, what its check said. */
export const accountState = style({ display: "flex", alignItems: "center", gap: "8px", flexWrap: "wrap", marginBottom: "12px", fontSize: vars.textSm });
