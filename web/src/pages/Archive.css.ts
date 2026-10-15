import { style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { navSessionWrap } from "../Sidebar.css.ts";

// An archived chat's row in the sidebar (Archive.tsx ArchiveRow), a chat's row (Sidebar.css.ts) but for what can be done
// with it: putting it back and deleting it, over the title's end while it is pointed at (or one of them under way).
const shown = `${navSessionWrap}:is(:hover, :focus-within, [data-busy]) &`;

/** The title making room for the two buttons. */
export const head = style({ selectors: { [shown]: { paddingRight: 52 } } });
/** Centred on the title line (20px tall, 7px down the row), as a chat's archive button is. */
export const actions = style({
  position: "absolute", top: 5, right: 6, display: "flex", gap: 2, opacity: 0, pointerEvents: "none",
  selectors: { [shown]: { opacity: 1, pointerEvents: "auto" } },
  // No pointer to point with: always there.
  "@media": { "(hover: none)": { opacity: 1, pointerEvents: "auto" } },
});
export const action = style({ width: 24, height: 24 });
export const remove = style({ selectors: { "&:hover": { color: vars.red } } });
