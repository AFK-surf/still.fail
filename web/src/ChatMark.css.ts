import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";
import { busyRing } from "./styles/busyRing.ts";
import { spinKeyframes } from "./styles/keyframes.css.ts";

/**
 * A chat's state on its row's picture (ChatMark.tsx), at the corner, over the picture: a gap of the row's ground
 * (`--mark-around`) round it. Three colours, bright in both themes: yellow at work, blue done and not yet read, red to
 * be seen now. The ground may be see-through (a row's hover tint): `--mark-under` is then what it lies on, painted
 * beneath it, so the gap stays solid and the picture does not show through.
 */
export const chatMark = style({
  position: "absolute", right: -3, bottom: -3, width: 14, height: 14, borderRadius: "50%", boxSizing: "border-box",
  border: "2px solid transparent",
  backgroundImage: "linear-gradient(var(--mark-around) 0 0)", backgroundColor: "var(--mark-under, transparent)",
  selectors: {
    '&[data-tone="done"]': {
      backgroundImage: "linear-gradient(#3b82f6 0 0), linear-gradient(var(--mark-around) 0 0)",
      backgroundClip: "padding-box, border-box",
    },
    '&[data-tone="alert"]': {
      backgroundImage: "linear-gradient(#e5484d 0 0), linear-gradient(var(--mark-around) 0 0)",
      backgroundClip: "padding-box, border-box",
    },
    // Something waits on the viewer: a hollow blue ring in the gap's ground (an inset shadow is drawn inside the
    // padding box, so the gap round it stays whole); waiting only on others, the same ring in grey.
    '&[data-tone="wait"]': { boxShadow: "inset 0 0 0 2px #3b82f6" },
    '&[data-tone="other"]': { boxShadow: `inset 0 0 0 2px ${vars.subtle}` },
    // A soft halo, the heaviest of the three: nothing else in the row is this loud.
    '&[data-tone="alert"]::after': {
      content: "\"\"", position: "absolute", inset: -5, borderRadius: "50%", background: "#e5484d", opacity: 0.25,
    },
    // At work: a turning ring with a gap.
    '&[data-tone="busy"]::after': {
      content: "\"\"", position: "absolute", inset: 0, background: `${busyRing(10)} center / 100% no-repeat`,
      animation: `${spinKeyframes} 1.2s linear infinite`,
    },
  },
  "@media": { "(prefers-reduced-motion: reduce)": { selectors: { '&[data-tone="busy"]::after': { animation: "none" } } } },
});

/** The same state as a dot in a line, before the chat's title: no gap round it, the row's ground is behind it. */
export const chatMarkInline = style({
  position: "relative", flex: "none", width: 8, height: 8, borderRadius: "50%", boxSizing: "border-box",
  selectors: {
    '&[data-tone="done"]': { background: "#3b82f6" },
    '&[data-tone="alert"]': { background: "#e5484d" },
    // Waiting on the viewer: a hollow ring (10px, 2px thick: whole pixels); on others only, the same in grey.
    '&[data-tone="wait"]': { width: 10, height: 10, border: "2px solid #3b82f6" },
    '&[data-tone="other"]': { width: 10, height: 10, border: `2px solid ${vars.subtle}` },
    '&[data-tone="alert"]::after': {
      content: "\"\"", position: "absolute", inset: -3, borderRadius: "50%", background: "#e5484d", opacity: 0.25,
    },
    '&[data-tone="busy"]': {
      width: 10, height: 10, background: `${busyRing(10)} center / 100% no-repeat`,
      animation: `${spinKeyframes} 1.2s linear infinite`,
    },
  },
  "@media": { "(prefers-reduced-motion: reduce)": { selectors: { '&[data-tone="busy"]': { animation: "none" } } } },
});

/** A workspace's counts (ChatMark.tsx MarkCounts): each dot with its number, small and quiet beside its name. */
export const markCounts = style({ display: "inline-flex", alignItems: "center", gap: 10, flex: "none", fontSize: vars.textMeta, lineHeight: 1, fontVariantNumeric: "tabular-nums" });
/** The dot at full colour, its number quiet. */
export const markCount = style({ display: "inline-flex", alignItems: "center", gap: 5, color: "color-mix(in srgb, currentColor 65%, transparent)" });
/** A row's waiting line's 等你 (ChatMark.tsx WaitingText). */
export const waitingLead = style({ fontWeight: 600 });

/**
 * A state line led by an icon in the title's mark's column (ChatMark.tsx WaitingText `slot`): the icon (14px, its ink
 * narrower) centred in the mark's 10px, then what follows where the title starts (`--lead-gap` on, the gap after the title's
 * mark: 8px on phones). Not clipped: the icon stands 2px out of its column on each side; what follows ellipsizes itself.
 */
export const leadLine = style({ display: "flex", alignItems: "center", gap: "var(--lead-gap, 8px)", selectors: { "&&": { overflow: "visible" } } });
export const leadSlot = style({ display: "flex", flex: "none", width: 10, height: 14, alignItems: "center", justifyContent: "center", overflow: "visible" });
globalStyle(`${leadSlot} svg`, { flex: "none" });
export const leadRest = style({ minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
