import { globalStyle, style } from "@vanilla-extract/css";
import { mRiseKeyframes } from "../../styles/keyframes.css.ts";
import { vars } from "../../styles/tokens.css.ts";
import { fileLink } from "../../Prose.css.ts";

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
  },
});
globalStyle(`${m} button`, { font: "inherit", color: "inherit", WebkitTapHighlightColor: "transparent" });
/** A link to a file within a message's text keeps its colour: the reset above is for the phone's own buttons. */
globalStyle(`${m} ${fileLink}`, { color: vars.blue });
globalStyle(`${m} p`, { margin: "0" });
globalStyle(`${m} [data-enter]`, { animation: `${mRiseKeyframes} 320ms var(--m-standard) both` });
globalStyle(`${m} [data-enter]`, {
  "@media": {
    "(prefers-reduced-motion: reduce)": {
      animation: "none !important", transition: "none !important",
    },
  },
});
