import { globalStyle, style } from "@vanilla-extract/css";
import { preview, previewBar, previewPath } from "../Preview.css.ts";

export const mPreview = style({});
/** A web service on the station, full screen under its bar. */
globalStyle(`${mPreview} ${preview}`, { flex: "1", minHeight: "0", paddingBottom: "var(--m-foot)" });
globalStyle(`${mPreview} ${previewBar}`, { padding: "4px 10px 6px 14px" });
globalStyle(`${mPreview} ${previewPath}`, { fontSize: "16px" });
