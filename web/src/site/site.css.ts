// The official site's page (Site.tsx): quiet type on a light page (dark when chosen: the switch in its bar,
// ThemeSwitch.tsx; the demo's app follows the same data-theme), still.fail's orange only where things connect. What
// moves is CSS and the picture's SVG (no script runs for it), still for those who ask for less motion.
import { globalStyle, keyframes, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

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

// The palette, light (the default) and dark; "system" (no data-theme) follows the system.
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

const fadeUp = keyframes({ from: { opacity: 0, transform: "translateY(16px)" }, to: { opacity: 1, transform: "none" } });

// While the theme changes (ThemeSwitch.tsx), nothing eases into it: the page changes in one frame.
globalStyle(":root[data-theme-switching] *, :root[data-theme-switching] *::before, :root[data-theme-switching] *::after", { transition: "none !important" });

// ---- Nav ----

export const nav = style({
  position: "sticky", top: "0", zIndex: "10", borderBottom: `1px solid ${LINE}`,
  background: `color-mix(in srgb, ${BG} 72%, transparent)`, backdropFilter: "blur(20px) saturate(1.4)", WebkitBackdropFilter: "blur(20px) saturate(1.4)",
});
export const navRow = style({ display: "flex", alignItems: "center", height: "64px", gap: "28px" });
/** The name in the bar: the station buddy and still.fail, its .fail in still.fail's orange. */
export const brand = style({ display: "flex", alignItems: "center", gap: "10px", fontSize: vars.textHeading, fontWeight: "600", letterSpacing: "-.03em", color: FG });
export const brandTail = style({ color: ORANGE });
export const logo = style({ display: "block", height: "28px", width: "auto" });
// The logo on the left, the rest of the bar on the right.
globalStyle(`${navRow} > :first-child`, { marginRight: "auto" });
export const navLink = style({ transition: "color .2s", selectors: { "&:hover": { color: FG } } });
// The downloads for the device the page is on (data-platform on the root): none shows without it (an iPhone).
export const forAndroid = style({ display: "none", selectors: { ":root[data-platform=\"android\"] &": { display: "inline" } } });
export const forComputer = style({ display: "none", selectors: { ":root:is([data-platform=\"mac\"], [data-platform=\"desktop\"]) &": { display: "inline-block" } } });
globalStyle(`${navRow} ${navLink}`, { color: "var(--s-muted)", fontSize: vars.textTitle });
globalStyle(`${navRow} button${navLink}`, { padding: "8px 0", border: "0", background: "none", font: "inherit", cursor: "default" });

/** The downloads' card, under their word while the pointer is on it (or it has focus): frosted, as the bar is. */
export const menu = style({ position: "relative" });
export const menuCard = style({
  position: "absolute", top: "calc(100% + 14px)", left: "50%", display: "grid", gridAutoFlow: "column", gridAutoColumns: "1fr", gap: "6px",
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
  borderRadius: "15px", fontSize: vars.textUi, color: DIM, transition: "background .2s",
  selectors: { "a&:hover": { background: CARD } },
});
globalStyle(`${menuItem} > b`, { fontSize: vars.textTitle, fontWeight: "600", color: FG, letterSpacing: "-.01em" });
export const menuGo = style({ gridRow: "3", color: FG, fontWeight: "500" });
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
  fontSize: vars.textTitle, fontWeight: "500", whiteSpace: "nowrap", transition: `transform .2s ${vars.easeOut}, box-shadow .2s, background .2s`,
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
    "&[data-size=\"large\"]": { height: "50px", padding: "0 28px", fontSize: vars.textTitle },
  },
});
export const actions = style({ display: "flex", gap: "12px", justifyContent: "center", flexWrap: "wrap" });

/** A button's words and what they turn into under them, in a window a line high: rolled up a line on hover. */
export const roll = style({ display: "grid", justifyItems: "center", overflow: "hidden", height: "1.3em", lineHeight: "1.3em" });
globalStyle(`${roll} > span`, { transition: `transform .45s cubic-bezier(.7, 0, .2, 1)` });
globalStyle(`${button}:hover ${roll} > span`, { transform: "translateY(-100%)" });
globalStyle(`${button}:hover ${roll} > span + span`, { transitionDelay: ".03s" });

// ---- Hero ----

export const hero = style({ padding: "88px 0 72px", "@media": { [NARROW]: { padding: "48px 0 40px" } } });
/** What it is on the left, the picture of it on the right; one under the other on a narrow screen. */
export const heroRow = style({
  display: "grid", gridTemplateColumns: "minmax(0, 1fr) minmax(0, 1.08fr)", gap: "56px", alignItems: "center",
  "@media": { [NARROW]: { gridTemplateColumns: "minmax(0, 1fr)", gap: "40px" } },
});
export const heroWords = style({ animation: `${fadeUp} .8s .05s ${vars.easeOut} both`, "@media": { [STILL]: { animation: "none" } } });
export const title = style({ margin: "0", fontSize: "clamp(44px, 5.4vw, 80px)", lineHeight: "1.08", letterSpacing: "-.02em", fontWeight: "700", color: "var(--s-title)" });
export const lede = style({ maxWidth: "30em", margin: "24px 0 0", fontSize: "clamp(17px, 1.6vw, 20px)", lineHeight: "1.65", color: "var(--s-muted)", textWrap: "balance", wordBreak: "keep-all" });
export const heroActions = style({ display: "flex", flexWrap: "wrap", alignItems: "center", gap: "12px 20px", marginTop: "36px" });
export const heroNote = style({ fontSize: vars.textUi, color: DIM });

export const pictureBox = style({ animation: `${fadeUp} .8s .18s ${vars.easeOut} both`, "@media": { [STILL]: { animation: "none" } } });
/** A dot going along a line now and then: none where less motion is asked for. */
export const pulse = style({ fill: ORANGE, "@media": { [STILL]: { display: "none" } } });
/** Online: the green of a machine that is there. */
export const onlineSpot = style({ fill: vars.online });

// ---- The app ----

export const stageSection = style({ padding: "24px 0 0" });
/** Where the demo shows the phone's app (under 700 wide, the box being the page's width less its margins): its box
 *  has a phone's large corners, around its composer's: the capsule's 26px plus the 10px it sits in from the box. */
const PHONE_BOX = "screen and (max-width: 747px)";
/** The demo's frame: a hairline round it and a soft shadow under it. */
export const edge = style({
  position: "relative", padding: "1px", borderRadius: "20px",
  background: ink(12), boxShadow: "0 40px 90px -40px rgba(0, 0, 0, .35)",
  "@media": { [NARROW]: { borderRadius: "14px" }, [PHONE_BOX]: { borderRadius: "37px" }, [STILL]: { animation: "none" } },
});
/** The demo's box (demo/): the app in it, at its size. Its corners cut by a clip, not a rounded overflow: under one,
 *  Chromium ignored the phone bar's glass's clip-path (a frosted layer, mobile/Bar.tsx) set while it was out of view,
 *  and drew the bar as a plain rectangle. */
/** Each idea of the page (Site.tsx): the first unless the root says the second. */
export const idea = style({ selectors: {
  ':root[data-v="2"] &[data-idea="1"]': { display: "none" },
  ':root:not([data-v="2"]) &[data-idea="2"]': { display: "none" },
} });
export const demo = style({
  position: "relative", height: "720px", overflow: "hidden", clipPath: "inset(0 round 19px)", background: vars.canvas,
  "@media": { [NARROW]: { clipPath: "inset(0 round 13px)", height: "620px" }, [PHONE_BOX]: { clipPath: "inset(0 round 36px)" } },
});
/** The demo's opening frame, built into the page: the phone's app where the box is narrow (as the demo picks: under
 *  700 wide, the box being the page's width less its margins), the desktop's elsewhere. */
export const frameWide = style({ height: "100%", "@media": { [PHONE_BOX]: { display: "none" } } });
export const framePhone = style({ height: "100%", display: "none", "@media": { [PHONE_BOX]: { display: "block" } } });
export const caption = style({ margin: "16px 0 0", textAlign: "center", fontSize: vars.textUi, color: DIM });

// ---- Sections ----

export const section = style({ padding: "120px 0 0", "@media": { [NARROW]: { padding: "80px 0 0" } } });
export const headingTitle = style({ margin: "0", fontSize: "clamp(30px, 3.6vw, 44px)", lineHeight: "1.2", letterSpacing: "-.02em", fontWeight: "700", color: "var(--s-title)", textWrap: "balance" });
/** Words that wrap only as a whole. */
export const phrase = style({ display: "inline-block" });
export const headingLede = style({ margin: "14px 0 0", fontSize: "clamp(16px, 1.5vw, 18px)", lineHeight: "1.65", color: "var(--s-muted)", textWrap: "balance" });

// What it connects: three, side by side under a rule each; one under another on a narrow screen.
export const links = style({
  display: "grid", gridTemplateColumns: "repeat(3, minmax(0, 1fr))", gap: "48px", margin: "56px 0 0", padding: "0", listStyle: "none",
  "@media": { [NARROW]: { gridTemplateColumns: "minmax(0, 1fr)", gap: "40px", marginTop: "40px" } },
});
export const link = style({ paddingTop: "24px", borderTop: `1px solid ${ink(14)}` });
export const linkNumber = style({ display: "block", fontFamily: vars.fontMono, fontSize: vars.textUi, color: ORANGE });
export const linkTitle = style({ margin: "14px 0 0", fontSize: vars.textHeading, fontWeight: "600", letterSpacing: "-.01em", color: FG });
export const linkText = style({ margin: "10px 0 0", fontSize: vars.textTitle, lineHeight: "1.7", color: "var(--s-muted)" });
export const parts = style({ display: "flex", flexWrap: "wrap", gap: "8px", margin: "18px 0 0", padding: "0", listStyle: "none" });
globalStyle(`${parts} > li`, { padding: "4px 12px", borderRadius: "999px", background: ink(5), color: "var(--s-muted)", fontSize: vars.textUi });

// What it promises: two panels.
export const promises = style({ display: "grid", gridTemplateColumns: "repeat(2, minmax(0, 1fr))", gap: "20px", "@media": { [NARROW]: { gridTemplateColumns: "minmax(0, 1fr)" } } });
export const promise = style({ padding: "40px", borderRadius: vars.rCard, background: CARD, boxShadow: `inset 0 0 0 1px ${LINE}`, "@media": { [NARROW]: { padding: "28px" } } });
export const promiseTitle = style({ margin: "0", fontSize: "clamp(24px, 2.6vw, 32px)", lineHeight: "1.25", letterSpacing: "-.02em", fontWeight: "700", color: "var(--s-title)" });
export const promiseText = style({ margin: "12px 0 0", fontSize: vars.textTitle, lineHeight: "1.7", color: "var(--s-muted)" });

// Installing: what to do on the left, the command on the right.
export const install = style({
  display: "grid", gridTemplateColumns: "minmax(0, .7fr) minmax(0, 1.3fr)", gap: "48px", alignItems: "center", paddingBottom: "120px",
  "@media": { [NARROW]: { gridTemplateColumns: "minmax(0, 1fr)", gap: "28px", paddingBottom: "80px" } },
});
/** The command, in a terminal's colours in either theme. */
export const terminal = style({
  borderRadius: vars.rCard, overflow: "hidden", background: "#111114", color: "#E9E9EA",
  boxShadow: `0 30px 70px -40px rgba(0, 0, 0, .5), inset 0 0 0 1px ${LINE}`,
  font: `14px/1.8 ${vars.fontMono}`, "@media": { [NARROW]: { fontSize: vars.textMeta } },
});
export const terminalBody = style({ padding: "26px 28px", overflowX: "auto" });
/** The command's line: the prompt and the command kept together, scrolled sideways where it is too long. */
export const command = style({ display: "block", whiteSpace: "nowrap" });
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

// ---- The first idea: the same machine (SameMachine.tsx) ----

export const sameHero = style({ padding: "96px 0 32px", textAlign: "center", "@media": { [NARROW]: { padding: "48px 0 16px" } } });
export const sameTitle = style({
  margin: "0", fontSize: "clamp(40px, 5.6vw, 76px)", lineHeight: "1.12", letterSpacing: "-.02em", fontWeight: "700", color: "var(--s-title)",
  animation: `${fadeUp} .8s .05s ${vars.easeOut} both`, "@media": { [STILL]: { animation: "none" } },
});
export const sameLede = style({ maxWidth: "36em", margin: "22px auto 0", fontSize: "clamp(17px, 1.6vw, 20px)", lineHeight: "1.65", color: "var(--s-muted)", textWrap: "balance", wordBreak: "keep-all" });
export const sameActions = style({ marginTop: "32px" });

/** The scene: as tall as its places, the stage held in view while it is scrolled through. */
export const scene = style({ position: "relative" });
export const sceneStick = style({
  position: "sticky", top: "64px", height: "calc(100vh - 64px)", display: "flex", flexDirection: "column", padding: "16px 0 28px",
});
/** What the step in view says, above the room: the steps' words one under another in a window one step high, moved
 *  up as the scene is scrolled (--at, the step it is at: OneComputer.tsx), each coming up as the one before goes. */
const SAY = { wide: 64, narrow: 112 };
export const stepWords = style({
  height: `${SAY.wide}px`, overflow: "hidden", padding: "0 24px", marginTop: "8px",
  "@media": { [NARROW]: { height: `${SAY.narrow}px` } },
});
export const stepTrack = style({
  transform: `translateY(calc(var(--at, 0) * -${SAY.wide}px))`,
  "@media": { [NARROW]: { transform: `translateY(calc(var(--at, 0) * -${SAY.narrow}px))` } },
});
export const stepSay = style({
  height: `${SAY.wide}px`, display: "grid", alignContent: "center", justifyItems: "center", gap: "4px", textAlign: "center",
  "@media": { [NARROW]: { height: `${SAY.narrow}px` } },
});
globalStyle(`${stepSay} > b`, { fontSize: vars.textHeading, fontWeight: 700, color: FG });
globalStyle(`${stepSay} > span`, { fontSize: vars.textTitle, color: "var(--s-muted)" });
/** Where the devices and the window are placed (OneComputer.tsx). */
export const oneRoom = style({ position: "relative", flex: "1", minHeight: "0", marginTop: "12px" });
export const oneWires = style({ position: "absolute", inset: "0", width: "100%", height: "100%", overflow: "visible", pointerEvents: "none" });
const flowing = keyframes({ to: { strokeDashoffset: -26 } });
globalStyle(`${oneWires} path`, {
  fill: "none", stroke: `color-mix(in srgb, ${ORANGE} 60%, transparent)`, strokeWidth: 1.5, strokeDasharray: "5 8",
  animation: `${flowing} 1.4s linear infinite`, "@media": { [STILL]: { animation: "none" } },
});
/** The computer's window (OneComputer.tsx): placed and stepped back by script; its shadow follows what of it shows. */
/** The window under its shadow (of what of it shows: the devices flying, then the window growing out of them). */
export const oneLift = style({ position: "absolute", inset: "0", zIndex: 1, pointerEvents: "none", filter: "drop-shadow(0 30px 40px rgba(0, 0, 0, .18))" });
export const oneWindow = style({ position: "absolute", transformOrigin: "0 0", pointerEvents: "auto" });
/** What of the window shows: its clip, set by script (the rows, widening to the window). */
export const oneScreen = style({ position: "absolute", inset: "0", background: vars.canvas });
/** The app in it: as large as the window. */
export const oneDemo = style({});
globalStyle(`${oneScreen} > ${oneDemo}`, { height: "100%", clipPath: "none", "@media": { [NARROW]: { height: "100%", clipPath: "none" } } });
/** The phone, a device among the others (a wide screen's; on a narrow one the window is the phone). */
export const onePhone = style({
  // Its shadow a box shadow round its corners, not a filter: under a filter the phone bar's frosted glass loses its
  // shape (Chromium draws it as a plain rectangle).
  position: "absolute", top: "0", left: "0", zIndex: 3, transformOrigin: "0 0", borderRadius: "44px", boxShadow: "0 24px 36px rgba(0, 0, 0, .22)", // own corner: a phone's
  "@media": { [NARROW]: { display: "none" } },
});
/** Its screen: the phone's app, a page of its own (site/phone.html); its corners cut by a clip. */
export const onePhoneScreen = style({ display: "block", border: "0", clipPath: "inset(0 round 44px)", background: vars.canvas });

// ---- The second idea: the distance (Distance.tsx) ----

export const map = style({ display: "block", width: "100%", height: "auto", overflow: "visible" });
export const mapGrid = style({ stroke: ink(7), strokeWidth: 1 });
export const mapDegree = style({ fill: "var(--s-faint)", fontFamily: vars.fontMono, fontSize: vars.textCaption, "@media": { [NARROW]: { fontSize: vars.textUi } } });
export const mapCity = style({});
globalStyle(`${mapCity} > circle`, { fill: ink(28) });
globalStyle(`${mapCity} > text`, { fill: DIM, fontSize: vars.textUi, "@media": { [NARROW]: { fontSize: vars.textTitle } } });
const flow = keyframes({ to: { strokeDashoffset: -28 } });
export const mapRoute = style({
  fill: "none", stroke: ORANGE, strokeWidth: 2, strokeDasharray: "6 8", animation: `${flow} 1.2s linear infinite`,
  "@media": { [STILL]: { animation: "none" } },
});
export const mapLink = style({});
globalStyle(`${mapLink} > rect`, { fill: "var(--s-node)", stroke: ORANGE, strokeWidth: 1.5 });
export const mapLinkMain = style({ fill: FG, fontSize: vars.textBody, fontWeight: 600, "@media": { [NARROW]: { fontSize: vars.textTitle } } });
export const mapLinkSub = style({ fill: DIM, fontFamily: vars.fontMono, fontSize: vars.textMeta, "@media": { [NARROW]: { fontSize: vars.textUi } } });
const breathe = keyframes({ "0%": { opacity: 0.5, transform: "scale(.6)" }, "100%": { opacity: 0, transform: "scale(1.6)" } });
export const mapHalo = style({
  fill: `color-mix(in srgb, ${ORANGE} 35%, transparent)`, transformBox: "fill-box", transformOrigin: "center",
  animation: `${breathe} 2.4s ease-out infinite`, "@media": { [STILL]: { animation: "none", opacity: 0.3 } },
});
export const mapSpot = style({ fill: ORANGE, stroke: "var(--s-bg)", strokeWidth: 3 });
export const mapCard = style({ filter: "drop-shadow(0 12px 24px rgba(0, 0, 0, .12))" });
globalStyle(`${mapCard} > rect`, { fill: "var(--s-node)", stroke: ink(12), strokeWidth: 1 });
export const mapCardMain = style({ fill: FG, fontSize: vars.textTitle, fontWeight: 600, "@media": { [NARROW]: { fontSize: vars.textHeading } } });
export const mapCardSub = style({ fill: DIM, fontSize: vars.textUi, "@media": { [NARROW]: { fontSize: vars.textTitle } } });
export const demoAfterHeading = style({ marginTop: "40px" });

// ---- Footer ----

export const footer = style({ padding: "32px 0 48px", color: DIM, fontSize: vars.textBody, borderTop: `1px solid ${LINE}` });
export const footerRow = style({ display: "flex", flexWrap: "wrap", alignItems: "center", gap: "12px 24px" });
export const footerFirst = style({ marginRight: "auto" });
