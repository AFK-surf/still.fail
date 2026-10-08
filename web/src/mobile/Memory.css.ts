import { style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

export const mMemoryNote = style({ margin: "0", padding: "0 24px 8px", fontSize: vars.textSecondary, color: "var(--m-muted)" });
/** The skills on their card: the wide screen's rows, a size up, the card's margins around them. */
export const mMemorySkills = style({ padding: "4px" });
export const mMemoryDoc = style({ fontSize: vars.textControl });
