import { globalStyle, style } from "@vanilla-extract/css";
import { mRiseKeyframes } from "../../styles/keyframes.css.ts";
import { vars } from "../../styles/tokens.css.ts";

/** The narrow screen's colours in the dark (root.css.ts m, mDark). */
const darkVars = {
  "--m-bg": "#1B1C1F",
  "--m-surface": "#26272B",
  "--m-surface2": "#2C2D31",
  "--raised": "#2A2C31",
  "--m-ink": "#ECECED",
  "--m-muted": "#9A9DA3",
  "--m-subtle": "#6E7177",
  "--m-line": "#34353A",
  "--m-accent": "#EF7A55",
  "--m-accent-bg": "#4A2F25",
  "--m-accent-ink": "#F6A383",
  "--m-green": "#5CC08A",
  "--m-red": "#EB6B58",
  "--m-blue": "#81AEFA",
  "--m-chip": "#313237",
  "--m-bubble": "#313237",
  "--m-thumb": "#3A3B40",
};

/**
 * The narrow screen, as the Android app draws it (apps/android/…/ui/Theme.kt, Glass.kt, Parts.kt, Sheet.kt and the
 * screens): warm paper, ink, and one ember orange that means "this needs you". A dp or an sp is a pixel here.
 */
export const m = style({
  position: "fixed", inset: "0", overflow: "hidden", background: "var(--m-bg)", color: "var(--m-ink)",
  fontSize: vars.textBody, lineHeight: "1.4", WebkitTapHighlightColor: "transparent", WebkitTextSizeAdjust: "100%",
  colorScheme: "light",
  vars: {
    // The phone's type, as Android's: what is read and tapped a size up, what is typed 16 (iOS zooms into less).
    [vars.textControl]: "14px",
    [vars.textBody]: "15px",
    [vars.textInput]: "16px",
    "--m-bg": "#F5F3EF",
    "--m-surface": "#FFFFFF",
    "--m-surface2": "#FBFAF7",
    // Its floating capsules white over the warm page (the wide screen's grey showed too little against it); dark as the wide screen's.
    "--raised": "#FFFFFF",
    "--m-ink": "#24272B",
    "--m-muted": "#7A7D83",
    "--m-subtle": "#A6A8AC",
    "--m-line": "#E7E3DC",
    "--m-accent": "#E5704A",
    "--m-accent-bg": "#FBE6DC",
    "--m-accent-ink": "#B9471F",
    "--m-green": "#2F8F5B",
    "--m-red": "#C9412E",
    "--m-warn": "#D9962B",
    "--m-blue": "#1559C4",
    "--m-chip": "#EFECE6",
    // A step darker than the page (the wide screen's grey sat as light as this warm page, and its bubbles barely showed).
    "--m-bubble": "#E8E4DC",
    "--m-thumb": "#FFFFFF",
    "--m-ease": "cubic-bezier(.2, .8, .2, 1)",
    "--m-standard": "cubic-bezier(.4, 0, .2, 1)",
    "--m-top": "env(safe-area-inset-top, 0px)",
    "--m-foot": "env(safe-area-inset-bottom, 0px)",
  },
  selectors: {
    ":root[data-theme=\"dark\"] &": {
      colorScheme: "dark",
      vars: darkVars,
    },
    // In the desktop app the window has no title bar: its buttons sit at the top left, over where a phone's status bar is,
    // and the bars at the top move the window.
    ":root[data-desktop] &": { vars: { "--m-top": "30px" } },
  },
  "@media": {
    "(prefers-color-scheme: dark)": {
      selectors: {
        ":root:not([data-theme=\"light\"]) &": {
          colorScheme: "dark",
          vars: darkVars,
        },
      },
    },
  },
});
/**
 * Where the phone draws what the wide screen draws, with the wide screen's own parts (a chat's messages, its composer):
 * the wide screen's styles hold there, the phone's resets below do not reach in, and its type is a size up for the
 * narrow screen.
 */
/**
 * The narrow screen's parts drawn where its root is not (over the dark image viewer, which is in a portal of the
 * document's): its colours, the dark ones, and its curves and insets.
 */
export const mDark = style({
  colorScheme: "dark",
  vars: {
    ...darkVars, "--m-ease": "cubic-bezier(.2, .8, .2, 1)", "--m-standard": "cubic-bezier(.4, 0, .2, 1)",
    "--m-top": "env(safe-area-inset-top, 0px)", "--m-foot": "env(safe-area-inset-bottom, 0px)",
  },
});

export const wide = style({
  color: vars.text, fontSize: vars.textBody, lineHeight: "1.55",
  vars: { [vars.textLabel]: "13px", [vars.textSecondary]: "15px", [vars.textBody]: "15px", [vars.neutralBg]: "var(--m-bubble)" },
});
globalStyle(`${m} button:not(${wide} *)`, { font: "inherit", color: "inherit" });
globalStyle(`${m} button`, { WebkitTapHighlightColor: "transparent" });
globalStyle(`${m} p:not(${wide} *)`, { margin: "0" });
globalStyle(`${m} [data-enter]:not(${wide} *)`, { animation: `${mRiseKeyframes} 320ms var(--m-standard) both` });
globalStyle(`${m} [data-enter]`, {
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animation: "none !important", transition: "none !important",
    },
  },
});
