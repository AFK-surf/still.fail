// The bottom bar (Bar.tsx): one frosted glass for the bar and the panel it grows into, the ball over the place in
// view, 令 in a notch cut into the bar's top. The places' icons are drawn over the ball (frosted, it would blur them).
import { globalStyle, keyframes, style, type StyleRule } from "@vanilla-extract/css";

/** Rules for the dark theme: chosen, or the device's while none is chosen (as styles/root.css.ts goes). */
const dark = (rules: StyleRule): StyleRule => ({
  selectors: { ":root[data-theme=\"dark\"] &": rules as never },
  "@media": { "(prefers-color-scheme: dark)": { selectors: { ":root:not([data-theme=\"light\"]) &": rules as never } } },
});

/**
 * Where it stands: over the foot of the top page, 22 in from the sides and up from the safe area (the ball, 6 past it,
 * as far from each).
 */
export const mBarHost = style({
  position: "absolute", left: "22px", right: "22px", bottom: "calc(22px + var(--m-foot))", height: "56px", zIndex: 6,
  transition: "transform 500ms var(--m-ease), opacity 300ms",
  selectors: {
    // Over a page pushed over a place: gone down and out of the way, back as that page goes.
    "&[data-away]": { transform: "translateY(120px)", opacity: 0, pointerEvents: "none" },
  },
  "@media": {
    // Wider (an opened foldable, a phone on its side): as wide as a phone's, in the middle.
    "(min-width: 680px)": { left: "calc(50% - 195px)", right: "calc(50% - 195px)" },
  },
});

/** The bar and its panel (as tall as the panel, its foot the bar's); only what shows takes a touch. */
export const mBarWrap = style({
  position: "absolute", left: "0", right: "0", bottom: "0", transformOrigin: "50% 100%",
  touchAction: "none", userSelect: "none", WebkitTouchCallout: "none",
});

/** The scrim under the open panel: nothing to see, a tap on it closes the panel. */
export const mBarScrim = style({ position: "absolute", inset: "0", zIndex: 5 });

const rim = (a: number, b: number, c: number) =>
  `inset 0 0 0 .5px rgb(255 255 255 / ${a}), inset 1.5px 1.5px 1px -1px rgb(255 255 255 / ${b}), inset -1.5px -1.5px 1px -1px rgb(255 255 255 / ${c})`;

/** The frosted glass (the composer's: raised 72%, blur 20), its rim lit as vaso's. As tall as what shows of it. */
export const mBarGlass = style([{
  position: "absolute", left: "0", right: "0", bottom: "0", pointerEvents: "none",
  background: "color-mix(in srgb, var(--raised) 72%, transparent)",
  backdropFilter: "blur(20px) saturate(1.6)",
  boxShadow: rim(0.35, 0.8, 0.45),
}, dark({ boxShadow: rim(0.14, 0.3, 0.16) })]);

/** Its shadow: below and to the sides only, nothing above its top (where the notch is). */
export const mBarShadow = style({ position: "absolute", left: "0", top: "0", overflow: "visible", pointerEvents: "none" });
export const mBarShadowShape = style([{ fill: "rgb(0 0 0 / .16)", filter: "blur(6px)", transform: "translateY(4px)" }, dark({ fill: "rgb(0 0 0 / .45)" })]);

/** The bar's row of places, at the panel's foot. */
export const mBarRow = style({ position: "absolute", left: "0", right: "0", height: "56px", zIndex: 6 });

/** A place: its icon, 28, grey; the one in view (or under the finger) in ink. */
export const mBarPlace = style({
  position: "absolute", top: "4px", height: "48px", padding: "0", border: "0", background: "none", cursor: "pointer",
  display: "grid", placeItems: "center", color: "var(--m-muted)", transition: "color 300ms",
  selectors: { "&[data-on]": { color: "var(--m-ink)" } },
});
globalStyle(`${mBarPlace} > svg`, { width: "28px", height: "28px" });
/** What waits there: a dot at the icon's top right (stations in trouble, in red). */
export const mBarDot = style({
  position: "absolute", top: "calc(50% - 16px)", left: "calc(50% + 10px)", width: "7px", height: "7px", borderRadius: "50%",
  background: "var(--m-red)",
});

/** The other bars, one row each above the bar, in the panel. */
export const mBarRows = style({ position: "absolute", left: "0", right: "0", zIndex: 6 });
export const mBarSetRow = style({ position: "absolute", left: "0", right: "0", height: "56px", cursor: "pointer" });

/** The selection: a frosted ball of 68 under the icons, over 令. */
export const mBarBall = style([{
  position: "absolute", left: 0, top: 0, zIndex: 5, pointerEvents: "none", transition: "opacity 200ms",
  background: "color-mix(in srgb, #fff 42%, transparent)",
  backdropFilter: "blur(14px) saturate(1.6)",
  boxShadow: `${rim(0.5, 0.95, 0.55)}, 0 1px 8px rgb(55 53 45 / .2)`,
}, dark({ background: "color-mix(in srgb, #fff 12%, transparent)", boxShadow: `${rim(0.22, 0.45, 0.25)}, 0 1px 8px rgb(0 0 0 / .35)` })]);

/** 令: a disc of frosted glass in the accent, in the notch. */
export const mBarLing = style({
  position: "absolute", left: "50%", width: "56px", height: "56px", borderRadius: "50%", border: "0", padding: "0", zIndex: 4,
  display: "grid", placeItems: "center", color: "#fff", cursor: "pointer", transformOrigin: "50% 50%",
  background: "color-mix(in srgb, var(--m-accent) 86%, transparent)",
  backdropFilter: "blur(20px) saturate(1.6)",
  boxShadow: rim(0.4, 0.75, 0.4),
});

/** The action's icon in it: another page's, coming in, pops (the circle stays). */
const pop = keyframes({ from: { transform: "scale(.5)", opacity: 0 }, to: { transform: "none", opacity: 1 } });
export const mBarAction = style({ display: "grid", placeItems: "center", animation: `${pop} 220ms var(--ease-out)` });

/** The notch's edge, lit as the glass's own rim. */
export const mBarNotchRim = style([{
  position: "absolute", left: "0", top: "0", overflow: "visible", pointerEvents: "none", zIndex: 2,
  fill: "none", stroke: "rgb(255 255 255 / .7)", strokeWidth: 1,
}, dark({ stroke: "rgb(255 255 255 / .22)" })]);

/** Choosing another bar: the bars' rows sliding down inside the closing glass, cut by its outline. */
export const mBarStack = style({ position: "absolute", left: "0", right: "0", zIndex: 6, pointerEvents: "none" });
export const mBarStackIcon = style({
  position: "absolute", width: "48px", height: "48px", display: "grid", placeItems: "center", color: "var(--m-muted)",
  selectors: { "&[data-on]": { color: "var(--m-ink)" } },
});
globalStyle(`${mBarStackIcon} > svg`, { width: "28px", height: "28px" });

// The phone's buttons take their page's colour (root.css.ts, as strong as two classes and an element): the places'
// and 令's own, as strong and after it.
globalStyle(`${mBarWrap} button${mBarPlace}`, { color: "var(--m-muted)" });
globalStyle(`${mBarWrap} button${mBarPlace}[data-on]`, { color: "var(--m-ink)" });
globalStyle(`${mBarWrap} button${mBarLing}`, { color: "#fff" });
