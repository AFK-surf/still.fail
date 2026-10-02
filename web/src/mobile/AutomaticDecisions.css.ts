import { style } from "@vanilla-extract/css";
export const stationHead = style({ display: "flex", alignItems: "center", marginRight: 20 });
export const stationName = style({ flex: "1", minWidth: 0 });
export const rowHead = style({ display: "flex", alignItems: "baseline", gap: 12 });
export const time = style({ fontSize: 12, color: "var(--m-subtle)", whiteSpace: "nowrap", flex: "none" });
export const meta = style({ display: "flex", alignItems: "baseline", gap: 6, fontSize: 13, color: "var(--m-muted)" });
