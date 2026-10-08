// The sidebar foot's services and jobs left up a long while (OpenJobs.tsx): quiet rows over the settings, their dots the only colour.
import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

const ellipsis = { minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } as const;

export const openJobs = style({ display: "grid", gridTemplateColumns: "minmax(0, 1fr)", gap: 8, marginBottom: 6 });
/** Web services, then background jobs: each under its heading. */
export const openJobsGroup = style({ display: "grid", gridTemplateColumns: "minmax(0, 1fr)", gap: 2 });
export const openJobsHead = style({ padding: "2px 10px 2px", fontSize: vars.textLabel, lineHeight: "18px", color: vars.muted });
/** A job: the row leads to its chat; stop takes the time's place while pointed at. */
export const openJob = style({ position: "relative", minWidth: 0 });
/** The dot, in the 16px column the icons of the rows under it take. */
export const openJobMark = style({ width: 16, flex: "none", display: "grid", placeItems: "center" });
export const openJobRow = style({
  display: "flex", alignItems: "center", gap: 10, padding: "5px 10px", borderRadius: vars.rNav, cornerShape: vars.cornerShape,
  color: vars.text, fontSize: vars.textSecondary, lineHeight: "18px", transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    [`${openJob}:hover &`]: { background: vars.hover },
    '&[aria-current="page"]': { background: vars.selected },
  },
});
export const openJobText = style({ flex: 1, minWidth: 0, display: "flex", flexDirection: "column" });
export const openJobName = style(ellipsis);
export const openJobWhere = style({ ...ellipsis, fontSize: vars.textLabel, lineHeight: "16px", color: vars.muted });
export const openJobAge = style({
  flex: "none", fontSize: vars.textLabel, color: vars.muted, fontVariantNumeric: "tabular-nums",
  selectors: { [`${openJob}:hover &`]: { visibility: "hidden" } },
  // No hover to tell: the stop button shows, over the time.
  "@media": { "(hover: none)": { visibility: "hidden" } },
});
export const openJobStop = style({
  position: "absolute", top: "50%", right: 6, width: 24, height: 24, marginTop: -12, display: "grid", placeItems: "center",
  border: 0, borderRadius: vars.rOption, background: "none", color: vars.muted, cursor: "pointer", opacity: 0, pointerEvents: "none",
  selectors: {
    [`${openJob}:hover &, &:focus-visible, &[aria-busy="true"]`]: { opacity: 1, pointerEvents: "auto" },
    "&:hover:not(:disabled)": { color: vars.red, background: vars.hover },
  },
  "@media": { "(hover: none)": { opacity: 1, pointerEvents: "auto" } },
});
export const openJobsMore = style({
  padding: "3px 10px", border: 0, background: "none", textAlign: "left", font: "inherit", fontSize: vars.textLabel, color: vars.muted, cursor: "pointer",
  selectors: { "&:hover": { color: vars.text } },
});
