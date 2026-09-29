import { globalStyle, style } from "@vanilla-extract/css";
import { mRiseKeyframes } from "../../styles/keyframes.css.ts";
import { vars } from "../../styles/tokens.css.ts";

/**
 * The narrow screen, as the Android app draws it (apps/android/…/ui/Theme.kt, Glass.kt, Parts.kt, Sheet.kt and the
 * screens): warm paper, ink, and one ember orange that means "this needs you". A dp or an sp is a pixel here.
 */
export const m = style({
  position: "fixed", inset: "0", overflow: "hidden", background: "var(--m-bg)", color: "var(--m-ink)",
  fontSize: "15px", lineHeight: "1.4", WebkitTapHighlightColor: "transparent", WebkitTextSizeAdjust: "100%",
  colorScheme: "light",
  vars: {
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
    "--m-bubble": "#EDEAE4",
    "--m-thumb": "#FFFFFF",
    "--m-ease": "cubic-bezier(.2, .8, .2, 1)",
    "--m-standard": "cubic-bezier(.4, 0, .2, 1)",
    "--m-top": "env(safe-area-inset-top, 0px)",
    "--m-foot": "env(safe-area-inset-bottom, 0px)",
  },
  selectors: {
    ":root[data-theme=\"dark\"] &": {
      colorScheme: "dark",
      vars: {
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
        "--m-bubble": "#33343A",
        "--m-thumb": "#3A3B40",
      },
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
          vars: {
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
            "--m-bubble": "#33343A",
            "--m-thumb": "#3A3B40",
          },
        },
      },
    },
    // Wider than a phone (a foldable opened, a phone on its side): the app keeps a phone's column in the middle, its
    // pages moving within it; the page's colour goes on to the edges.
    "(min-width: 721px)": {
      left: "calc(50% - 360px)", right: "calc(50% - 360px)", boxShadow: "0 0 0 100vmax var(--m-bg)",
    },
  },
});
/**
 * Where the phone draws what the wide screen draws, with the wide screen's own parts (a chat's messages, its composer):
 * the wide screen's styles hold there, the phone's resets below do not reach in, and its type is a size up for the
 * narrow screen.
 */
export const wide = style({
  color: vars.text, fontSize: vars.textBody, lineHeight: "1.55",
  vars: { [vars.textXs]: "13px", [vars.textSm]: "15px", [vars.textBody]: "15px" },
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
