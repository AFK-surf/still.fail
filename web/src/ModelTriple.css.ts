// Models by name, by series: the model control's list, and a profile's list of models to enable.
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

/** A series of models in the control's list: its models one under another, each as wide as the list. */
export const series = style({ display: "flex", flexDirection: "column", gap: 1 });

/** A series in a profile's list of models to enable: its name, a toggle for all of it, its models under. */
export const poolSeries = style({ display: "grid", gap: 2, selectors: { "& + &": { marginTop: 10 } } });
export const poolSeriesHead = style({ display: "flex", alignItems: "center", gap: 10, padding: "0 8px" });
globalStyle(`${poolSeriesHead} h4`, { margin: 0, fontSize: vars.textXs, fontWeight: 500, color: vars.muted });
