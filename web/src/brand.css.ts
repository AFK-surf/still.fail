import { globalStyle, style } from "@vanilla-extract/css";
import { LIST_PAD, list, listCardLook, pageNarrow } from "./styles/pages.css.ts";
import { inNarrow } from "./styles/narrow.ts";
import { newChat } from "./NewChat.css.ts";
import { pageBar as onePageBar } from "./styles/sidebar.css.ts";
import { bar as filesBar } from "./pages/Files.css.ts";
import { neg, outset } from "@stillfail/ui/styles/align.ts";

// A page's bar, and the files page's over its tabs (Files.tsx), which is in the same place.
const pageBar = `:is(${onePageBar}, ${filesBar})`;
export const illus = style({
  display: "block", maxWidth: "100%", height: "auto",
  selectors: {
    [`${newChat} &`]: { marginBottom: "4px" },
  },
  "@media": {
    "(max-height: 640px)": {
      selectors: {
        [`${newChat} &`]: { display: "none" },
      },
    },
  },
});
const wide = "(min-width: 701px)";
/** Here rather than with its class: it comes after .illus, and wins over it. */
globalStyle(inNarrow("*"), { maxWidth: "760px", marginLeft: "auto", marginRight: "auto" });
/** Lists stand on spacing, not frames or rules: their rows' text lines up with the page's, a row's ground shows on hover. */
/** Here rather than with its class: it comes after .page-narrow > *, and wins over it. */
// One column no wider than the page, so a long title is cut short rather than widening its row past it.
globalStyle(list, { listStyle: "none", marginBlock: "0", ...outset(12), padding: "0", display: "grid", gridTemplateColumns: "minmax(0, 1fr)", gap: "2px" });
/** A list right in a narrow page (not in a section): in the page's column like everything else there, its rows' grounds
 * out past it by their padding. Its own margin above would take the column's centring away (it comes later). */
globalStyle(inNarrow(list), { maxWidth: "none", marginLeft: `max(${neg(12)}, calc(50% - 392px))`, marginRight: `max(${neg(12)}, calc(50% - 392px))` });
/**
 * On a settings page a list is a list card, on every width as the narrow screen's and the app's are (docs/ui-panels.md
 * 页面卡片, 列表卡; the user, 2026-10-26: 「设置感觉很乱」, a wide page's rows were on the page or on cards for no reason):
 * at the column's edges as the page's other cards, its rows' grounds LIST_PAD in, their words CARD_PAD in, their corners
 * concentric with its. Here, after the two above, so it wins over them.
 */
globalStyle(`${pageNarrow} ${list}`, { ...listCardLook, padding: LIST_PAD, marginInline: "0" });
// One right in the page is a block of its own, as far from what follows as a section (page.css.ts section).
globalStyle(inNarrow(list), { maxWidth: "760px", marginLeft: "auto", marginRight: "auto", marginBottom: "28px" });
