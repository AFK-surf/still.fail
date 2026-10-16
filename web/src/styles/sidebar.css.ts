import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./tokens.css.ts";

/** 44px above where its line was (it has none now): a 32px button in it sits on whole pixels, level with the desktop window's buttons. */
export const pageBar = style({
  display: "grid", gridTemplateColumns: "1fr auto 1fr", alignItems: "center", height: "45px", padding: "0 12px 1px",
  selectors: {
    // The desktop app has no title bar: each page's bar drags the window, all but what is pressed in it (the sidebar's top
    // row does too: Sidebar.css.ts).
    "[data-desktop] &": { WebkitAppRegion: "drag" },
    // On Windows the window's buttons are over its right end (global.css.ts): what is there stays clear of them.
    ':is([data-desktop="overlay"], [data-desktop="custom"]) &': { paddingRight: "calc(var(--window-buttons, 0px) + 12px)" },
  },
  "@media": {
    "(max-width: 700px)": {
      gridTemplateColumns: "auto minmax(0, 1fr) auto", gap: "8px",
    },
    // Clear of the window's buttons with the sidebar closed: brand.css.ts clearOfWindowButtons.
  },
});
globalStyle(`[data-desktop] ${pageBar} :is(a, button, input, select, textarea, [role="button"], [tabindex])`, { WebkitAppRegion: "no-drag" });
