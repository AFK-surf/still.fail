// The official site's page (Site.tsx): big type, a thin grid and a beam of still.fail's orange, near black by default and
// light when chosen (the switch in its bar: ThemeSwitch.tsx; the demo's app follows the same data-theme). What moves is
// CSS (no script runs for it), still for those who ask for less motion.
import { createVar, globalStyle, keyframes, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

const NARROW = "screen and (max-width: 860px)";
const STILL = "(prefers-reduced-motion: reduce)";
const ORANGE = "#E5704A";
const BG = "var(--s-bg)";
const FG = "var(--s-fg)";
const DIM = "var(--s-dim)";
/** The page's ink at a strength: white on dark, black on light. */
const ink = (percent: number) => `color-mix(in srgb, var(--s-ink) ${percent}%, transparent)`;
const LINE = ink(9);
const CARD = ink(3.5);

// The palette, dark (the site's own look, and its default) and light; "system" (no data-theme) follows the system.
const DARK = {
  "--s-bg": "#09090B", "--s-fg": "#F4F4F5", "--s-muted": "#A1A1AA", "--s-dim": "#71717A", "--s-faint": "#52525B", "--s-ink": "#FFFFFF",
  "--s-node": "#111114", "--s-primary": "#FAFAFA", "--s-on-primary": "#09090B", "--s-title": "#FFFFFF", "--s-mono": "invert(1)",
};
const LIGHT = {
  "--s-bg": "#FAFAF9", "--s-fg": "#18181B", "--s-muted": "#52525B", "--s-dim": "#71717A", "--s-faint": "#A1A1AA", "--s-ink": "#000000",
  "--s-node": "#FFFFFF", "--s-primary": "#18181B", "--s-on-primary": "#FAFAFA", "--s-title": "#09090B", "--s-mono": "none",
};
globalStyle(":root", { vars: LIGHT });
globalStyle(":root:not([data-theme=\"light\"])", { "@media": { "(prefers-color-scheme: dark)": { vars: DARK } } });
globalStyle(":root[data-theme=\"dark\"]", { vars: DARK });

// The page's own type; the app's (14px) is the demo's (demo/demo.css.ts).
globalStyle("body", { font: `16px/1.6 ${vars.fontBody}`, background: BG });
globalStyle("html", { scrollBehavior: "smooth", background: BG });

export const page = style({ background: BG, color: FG, overflowX: "clip" });
export const wrap = style({ maxWidth: "1160px", margin: "0 auto", padding: "0 24px" });

// ---- Motion ----

const rise = keyframes({ from: { opacity: 0, transform: "translateY(48px) scale(.97)" }, to: { opacity: 1, transform: "none" } });
/** Comes up into place as it scrolls into view (a scroll-driven animation; where there are none, it is simply there). */
export const reveal = style({
  animation: `${rise} linear both`, animationTimeline: "view()", animationRange: "entry 0% cover 28%",
  "@media": { [STILL]: { animation: "none" } },
});
const enter = keyframes({
  from: { opacity: 0, transform: "perspective(1800px) rotateX(22deg) translateY(60px) scale(.9)" },
  to: { opacity: 1, transform: "none" },
});
const fadeUp = keyframes({ from: { opacity: 0, transform: "translateY(16px)" }, to: { opacity: 1, transform: "none" } });
const sway = keyframes({ "0%,100%": { transform: "translateX(-50%) rotate(-4deg)" }, "50%": { transform: "translateX(-50%) rotate(4deg)" } });

/** The grid over a section, fading out from where its light comes. */
const gridLines = {
  backgroundImage: `linear-gradient(${LINE} 1px, transparent 1px), linear-gradient(90deg, ${LINE} 1px, transparent 1px)`,
  backgroundSize: "64px 64px",
};

// While the theme changes (ThemeSwitch.tsx), nothing eases into it: the page changes in one frame.
globalStyle(":root[data-theme-switching] *, :root[data-theme-switching] *::before, :root[data-theme-switching] *::after", { transition: "none !important" });

// ---- Nav ----

export const nav = style({
  position: "sticky", top: "0", zIndex: "10", borderBottom: `1px solid ${LINE}`,
  background: `color-mix(in srgb, ${BG} 72%, transparent)`, backdropFilter: "blur(20px) saturate(1.4)", WebkitBackdropFilter: "blur(20px) saturate(1.4)",
});
export const navRow = style({ display: "flex", alignItems: "center", height: "64px", gap: "28px" });
/** The name in the bar: the station buddy and still.fail, its .fail in still.fail's orange. */
export const brand = style({ display: "flex", alignItems: "center", gap: "10px", fontSize: "22px", fontWeight: "700", letterSpacing: "-.03em", color: FG });
export const brandTail = style({ color: ORANGE });
export const logo = style({ display: "block", height: "28px", width: "auto" });
// The logo on the left, the rest of the bar on the right.
globalStyle(`${navRow} > :first-child`, { marginRight: "auto" });
export const navLink = style({ transition: "color .2s", selectors: { "&:hover": { color: FG } } });
// The downloads for the device the page is on (data-platform on the root): none shows without it (an iPhone).
export const forAndroid = style({ display: "none", selectors: { ":root[data-platform=\"android\"] &": { display: "inline" } } });
export const forComputer = style({ display: "none", selectors: { ":root:is([data-platform=\"mac\"], [data-platform=\"desktop\"]) &": { display: "inline-block" } } });
globalStyle(`${navRow} ${navLink}`, { color: "var(--s-muted)", fontSize: "15px" });
globalStyle(`${navRow} button${navLink}`, { padding: "8px 0", border: "0", background: "none", font: "inherit", cursor: "default" });

/** The downloads' card, under their word while the pointer is on it (or it has focus): frosted, as the bar is. */
export const menu = style({ position: "relative" });
export const menuCard = style({
  position: "absolute", top: "calc(100% + 14px)", left: "50%", display: "grid", gridTemplateColumns: "1fr 1fr", gap: "6px",
  padding: "6px", borderRadius: "20px", whiteSpace: "nowrap",
  background: `color-mix(in srgb, var(--s-node) 84%, transparent)`, backdropFilter: "blur(20px) saturate(1.4)", WebkitBackdropFilter: "blur(20px) saturate(1.4)",
  boxShadow: `0 16px 48px -16px rgba(0, 0, 0, .5), inset 0 0 0 1px ${LINE}`,
  opacity: 0, visibility: "hidden", transform: "translate(-50%, -6px)", transition: `opacity .2s, transform .25s ${vars.easeOut}, visibility 0s .25s`,
  selectors: {
    // The gap between the word and the card keeps it open on the way down.
    "&::before": { content: "\"\"", position: "absolute", left: 0, right: 0, bottom: "100%", height: "14px" },
    [`${menu}:hover &, ${menu}:focus-within &`]: { opacity: 1, visibility: "visible", transform: "translate(-50%, 0)", transition: `opacity .2s, transform .25s ${vars.easeOut}` },
  },
});
export const menuItem = style({
  display: "grid", gridTemplateRows: "auto 1fr auto", justifyItems: "start", gap: "2px", width: "150px", minHeight: "178px", padding: "14px",
  borderRadius: "15px", fontSize: "13px", color: DIM, transition: "background .2s",
  selectors: { "a&:hover": { background: CARD } },
});
globalStyle(`${menuItem} > b`, { fontSize: "17px", fontWeight: "650", color: FG, letterSpacing: "-.01em" });
export const menuGo = style({ gridRow: "3", color: FG, fontWeight: "550" });
/** The code itself stays dark on white in either theme, with the quiet margin a scanner wants. */
export const scanCode = style({ display: "block", width: "122px", height: "122px", padding: "8px", borderRadius: "10px", background: "#fff", imageRendering: "pixelated" });

/** The theme switch (ThemeSwitch.tsx): three small buttons in a pill. */
export const themeSwitch = style({ display: "flex", gap: "2px", padding: "3px", borderRadius: "999px", background: CARD, boxShadow: `inset 0 0 0 1px ${LINE}` });
export const themeChoice = style({
  display: "grid", placeItems: "center", width: "30px", height: "30px", padding: "0", border: "0", borderRadius: "999px",
  background: "transparent", color: DIM, cursor: "pointer", transition: "color .2s, background .2s",
  selectors: { "&:hover": { color: FG }, "&[aria-checked=\"true\"]": { background: ink(10), color: FG } },
});
/** Pictures drawn for a light ground and for a dark one (web/public's -dark twins): the one for the page's theme shows. */
export const lightOnly = style({ display: "contents" });
export const darkOnly = style({ display: "none" });
globalStyle(`:root[data-theme="dark"] ${lightOnly}`, { display: "none" });
globalStyle(`:root[data-theme="dark"] ${darkOnly}`, { display: "contents" });
globalStyle(`:root:not([data-theme="light"]) ${lightOnly}`, { "@media": { "(prefers-color-scheme: dark)": { display: "none" } } });
globalStyle(`:root:not([data-theme="light"]) ${darkOnly}`, { "@media": { "(prefers-color-scheme: dark)": { display: "contents" } } });
// On a phone the bar keeps the logo and the theme; the hero has the buttons.
export const navButton = style({ "@media": { [NARROW]: { display: "none" } } });

// ---- Buttons ----

export const button = style({
  position: "relative", overflow: "hidden", display: "inline-flex", alignItems: "center", gap: "8px", height: "40px", padding: "0 20px", borderRadius: "999px",
  fontSize: "15px", fontWeight: "550", whiteSpace: "nowrap", transition: `transform .2s ${vars.easeOut}, box-shadow .2s, background .2s`,
  selectors: {
    "&:hover": { transform: "translateY(-2px)" },
    "&[data-kind=\"primary\"]": { background: "var(--s-primary)", color: "var(--s-on-primary)" },
    // A light sweeping across the main one as the pointer comes onto it.
    "&[data-kind=\"primary\"]::after": {
      content: "\"\"", position: "absolute", inset: "0", pointerEvents: "none", transform: "translateX(-120%) skewX(-20deg)",
      background: `linear-gradient(90deg, transparent, color-mix(in srgb, ${ORANGE} 45%, transparent), transparent)`,
    },
    "&[data-kind=\"primary\"]:hover::after": { transform: "translateX(120%) skewX(-20deg)", transition: `transform .6s ${vars.easeOut}` },
    "&[data-kind=\"primary\"]:hover": { boxShadow: `0 10px 34px -8px color-mix(in srgb, ${ORANGE} 80%, transparent)` },
    "&[data-kind=\"ghost\"]": { color: FG, boxShadow: `inset 0 0 0 1px ${ink(18)}` },
    "&[data-kind=\"ghost\"]:hover": { background: `${ink(6)}` },
    "&[data-size=\"large\"]": { height: "50px", padding: "0 28px", fontSize: "16px" },
  },
});
export const actions = style({ display: "flex", gap: "12px", justifyContent: "center", flexWrap: "wrap" });

/** A button's words and what they turn into under them, in a window a line high: rolled up a line on hover. */
export const roll = style({ display: "grid", justifyItems: "center", overflow: "hidden", height: "1.3em", lineHeight: "1.3em" });
globalStyle(`${roll} > span`, { transition: `transform .45s cubic-bezier(.7, 0, .2, 1)` });
globalStyle(`${button}:hover ${roll} > span`, { transform: "translateY(-100%)" });
globalStyle(`${button}:hover ${roll} > span + span`, { transitionDelay: ".03s" });

// ---- Hero ----

export const hero = style({
  position: "relative", paddingTop: "120px", paddingBottom: "110px", textAlign: "center", isolation: "isolate",
  "@media": { [NARROW]: { paddingTop: "64px", paddingBottom: "72px" } },
});
export const grid = style({
  position: "absolute", inset: "0", zIndex: "-1", pointerEvents: "none", ...gridLines,
  maskImage: "radial-gradient(ellipse 60% 50% at 50% 0%, #000 20%, transparent 72%)",
  WebkitMaskImage: "radial-gradient(ellipse 60% 50% at 50% 0%, #000 20%, transparent 72%)",
});
/** Light falling from the top, swaying a little. */
export const beam = style({
  position: "absolute", left: "50%", top: "-160px", width: "1000px", height: "760px", zIndex: "-1", pointerEvents: "none",
  transformOrigin: "50% 0", transform: "translateX(-50%)", filter: "blur(44px)", opacity: ".75",
  background: `conic-gradient(from 180deg at 50% 0%, transparent 40%, color-mix(in srgb, ${ORANGE} 60%, transparent) 50%, transparent 60%)`,
  animation: `${sway} 14s ease-in-out infinite`, "@media": { [STILL]: { animation: "none" } },
});
export const title = style({
  margin: "0 auto", fontSize: "clamp(64px, 15vw, 232px)", lineHeight: ".92", letterSpacing: "-.06em", fontWeight: "800",
  animation: `${fadeUp} .9s .06s ${vars.easeOut} both`,
  // Script opens the page with the Chinese and brings the English in itself (motion.ts).
  selectors: { ":root[data-motion] &": { animation: "none" } },
});
/** The title and, over it, the intro. */
export const titleStage = style({ position: "relative" });
/**
 * The intro: the two lines in Chinese, large, over where the title will be. Never seen: it only lays out where each
 * character stands while large; the characters on the dots are the ones drawn there (motion.ts).
 */
export const intro = style({
  position: "absolute", inset: "0", display: "none", visibility: "hidden", flexDirection: "column", alignItems: "center", justifyContent: "center",
  fontSize: "clamp(56px, 12.5vw, 196px)", fontWeight: "900", lineHeight: "1.08", letterSpacing: ".02em", pointerEvents: "none",
  selectors: { ":root[data-motion] &": { display: "flex" } },
});
export const introLine = style({
  display: "block", whiteSpace: "nowrap", color: "var(--s-title)",
  selectors: {
    [`:root:not([data-host="youdid.wtf"]) &[data-line="still.fail"], :root[data-host="youdid.wtf"] &[data-line="youdid.wtf"]`]: {
      color: ORANGE, textShadow: `0 0 60px color-mix(in srgb, ${ORANGE} 55%, transparent)`,
    },
  },
});
export const introChar = style({ display: "inline-block", opacity: 0 });
/**
 * A line of the title that is a domain. The one the page was opened on (data-host on the root; still.fail otherwise) is
 * lit, warm orange and glowing; the other sits dim behind it. Padded, so what hangs out of a letter (y, f) is not cut
 * off by the text clip, and pulled back by as much.
 */
const lit = {
  backgroundImage: `linear-gradient(180deg, #FFC2A3, ${ORANGE} 70%)`, WebkitBackgroundClip: "text", backgroundClip: "text", color: "transparent",
};
const LIT = `:root:not([data-host="youdid.wtf"]) [data-domain="still.fail"], :root[data-host="youdid.wtf"] [data-domain="youdid.wtf"]`;
export const titleDomain = style({
  display: "inline-block", color: "color-mix(in srgb, var(--s-title) 16%, var(--s-bg))",
  selectors: {
    [`:root:not([data-host="youdid.wtf"]) &[data-domain="still.fail"], :root[data-host="youdid.wtf"] &[data-domain="youdid.wtf"]`]: {
      filter: `drop-shadow(0 0 48px color-mix(in srgb, ${ORANGE} 45%, transparent))`,
    },
  },
});
/** The English of a line, painted on its own (so that it can be brought in apart from the Chinese on its dot). */
export const word = style({
  // Unseen until the opening brings it in, when script plays one.
  selectors: { ":root[data-motion] &": { opacity: 0 } },
});
globalStyle(`:is(${LIT}) ${word}`, lit);
/**
 * A domain's dot and what the domain says in Chinese, written upright on it (above, and below when it goes on), lit
 * with its line. Its own colour, not the line's text clip, which does not reach positioned boxes.
 */
export const dot = style({
  position: "relative", display: "inline-block", width: "0",
  color: "color-mix(in srgb, var(--s-title) 30%, var(--s-bg))", WebkitTextFillColor: "currentColor",
  selectors: {
    [`:root:not([data-host="youdid.wtf"]) [data-domain="still.fail"] &, :root[data-host="youdid.wtf"] [data-domain="youdid.wtf"] &`]: { color: ORANGE },
  },
});
/** Where the words stand, in the title's em: just clear of the dot's top, or of the baseline under it. */
export const dotSay = style({
  position: "absolute", left: "-.12em", transform: "translateX(-50%)", pointerEvents: "none",
  selectors: { "&[data-at=above]": { bottom: ".22em" }, "&[data-at=below]": { top: ".06em" } },
});
export const dotWords = style({
  display: "block", writingMode: "vertical-rl", textOrientation: "upright",
  fontSize: "max(.1em, 8px)", fontWeight: "700", lineHeight: "1", whiteSpace: "nowrap",
});

/** A character of those words: they land one at a time (motion.ts), unseen till then when script will move them. */
/**
 * A character of those words: a box of its own size, the glyph centred in it, so that the glyph can fly in at another
 * size and place (motion.ts) and end exactly where it rests, the same element drawn the same way.
 */
export const dotChar = style({ position: "relative", display: "inline-block", inlineSize: "1em", blockSize: "1em", marginInlineEnd: ".12em", verticalAlign: "top" });
export const dotGlyph = style({
  position: "absolute", inset: "0", display: "flex", alignItems: "center", justifyContent: "center", whiteSpace: "nowrap",
  selectors: { ":root[data-motion] &": { opacity: 0 } },
});

export const heroActions = style({
  marginTop: "clamp(64px, 7vw, 100px)", animation: `${fadeUp} .9s .24s ${vars.easeOut} both`,
  // With the opening, held until the title has landed (motion.ts), not for a time guessed at.
  selectors: { ":root[data-motion] &": { animationDelay: "0s", animationPlayState: "paused" }, ":root[data-motion][data-opened] &": { animationPlayState: "running" } },
});

/** The demo's stage: it rises out of a tilt as the page opens, a beam of light running round its edge. */
export const stage = style({
  position: "relative", margin: "80px auto 0", maxWidth: "1200px", animation: `${enter} 1.4s .3s cubic-bezier(.2,.8,.2,1) both`,
  "@media": { [NARROW]: { marginTop: "52px" }, [STILL]: { animation: "none" } },
  selectors: { ":root[data-motion] &": { animationDelay: ".1s", animationPlayState: "paused" }, ":root[data-motion][data-opened] &": { animationPlayState: "running" } },
});
/** Its glow on the page under it. */
export const stageGlow = style({
  position: "absolute", inset: "12% 8% -4%", zIndex: "-1", borderRadius: "40px", filter: "blur(70px)",
  background: `color-mix(in srgb, ${ORANGE} 40%, transparent)`, opacity: ".45",
});
/**
 * The edge the beam is seen through: a hairline of a turning light around the box. The light is the edge's own
 * background, turned by animating the gradient's angle (a registered property), not a huge spinning layer behind it:
 * the browser left parts of that layer unpainted at times, and the beam went missing along the edge.
 */
const beamAngle = createVar({ syntax: "<angle>", inherits: false, initialValue: "0deg" });
const turn = keyframes({ to: { vars: { [beamAngle]: "360deg" } } });
/** Where the demo shows the phone's app (under 700 wide, the box being the page's width less its margins): its box
 *  has a phone's large corners, around its composer's: the capsule's 26px plus the 10px it sits in from the box. */
const PHONE_BOX = "screen and (max-width: 747px)";
export const edge = style({
  position: "relative", padding: "1px", borderRadius: "20px",
  background: `conic-gradient(from ${beamAngle}, transparent 0 72%, ${ORANGE} 84%, #FFE2D2 89%, transparent 95%), ${ink(14)}`,
  animation: `${turn} 7s linear infinite`,
  "@media": { [NARROW]: { borderRadius: "14px" }, [PHONE_BOX]: { borderRadius: "37px" }, [STILL]: { animation: "none" } },
});
/** The demo's box (demo/): the app in it, at its size. */
export const demo = style({
  position: "relative", height: "720px", borderRadius: "19px", overflow: "hidden", background: vars.canvas,
  "@media": { [NARROW]: { borderRadius: "13px", height: "620px" }, [PHONE_BOX]: { borderRadius: "36px" } },
});
/** The demo's opening frame, built into the page: the phone's app where the box is narrow (as the demo picks: under
 *  700 wide, the box being the page's width less its margins), the desktop's elsewhere. */
export const frameWide = style({ height: "100%", "@media": { [PHONE_BOX]: { display: "none" } } });
export const framePhone = style({ height: "100%", display: "none", "@media": { [PHONE_BOX]: { display: "block" } } });
export const key = style({ padding: "2px 8px", borderRadius: "6px", background: `${ink(8)}`, color: FG, fontWeight: "550", whiteSpace: "nowrap" });

// ---- Sections ----

export const section = style({ position: "relative", padding: "130px 0", isolation: "isolate", "@media": { [NARROW]: { padding: "80px 0" } } });
/** A section's light: the grid, fading from its top. */
export const sectionLight = style({
  position: "absolute", inset: "0", zIndex: "-1", pointerEvents: "none", ...gridLines,
  maskImage: "radial-gradient(ellipse 50% 40% at 50% 0%, #000 10%, transparent 70%)",
  WebkitMaskImage: "radial-gradient(ellipse 50% 40% at 50% 0%, #000 10%, transparent 70%)",
});
// Installing.
export const terminal = style({
  position: "relative", maxWidth: "840px", margin: "0 auto", borderRadius: "18px", overflow: "hidden",
  background: "#0F0F12", color: "#E9E9EA", border: `1px solid ${LINE}`,
  boxShadow: `0 50px 100px -40px color-mix(in srgb, ${ORANGE} 50%, transparent)`,
  font: `16px/1.8 ${vars.fontMono}`, "@media": { [NARROW]: { fontSize: "12px" } },
});
export const terminalBar = style({ display: "flex", gap: "8px", padding: "16px 18px", borderBottom: `1px solid ${LINE}` });
export const terminalDot = style({ width: "12px", height: "12px", borderRadius: "50%", background: "#2A2A30" });
export const terminalBody = style({ padding: "24px 28px 30px", overflowX: "auto" });
const type = keyframes({ from: { width: "0" }, to: { width: "var(--chars)" } });
const blink = keyframes({ "50%": { borderColor: "transparent" } });
export const typed = style({
  display: "inline-block", verticalAlign: "bottom", overflow: "hidden", whiteSpace: "nowrap", borderRight: `2px solid ${ORANGE}`,
  // Typed as the terminal comes up the screen (where there are no scroll-driven animations, typed at once).
  animation: `${type} linear both, ${blink} .9s step-end infinite`, animationTimingFunction: "steps(var(--steps)), step-end",
  animationTimeline: "view(), auto", animationRange: "entry 80% cover 42%, normal",
  "@media": { [STILL]: { animation: "none", width: "var(--chars)" } },
});
const appear = keyframes({ from: { opacity: 0 }, to: { opacity: 1 } });
export const output = style({
  display: "block", color: DIM, animation: `${appear} linear both`, animationTimeline: "view()",
  selectors: {
    "&[data-ok]": { color: "#7FD4A1" },
    "&[data-at=\"1\"]": { animationRange: "cover 44% cover 47%" },
    "&[data-at=\"2\"]": { animationRange: "cover 48% cover 51%" },
    "&[data-at=\"3\"]": { animationRange: "cover 52% cover 55%" },
  },
  "@media": { [STILL]: { animation: "none", opacity: 1 } },
});
export const prompt = style({ color: ORANGE, userSelect: "none" });

// ---- Footer ----

export const footer = style({ padding: "32px 0 48px", color: DIM, fontSize: "14px", borderTop: `1px solid ${LINE}` });
export const footerRow = style({ display: "flex", alignItems: "center", gap: "24px" });
export const footerFirst = style({ marginRight: "auto" });
