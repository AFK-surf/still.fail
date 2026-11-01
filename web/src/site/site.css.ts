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
  // No line under it: its frosted glass sets it apart from what scrolls under it.
  position: "sticky", top: "0", zIndex: "10",
  background: `color-mix(in srgb, ${BG} 72%, transparent)`, backdropFilter: "blur(20px) saturate(1.4)",
});
// On a phone its links sit closer, so that the name, 下载 (Download), GitHub's mark and the theme switch fit on the
// narrowest (360 wide), none of them broken over two lines.
export const navRow = style({ display: "flex", alignItems: "center", height: "64px", gap: "28px", whiteSpace: "nowrap", "@media": { [NARROW]: { gap: "12px" } } });
/** The name in the bar, as the wordmark draws it (web/public/wordmark.svg): Inter Bold, its dot still.fail's orange and
 *  drawn closer to the words it joins. */
export const brand = style({ display: "flex", alignItems: "center", fontSize: vars.textHeading, fontWeight: "700", letterSpacing: "-.02em", color: FG });
export const brandDot = style({ color: ORANGE, margin: "0 -.035em" });
/** The headline's full stop: still.fail's dot. */
export const titleDot = style({ color: ORANGE });
// The logo on the left, the rest of the bar on the right.
globalStyle(`${navRow} > :first-child`, { marginRight: "auto" });
export const navLink = style({ transition: "color .2s", selectors: { "&:hover": { color: FG } } });
globalStyle(`${navRow} ${navLink}`, { color: "var(--s-muted)", fontSize: vars.textTitle });
/** A link in the bar that is a mark (GitHub's): as wide as the mark, as tall as the theme switch beside it. */
export const navMark = style({ display: "grid", placeItems: "center", width: "24px", height: "36px" });

// ---- Downloads (Site.tsx Downloads) ----

// Gone to from the bar's 下载 (Download): its title clear of the bar.
globalStyle("#download", { scrollMarginTop: "64px" });
/** Its title with every app under it, and the button for this device's beside it (under it on a narrow screen). */
export const downloadBand = style({
  display: "flex", alignItems: "center", justifyContent: "space-between", gap: "24px",
  "@media": { [NARROW]: { flexDirection: "column", alignItems: "flex-start", gap: "24px" } },
});
/** Every app, a line of quiet links. */
export const downloadAll = style({
  display: "flex", flexWrap: "wrap", alignItems: "center", gap: "8px 20px", margin: "12px 0 0", fontSize: vars.textTitle, color: "var(--s-muted)",
  // (on a phone closer, all of it on one line on the narrowest)
  "@media": { [NARROW]: { gap: "8px 14px" } },
});
globalStyle(`${downloadAll} > a`, { color: FG, transition: "color .2s" });
globalStyle(`${downloadAll} > a:hover`, { color: "var(--s-muted)" });
export const downloadMain = style({ display: "flex", alignItems: "center", gap: "24px" });
/** Each device's button: the one for the device the page is on shows (data-platform on the root; a computer not a
 *  Mac's is taken for Windows', a device none is made for opens the web app). */
export const downloadFor = style({ display: "none" });
const MAIN_FOR = { mac: ["mac"], windows: ["windows", "desktop"], android: ["android"] } as const;
for (const [key, platforms] of Object.entries(MAIN_FOR)) {
  globalStyle(`${platforms.map((p) => `:root[data-platform="${p}"] ${downloadFor}[data-for="${key}"]`).join(", ")}`, { display: "flex" });
}
globalStyle(`:root:not(:is([data-platform="mac"], [data-platform="windows"], [data-platform="desktop"], [data-platform="android"])) ${downloadFor}[data-for="other"]`, { display: "flex" });
/** The code to scan for the Android app, with its words: on a computer only (a phone has its link). */
export const scanOnComputer = style({
  display: "flex", alignItems: "center", gap: "12px", fontSize: vars.textUi, color: "var(--s-muted)",
  selectors: { ':root:is([data-platform="android"], [data-platform="ios"]) &': { display: "none" } },
});
/** The code itself stays dark on white in either theme, with the quiet margin a scanner wants. */
export const scanCode = style({ display: "block", flex: "none", width: "64px", height: "64px", padding: "4px", borderRadius: "10px", background: "#fff", imageRendering: "pixelated" }); // own corner: a white label round the code, no panel

/** The theme switch (ThemeSwitch.tsx): three small buttons in a pill. */
export const themeSwitch = style({ display: "flex", gap: "2px", padding: "3px", borderRadius: "999px", background: CARD, boxShadow: `inset 0 0 0 1px ${LINE}` });
export const themeChoice = style({
  display: "grid", placeItems: "center", width: "30px", height: "30px", padding: "0", border: "0", borderRadius: "999px",
  background: "transparent", color: DIM, cursor: "pointer", transition: "color .2s, background .2s",
  selectors: { "&:hover": { color: FG }, "&[aria-checked=\"true\"]": { background: ink(10), color: FG } },
});
// On a phone the bar keeps the name and the theme; the hero has the buttons.
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
export const heroNote = style({ fontSize: vars.textUi, color: "var(--s-muted)" });

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
/** The demo's opening frame, built into the page (Site.tsx frameHtml): the phone's app where its box is narrow, the
 *  desktop's elsewhere, by the box's own width as the demo picks (under 700 wide: demo/mount.tsx PHONE_BELOW). */
export const frame = style({ height: "100%", containerType: "inline-size" });
const NARROW_BOX = "(width < 700px)";
export const frameWide = style({ height: "100%", "@container": { [NARROW_BOX]: { display: "none" } } });
export const framePhone = style({ height: "100%", display: "none", "@container": { [NARROW_BOX]: { display: "block" } } });
export const caption = style({ margin: "16px 0 0", textAlign: "center", fontSize: vars.textUi, color: "var(--s-muted)" });

// ---- Sections ----

export const section = style({ padding: "120px 0 0", "@media": { [NARROW]: { padding: "80px 0 0" } } });
export const headingTitle = style({ margin: "0", fontSize: "clamp(30px, 3.6vw, 44px)", lineHeight: "1.2", letterSpacing: "-.02em", fontWeight: "700", color: "var(--s-title)", textWrap: "balance" });
/** Words that wrap only as a whole. */
export const phrase = style({ display: "inline-block" });
export const headingLede = style({ margin: "14px 0 0", fontSize: "clamp(16px, 1.5vw, 18px)", lineHeight: "1.65", color: "var(--s-muted)", textWrap: "balance" });

// What it connects: three, side by side, set apart by the room between them; one under another on a narrow screen.
export const links = style({
  display: "grid", gridTemplateColumns: "repeat(3, minmax(0, 1fr))", gap: "48px", margin: "56px 0 0", padding: "0", listStyle: "none",
  "@media": { [NARROW]: { gridTemplateColumns: "minmax(0, 1fr)", gap: "40px", marginTop: "40px" } },
});
/** What it is for (OneComputer.tsx): those shown on a phone three across, each its phone over its words, what is not
 *  here yet a line under them; one under another on a narrow screen. */
export const scenes = style({
  gridTemplateColumns: "repeat(3, minmax(0, 1fr))", gap: "56px 40px",
  "@media": { [NARROW]: { gridTemplateColumns: "minmax(0, 1fr)", gap: "56px" } },
});
globalStyle(`${scenes} > [data-soon]`, { gridColumn: "1 / -1" });
export const link = style({});
/** Its number, quiet: the orange is for where things connect. */
export const linkNumber = style({ display: "block", fontFamily: vars.fontMono, fontSize: vars.textUi, color: "var(--s-muted)" });
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
  display: "grid", gridTemplateColumns: "minmax(0, .7fr) minmax(0, 1.3fr)", gap: "48px", alignItems: "center",
  "@media": { [NARROW]: { gridTemplateColumns: "minmax(0, 1fr)", gap: "28px" } },
});
// What it works with (Site.tsx Works): each row's quiet name over its marks, a pill each.
export const works = style({ display: "grid", gap: "14px", margin: "40px 0 0", "@media": { [NARROW]: { marginTop: "28px" } } });
globalStyle(`${works} > ul + span`, { marginTop: "18px" });
export const worksRow = style({ fontSize: vars.textUi, color: "var(--s-muted)" });
export const marks = style({ display: "flex", flexWrap: "wrap", gap: "10px", "@media": { [NARROW]: { gap: "8px" } }, margin: "0", padding: "0", listStyle: "none" });
globalStyle(`${marks} > li`, {
  display: "flex", alignItems: "center", gap: "10px", padding: "10px 18px 10px 14px", borderRadius: "999px",
  background: CARD, boxShadow: `inset 0 0 0 1px ${LINE}`, color: FG, fontSize: vars.textTitle, lineHeight: "1.2",
  "@media": { [NARROW]: { gap: "8px", padding: "8px 14px 8px 12px", fontSize: vars.textBody } },
});
globalStyle(`${marks} svg`, { display: "block", flex: "none" });

// What a visitor asks first (Site.tsx Questions): the title on the left, the questions on the right (under it on a
// narrow screen), each a quiet card that opens to its answer; the page's foot under them.
export const questions = style({
  display: "grid", gridTemplateColumns: "minmax(0, .7fr) minmax(0, 1.3fr)", gap: "48px", alignItems: "start",
  "@media": { [NARROW]: { gridTemplateColumns: "minmax(0, 1fr)", gap: "28px" } },
});
export const questionList = style({ display: "grid", gap: "10px" });
export const question = style({ borderRadius: vars.rCard, background: CARD, boxShadow: `inset 0 0 0 1px ${LINE}` });
export const questionAsked = style({
  display: "flex", alignItems: "center", justifyContent: "space-between", gap: "16px", padding: "20px 24px", cursor: "pointer", listStyle: "none",
  fontSize: vars.textTitle, fontWeight: "600", color: FG, selectors: { "&::-webkit-details-marker": { display: "none" } },
});
export const questionOpen = style({ flex: "none", color: "var(--s-muted)", transition: `transform .2s ${vars.easeOut}` });
globalStyle(`${question}[open] ${questionOpen}`, { transform: "rotate(180deg)" });
export const questionAnswer = style({ margin: "0", padding: "0 24px 22px", fontSize: vars.textTitle, lineHeight: "1.7", color: "var(--s-muted)" });

// What the last release brought (Site.tsx Shipped): the title on the left, its number, day and counts on the right, its
// first new things under them.
export const shipped = style({
  display: "grid", gridTemplateColumns: "minmax(0, .7fr) minmax(0, 1.3fr)", gap: "48px", alignItems: "start",
  "@media": { [NARROW]: { gridTemplateColumns: "minmax(0, 1fr)", gap: "20px" } },
});
export const shippedWhen = style({ display: "flex", flexWrap: "wrap", gap: "4px 20px", margin: "0", fontSize: vars.textTitle, color: "var(--s-muted)", "@media": { "screen and (min-width: 861px)": { paddingTop: "14px" } } });
globalStyle(`${shippedWhen} > :first-child`, { color: FG, fontFamily: vars.fontMono });
export const shippedLines = style({ display: "grid", gap: "10px", margin: "20px 0 0", padding: "0 0 0 20px", fontSize: vars.textTitle, lineHeight: "1.6", color: FG });
globalStyle(`${shippedLines} > li::marker`, { color: "var(--s-muted)" });

// The page's last word (Site.tsx Closing): its title again, the ways in under it, in the middle; the page's foot under.
export const closing = style({ display: "grid", justifyItems: "center", gap: "32px", textAlign: "center", paddingBottom: "120px", "@media": { [NARROW]: { gap: "24px", paddingBottom: "80px" } } });
export const closingTitle = style({ margin: "0", fontSize: "clamp(40px, 5.6vw, 76px)", lineHeight: "1.12", letterSpacing: "-.02em", fontWeight: "700", color: "var(--s-title)" });
export const closingActions = style({ display: "flex", flexWrap: "wrap", justifyContent: "center", gap: "12px" });

/** The command, in a terminal's colours in either theme. */
export const terminal = style({
  borderRadius: vars.rCard, overflow: "hidden", background: "#111114", color: "#E9E9EA",
  boxShadow: `0 30px 70px -40px rgba(0, 0, 0, .5), inset 0 0 0 1px ${LINE}`,
  font: `14px/1.8 ${vars.fontMono}`, "@media": { [NARROW]: { fontSize: vars.textMeta } },
  // Its lines go by where it is on the screen (typed, output), named here: their own view() would be inside it, which
  // scrolls sideways (its body; its corners' clip too), and never moves.
  viewTimeline: "--terminal",
});
export const terminalBody = style({ padding: "26px 28px", overflowX: "auto" });
/** The command's line: the prompt and the command kept together, scrolled sideways where it is too long. */
export const command = style({ display: "block", whiteSpace: "nowrap" });
const type = keyframes({ from: { width: "0" }, to: { width: "var(--chars)" } });
const blink = keyframes({ "50%": { borderColor: "transparent" } });
export const typed = style({
  display: "inline-block", verticalAlign: "bottom", overflow: "hidden", whiteSpace: "nowrap", borderRight: `2px solid ${ORANGE}`,
  // Typed as the terminal comes up the screen (where there are no scroll-driven animations, typed at once), done a
  // little after it is all in view: the page ends not far under it, so how far it can go up the screen is that much
  // (its install section's foot and the footer: 200px and more), not a share of the screen's height.
  animation: `${type} linear both, ${blink} .9s step-end infinite`, animationTimingFunction: "steps(var(--steps)), step-end",
  animationTimeline: "--terminal, auto", animationRange: "entry 60% contain 50px, normal",
  "@media": { [STILL]: { animation: "none", width: "var(--chars)" } },
});
const appear = keyframes({ from: { opacity: 0 }, to: { opacity: 1 } });
export const output = style({
  display: "block", color: DIM, animation: `${appear} linear both`, animationTimeline: "--terminal",
  selectors: {
    "&[data-ok]": { color: "#7FD4A1" },
    "&[data-at=\"1\"]": { animationRange: "contain 70px contain 90px" },
    "&[data-at=\"2\"]": { animationRange: "contain 100px contain 120px" },
    "&[data-at=\"3\"]": { animationRange: "contain 130px contain 150px" },
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
export const sameActions = style({ marginTop: "32px" });

/** The scene: as tall as its places, the stage held in view while it is scrolled through. */
export const scene = style({ position: "relative" });
export const sceneStick = style({
  position: "sticky", top: "64px", height: "calc(100vh - 64px)", display: "flex", flexDirection: "column", padding: "16px 0 28px",
});
/** Where the devices and the window are placed (OneComputer.tsx): by its script, so none of them is drawn before it
 *  has placed them (data-drawn), at the scene's first frame. Unseen by its opacity, not its visibility: the rows read
 *  for the air till then are copied with every style the app gives them, and a visibility would be inherited into them. */
export const oneRoom = style({ position: "relative", flex: "1", minHeight: "0", marginTop: "12px", selectors: { "&:not([data-drawn])": { opacity: 0 } } });
export const oneWires = style({ position: "absolute", inset: "0", pointerEvents: "none" });
// Each line is clipped to its length by scaling this box. Its child cancels that scale, so the moving dashes keep
// their size as the endpoints move. Both the moving pattern and the clip can then be composited without repainting.
export const oneWire = style({
  position: "absolute", left: "0", top: "0", height: "1.5px", overflow: "hidden", transformOrigin: "0 50%",
  transform: "scaleX(0)", willChange: "transform",
  "@media": { [NARROW]: { selectors: { "&:nth-child(n+7)": { display: "none" } } } },
});
export const oneWireScale = style({ width: "100%", height: "100%", transformOrigin: "0 50%", willChange: "transform" });
const flowing = keyframes({ to: { transform: "translateX(-26px)" } });
export const oneWireDashes = style({
  width: "calc(100% + 26px)", height: "100%",
  background: `repeating-linear-gradient(90deg, color-mix(in srgb, ${ORANGE} 60%, transparent) 0 5px, transparent 5px 13px)`,
  animation: `${flowing} 1.4s linear infinite`, willChange: "transform", "@media": { [STILL]: { animation: "none" } },
});
globalStyle(`${oneWires}[data-offscreen] ${oneWireDashes}`, { animationPlayState: "paused" });
/** The computer's window (OneComputer.tsx): placed and stepped back by script; its shadow follows what of it shows. */
/** The window under its shadow (of what of it shows: the devices flying, then the window growing out of them). */
export const oneLift = style({ position: "absolute", inset: "0", zIndex: 1, pointerEvents: "none", filter: "drop-shadow(0 30px 40px rgba(0, 0, 0, .18))" });
export const oneWindow = style({ position: "absolute", transformOrigin: "0 0", pointerEvents: "auto" });
/** The screen: the app, cut to the screen's corners, round within its shell's (as far in as the shell's edge is wide).
 *  All of the app is in it; what flies in is over it until it lands (oneAir). */
export const oneScreen = style({
  position: "absolute", inset: "0", background: vars.canvas, clipPath: "inset(0 round 20px)", // own corner: a laptop's screen
  "@media": { [NARROW]: { clipPath: "inset(0 round 36px)" } }, // own corner: a phone's screen
});
/** Over the devices: the rows while they fly, each the row as the app draws it, until it lands in its place. */
export const oneAir = style({ position: "absolute", inset: "0", zIndex: 4, pointerEvents: "none" });
/** The shells (OneComputer.tsx SHELL): a laptop's edge round its screen and its base under it; on a narrow screen,
 *  where the window is a phone, a phone's edge. */
const BEZEL = "#060607";
/** A metal edge round a device's black face: dark where it meets the glass, light on its face, dark at its rim. */
const METAL = "0 0 0 1.5px #2C2C2F, 0 0 0 3.5px #B8B8BE, 0 0 0 4.5px #6E6E74";
/** Metal, lit from above: buttons, a laptop's base. */
const ALU = "linear-gradient(180deg, #F4F4F6 0%, #DCDCE0 38%, #B7B7BD 78%, #8C8C92 100%)";
export const oneEdge = style({
  // A laptop's lid round its screen, its camera at the top of its frame.
  position: "absolute", inset: "-14px", borderRadius: "34px", background: BEZEL, // own corner: a laptop's
  boxShadow: `${METAL}, inset 0 0 0 1px rgba(255, 255, 255, .06)`,
  selectors: {
    "&::after": {
      content: "\"\"", position: "absolute", top: "4px", left: "calc(50% - 3px)", width: "6px", height: "6px", borderRadius: "50%",
      background: "radial-gradient(circle at 40% 35%, #3A4A5E, #0B0F14 70%)", boxShadow: "0 0 0 1px #1A1A1C",
    },
  },
  // A phone's face round its screen (a narrow screen's window).
  "@media": { [NARROW]: { inset: "-12px", borderRadius: "48px", selectors: { "&::after": { display: "none" } } } }, // own corner: a phone's
});
/** A laptop's base: metal, its hinge under the lid, the scoop in its front edge to lift the lid by. */
export const oneBase = style({
  position: "absolute", left: "-84px", right: "-84px", top: "calc(100% + 18px)", height: "14px", background: ALU,
  borderRadius: "3px 3px 18px 18px / 3px 3px 12px 12px", boxShadow: "inset 0 1px 0 #FFFFFF, 0 2px 3px rgba(0, 0, 0, .18)", // own corner: a laptop's base
  selectors: {
    // The hinge, dark, under the lid.
    "&::before": { content: "\"\"", position: "absolute", left: "12%", right: "12%", top: "-4px", height: "4px", background: "linear-gradient(180deg, #1E1E21, #4A4A4F)" },
    // The scoop.
    "&::after": {
      content: "\"\"", position: "absolute", left: "calc(50% - 70px)", top: "0", width: "140px", height: "6px", borderRadius: "0 0 10px 10px", // own corner: the scoop
      background: "linear-gradient(180deg, #9C9CA2, #C9C9CE)",
    },
  },
  "@media": { [NARROW]: { display: "none" } },
});
/** A phone's camera island at the top of its screen; `oneIslandInWindow` the one of a narrow screen's window. */
const island = { position: "absolute", left: "calc(50% - 56px)", width: "112px", height: "32px", borderRadius: "16px", background: "#000", zIndex: 2, pointerEvents: "none" } as const; // own corner: an island
export const oneIsland = style({ ...island, top: "23px" });
export const oneIslandInWindow = style({ ...island, top: "11px", display: "none", "@media": { [NARROW]: { display: "block" } } });
/** A phone's buttons on its metal edge: the volume keys on the left, the power key on the right. `oneKeysInWindow` the
 *  ones of a narrow screen's window (its edge outside its screen). */
const keys = (out: number) => ({
  position: "absolute", inset: `0 -${out}px`, pointerEvents: "none",
  selectors: {
    "&::before": { content: "\"\"", position: "absolute", left: "0", top: "170px", width: "4px", height: "128px", borderRadius: "2px", background: `linear-gradient(180deg, transparent 0 0, #9A9AA0 0 46%, transparent 46% 54%, #9A9AA0 54%)` }, // own corner: a key
    "&::after": { content: "\"\"", position: "absolute", right: "0", top: "220px", width: "4px", height: "92px", borderRadius: "2px", background: "linear-gradient(90deg, #8C8C92, #D2D2D7)" }, // own corner: a key
  },
} as const);
export const oneKeys = style(keys(8));
export const oneKeysInWindow = style({ ...keys(20), display: "none", "@media": { [NARROW]: { display: "block" } } });
/** The app in it: as large as the window. */
export const oneDemo = style({});
globalStyle(`${oneScreen} > ${oneDemo}`, { height: "100%", clipPath: "none", "@media": { [NARROW]: { height: "100%", clipPath: "none" } } });
/** The phone, a device among the others (a wide screen's; on a narrow one the window is the phone). */
export const onePhone = style({
  // Its shadow a box shadow round its corners, not a filter: under a filter the phone bar's frosted glass loses its
  // shape (Chromium draws it as a plain rectangle).
  position: "absolute", top: "0", left: "0", zIndex: 3, transformOrigin: "0 0", boxSizing: "border-box", borderRadius: "56px", background: BEZEL, // own corner: a phone's
  boxShadow: `${METAL}, inset 0 0 0 1px rgba(255, 255, 255, .06), 0 30px 50px -12px rgba(0, 0, 0, .35)`,
  "@media": { [NARROW]: { display: "none" } },
});
/** Its screen: the phone's app, a page of its own (site/phone.html); its corners cut by a clip. */
export const onePhoneScreen = style({ display: "block", border: "0", clipPath: "inset(0 round 44px)", background: vars.canvas });
/** A phone showing one: its shell drawn at a phone's size (onePhone's) and made smaller to fit, in a box as large as
 *  it is drawn. */
const FEATURE = { w: 390 + 24, h: 844 + 24, k: 0.72 };
export const featurePhone = style({
  position: "relative", width: `${FEATURE.w * FEATURE.k}px`, height: `${FEATURE.h * FEATURE.k}px`, margin: "0 0 32px",
  "@media": { [NARROW]: { margin: "0 auto 28px" } },
});
export const featureShell = style({
  position: "absolute", top: "0", left: "0", width: `${FEATURE.w}px`, height: `${FEATURE.h}px`, padding: "12px", boxSizing: "border-box",
  transform: `scale(${FEATURE.k})`, transformOrigin: "0 0", borderRadius: "56px", background: BEZEL, // own corner: a phone's
  boxShadow: `${METAL}, inset 0 0 0 1px rgba(255, 255, 255, .06), 0 30px 50px -12px rgba(0, 0, 0, .3)`,
});
globalStyle(`${featureShell} iframe`, { pointerEvents: "none" });

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

export const footer = style({ padding: "32px 0 48px", color: DIM, fontSize: vars.textBody });
export const footerRow = style({ display: "flex", flexWrap: "wrap", alignItems: "center", gap: "12px 24px" });
export const footerFirst = style({ marginRight: "auto" });
