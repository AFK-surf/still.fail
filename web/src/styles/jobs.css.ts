import { globalStyle, style } from "@vanilla-extract/css";
import { chat } from "./session.css.ts";

export const sessionMain = style({ minWidth: "0", minHeight: "0", display: "flex", flexDirection: "column" });
globalStyle(`${sessionMain} ${chat}`, { flex: "1" });
