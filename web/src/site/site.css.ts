// The official site's page (Site.tsx): big type, a thin grid and a beam of ember's orange, near black by default and
// light when chosen (the switch in its bar: ThemeSwitch.tsx; the demo's app follows the same data-theme). What moves is
// CSS (no script runs for it), still for those who ask for less motion.
import { globalStyle, keyframes, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";

const NARROW = "screen and (max-width: 860px)";
const STILL = "(prefers-reduced-motion: reduce)";
const EMBER = "#E5704A";
const BG = "var(--s-bg)";
const FG = "var(--s-fg)";
const MUTED = "var(--s-muted)";
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
const spin = keyframes({ to: { transform: "rotate(1turn)" } });
const enter = keyframes({
  from: { opacity: 0, transform: "perspective(1800px) rotateX(22deg) translateY(60px) scale(.9)" },
  to: { opacity: 1, transform: "none" },
});
const fadeUp = keyframes({ from: { opacity: 0, transform: "translateY(16px)" }, to: { opacity: 1, transform: "none" } });
const fadeIn = keyframes({ from: { opacity: 0 }, to: { opacity: 1 } });
const grow = keyframes({ from: { transform: "scaleY(0)" }, to: { transform: "none" } });
const sway = keyframes({ "0%,100%": { transform: "translateX(-50%) rotate(-4deg)" }, "50%": { transform: "translateX(-50%) rotate(4deg)" } });

/** The grid over a section, fading out from where its light comes. */
const gridLines = {
  backgroundImage: `linear-gradient(${LINE} 1px, transparent 1px), linear-gradient(90deg, ${LINE} 1px, transparent 1px)`,
  backgroundSize: "64px 64px",
};
const white = { backgroundImage: `linear-gradient(180deg, var(--s-title) 30%, ${MUTED})`, WebkitBackgroundClip: "text", backgroundClip: "text", color: "transparent" };

// ---- Nav ----

export const nav = style({
  position: "sticky", top: "0", zIndex: "10", borderBottom: `1px solid ${LINE}`,
  background: `color-mix(in srgb, ${BG} 72%, transparent)`, backdropFilter: "blur(20px) saturate(1.4)", WebkitBackdropFilter: "blur(20px) saturate(1.4)",
});
export const navRow = style({ display: "flex", alignItems: "center", height: "64px", gap: "28px" });
export const logo = style({ display: "block", height: "28px", width: "auto" });
export const navLinks = style({
  display: "flex", gap: "26px", marginLeft: "auto", marginRight: "4px", fontSize: "15px", color: MUTED,
  "@media": { [NARROW]: { display: "none" } },
});
export const navLink = style({ transition: "color .2s", selectors: { "&:hover": { color: FG } } });
/** The theme switch (ThemeSwitch.tsx): three small buttons in a pill. */
export const themeSwitch = style({ "@media": { [NARROW]: { marginLeft: "auto" } }, display: "flex", gap: "2px", padding: "3px", borderRadius: "999px", background: CARD, boxShadow: `inset 0 0 0 1px ${LINE}` });
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
  position: "relative", display: "inline-flex", alignItems: "center", gap: "8px", height: "40px", padding: "0 20px", borderRadius: "999px",
  fontSize: "15px", fontWeight: "550", whiteSpace: "nowrap", transition: `transform .2s ${vars.easeOut}, box-shadow .2s, background .2s`,
  selectors: {
    "&:hover": { transform: "translateY(-2px)" },
    "&[data-kind=\"primary\"]": { background: "var(--s-primary)", color: "var(--s-on-primary)" },
    "&[data-kind=\"primary\"]:hover": { boxShadow: `0 10px 34px -8px color-mix(in srgb, ${EMBER} 80%, transparent)` },
    "&[data-kind=\"ghost\"]": { color: FG, boxShadow: `inset 0 0 0 1px ${ink(18)}` },
    "&[data-kind=\"ghost\"]:hover": { background: `${ink(6)}` },
    "&[data-size=\"large\"]": { height: "50px", padding: "0 28px", fontSize: "16px" },
  },
});
export const actions = style({ display: "flex", gap: "12px", justifyContent: "center", flexWrap: "wrap" });

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
  background: `conic-gradient(from 180deg at 50% 0%, transparent 40%, color-mix(in srgb, ${EMBER} 60%, transparent) 50%, transparent 60%)`,
  animation: `${sway} 14s ease-in-out infinite`, "@media": { [STILL]: { animation: "none" } },
});
export const title = style({
  margin: "0 auto", fontSize: "clamp(64px, 15vw, 232px)", lineHeight: ".92", letterSpacing: "-.06em", fontWeight: "800",
  animation: `${fadeUp} .9s .06s ${vars.easeOut} both`,
});
/**
 * A line of the title that is a domain. The one the page was opened on (data-host on the root; still.fail otherwise) is
 * lit, ember orange and glowing; the other sits dim behind it. Padded, so what hangs out of a letter (y, f) is not cut
 * off by the text clip, and pulled back by as much.
 */
const lit = {
  backgroundImage: `linear-gradient(180deg, #FFC2A3, ${EMBER} 70%)`, WebkitBackgroundClip: "text", backgroundClip: "text", color: "transparent",
  filter: `drop-shadow(0 0 48px color-mix(in srgb, ${EMBER} 45%, transparent))`,
};
export const titleDomain = style({
  display: "inline-block", padding: ".04em .1em .16em", margin: "-.04em -.1em -.16em",
  color: "color-mix(in srgb, var(--s-title) 16%, var(--s-bg))",
  selectors: {
    [`:root:not([data-host="youdid.wtf"]) &[data-domain="still.fail"]`]: lit,
    [`:root[data-host="youdid.wtf"] &[data-domain="youdid.wtf"]`]: lit,
  },
});
/**
 * A domain's dot and what the domain says in Chinese, led off it by a line: up from the first line's dot, down from the
 * second's. Lit with its line. Its own colour, not the line's text clip, which ends at the line's box.
 */
export const dot = style({ position: "relative" });
export const dotNote = style({
  position: "absolute", left: "50%", top: ".78em", display: "flex", flexDirection: "column", alignItems: "center",
  transform: "translateX(-50%)", color: "color-mix(in srgb, var(--s-title) 30%, var(--s-bg))", WebkitTextFillColor: "currentColor",
  pointerEvents: "none", animation: `${fadeIn} .6s .7s ${vars.easeOut} both`,
  selectors: {
    "&[data-up]": { top: "auto", bottom: ".3em", flexDirection: "column-reverse" },
    [`:root:not([data-host="youdid.wtf"]) [data-domain="still.fail"] &, :root[data-host="youdid.wtf"] [data-domain="youdid.wtf"] &`]: { color: EMBER },
  },
});
export const dotLine = style({
  width: "2px", height: ".62em", background: "currentColor", opacity: ".8", transformOrigin: "50% 0",
  animation: `${grow} .6s .7s ${vars.easeOut} both`, "@media": { [STILL]: { animation: "none" } },
  selectors: { [`${dotNote}[data-up] &`]: { transformOrigin: "50% 100%" } },
});
export const dotSay = style({
  marginTop: "12px", fontSize: "max(.11em, 14px)", fontWeight: "700", letterSpacing: ".08em", lineHeight: "1", whiteSpace: "nowrap",
  selectors: { [`${dotNote}[data-up] &`]: { marginTop: "0", marginBottom: "12px" } },
});

export const heroActions = style({ marginTop: "44px", animation: `${fadeUp} .9s .24s ${vars.easeOut} both` });

/** The demo's stage: it rises out of a tilt as the page opens, a beam of light running round its edge. */
export const stage = style({
  position: "relative", margin: "80px auto 0", maxWidth: "1200px", animation: `${enter} 1.4s .3s cubic-bezier(.2,.8,.2,1) both`,
  "@media": { [NARROW]: { marginTop: "52px" }, [STILL]: { animation: "none" } },
});
/** Its glow on the page under it. */
export const stageGlow = style({
  position: "absolute", inset: "12% 8% -4%", zIndex: "-1", borderRadius: "40px", filter: "blur(70px)",
  background: `color-mix(in srgb, ${EMBER} 40%, transparent)`, opacity: ".45",
});
/** The edge the beam is seen through: a hairline of a turning light around the box. */
export const edge = style({
  position: "relative", padding: "1px", borderRadius: "20px", overflow: "hidden", background: `${ink(14)}`,
  "@media": { [NARROW]: { borderRadius: "14px" } },
  selectors: {
    "&::before": {
      content: "\"\"", position: "absolute", left: "50%", top: "50%", width: "200vmax", height: "200vmax", marginLeft: "-100vmax", marginTop: "-100vmax",
      background: `conic-gradient(transparent 0 72%, ${EMBER} 84%, #FFE2D2 89%, transparent 95%)`,
      animation: `${spin} 7s linear infinite`, "@media": { [STILL]: { animation: "none" } },
    },
  },
});
/** The demo's box (demo/): the app in it, at its size. */
export const demo = style({
  position: "relative", height: "720px", borderRadius: "19px", overflow: "hidden", background: vars.canvas,
  "@media": { [NARROW]: { borderRadius: "13px", height: "620px" } },
});
/** The demo's opening frame, built into the page: the phone's app where the box is narrow (as the demo picks: under
 *  700 wide, the box being the page's width less its margins), the desktop's elsewhere. */
const PHONE_BOX = "screen and (max-width: 747px)";
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
export const sectionTitle = style({
  margin: "0 0 72px", textAlign: "center", fontSize: "clamp(34px, 6vw, 72px)", lineHeight: "1.05", letterSpacing: "-.045em", fontWeight: "700",
  ...white, "@media": { [NARROW]: { marginBottom: "48px" } },
});
/** A title's second line, dimmer. */
export const faint = style({ display: "block", backgroundImage: `linear-gradient(180deg, ${MUTED}, var(--s-faint))`, WebkitBackgroundClip: "text", backgroundClip: "text", color: "transparent" });

// The mesh: stations linked to each other and to the devices people talk from; ember cloud apart, for accounts only.
export const network = style({
  display: "block", width: "100%", maxWidth: "1000px", height: "auto", margin: "0 auto", overflow: "visible",
  selectors: { "&[data-shape=\"tall\"]": { display: "none", maxWidth: "420px" } },
  "@media": { [NARROW]: { selectors: { "&[data-shape=\"wide\"]": { display: "none" }, "&[data-shape=\"tall\"]": { display: "block" } } } },
});
export const wire = style({
  fill: "none", stroke: `${ink(18)}`, strokeWidth: "1.5", strokeDasharray: "4 6",
  selectors: {
    "&[data-kind=\"mesh\"]": { stroke: `color-mix(in srgb, ${EMBER} 55%, transparent)`, strokeWidth: "2", strokeDasharray: "none" },
    "&[data-kind=\"cloud\"]": { stroke: `${ink(10)}`, strokeDasharray: "2 6" },
  },
});
export const packet = style({ fill: EMBER, filter: `drop-shadow(0 0 6px ${EMBER})`, selectors: { "&[data-kind=\"mesh\"]": { fill: "#FFD2BC" } } });
export const node = style({
  fill: "var(--s-node)", stroke: `${ink(14)}`, strokeWidth: "1.2",
  selectors: { "&[data-kind=\"cloud\"]": { fill: "transparent", strokeDasharray: "4 5", stroke: `${ink(22)}` } },
});
// Words over the lines keep a margin of the page's dark around them.
const halo = { paintOrder: "stroke", stroke: BG, strokeWidth: "5px", strokeLinejoin: "round" } as const;
export const nodeLabel = style({ fill: FG, fontSize: "15px", fontWeight: "600", fontFamily: vars.fontBody, ...halo });
export const hub = style({ fill: `color-mix(in srgb, ${EMBER} 14%, ${BG})`, stroke: EMBER, strokeWidth: "1.5" });
const pulse = keyframes({ "0%": { transform: "scale(1)", opacity: ".6" }, "100%": { transform: "scale(1.8)", opacity: "0" } });
export const ring = style({
  fill: "none", stroke: EMBER, strokeWidth: "1.5", transformBox: "fill-box", transformOrigin: "center",
  animation: `${pulse} 2.8s ease-out infinite`, "@media": { [STILL]: { animation: "none", opacity: "0" } },
});

// Installing.
export const terminal = style({
  position: "relative", maxWidth: "840px", margin: "0 auto", borderRadius: "18px", overflow: "hidden",
  background: "#0F0F12", color: "#E9E9EA", border: `1px solid ${LINE}`,
  boxShadow: `0 50px 100px -40px color-mix(in srgb, ${EMBER} 50%, transparent)`,
  font: `16px/1.8 ${vars.fontMono}`, "@media": { [NARROW]: { fontSize: "12px" } },
});
export const terminalBar = style({ display: "flex", gap: "8px", padding: "16px 18px", borderBottom: `1px solid ${LINE}` });
export const terminalDot = style({ width: "12px", height: "12px", borderRadius: "50%", background: "#2A2A30" });
export const terminalBody = style({ padding: "24px 28px 30px", overflowX: "auto" });
const type = keyframes({ from: { width: "0" }, to: { width: "var(--chars)" } });
const blink = keyframes({ "50%": { borderColor: "transparent" } });
export const typed = style({
  display: "inline-block", verticalAlign: "bottom", overflow: "hidden", whiteSpace: "nowrap", borderRight: `2px solid ${EMBER}`,
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
export const prompt = style({ color: EMBER, userSelect: "none" });

// ---- Footer ----

export const footer = style({ padding: "32px 0 48px", color: DIM, fontSize: "14px", borderTop: `1px solid ${LINE}` });
export const footerRow = style({ display: "flex", alignItems: "center", gap: "24px" });
export const footerFirst = style({ marginRight: "auto" });
