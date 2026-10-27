import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { spokesBox, spokesTurn } from "@stillfail/ui/styles/spokes.ts";
import { STILL, stillLoop } from "@stillfail/ui/styles/still.ts";

/**
 * A chat's state on its row's picture (ChatMark.tsx), at the corner, over the picture: a gap of the row's ground
 * (`--mark-around`) round it. Three colours, bright in both themes, one meaning each wherever they are (an agent's
 * badge, ui.css.ts agentMark, says the same): yellow at work, blue the viewer's turn (something unread, or a card or an
 * agent waiting on them: what kind the row's second line says), red gone wrong. The ground may be see-through (a row's hover tint): `--mark-under` is then what it lies on, painted
 * beneath it, so the gap stays solid and the picture does not show through.
 */
export const chatMark = style({
  position: "absolute", right: -3, bottom: -3, width: 14, height: 14, borderRadius: "50%", boxSizing: "border-box",
  border: "2px solid transparent",
  backgroundImage: "linear-gradient(var(--mark-around) 0 0)", backgroundColor: "var(--mark-under, transparent)",
  selectors: {
    '&[data-tone="done"], &[data-tone="wait"]': {
      backgroundImage: "linear-gradient(#3b82f6 0 0), linear-gradient(var(--mark-around) 0 0)",
      backgroundClip: "padding-box, border-box",
    },
    '&[data-tone="alert"]': {
      backgroundImage: "linear-gradient(#e5484d 0 0), linear-gradient(var(--mark-around) 0 0)",
      backgroundClip: "padding-box, border-box",
    },
    // At work: yellow spokes stepping round (spokes.ts), with no gap of the ground round them (it showed as a dark rim,
    // 2026-10-19): they fill the box.
    '&[data-tone="busy"]': { border: 0, backgroundImage: "none", backgroundColor: "transparent" },
    '&[data-tone="busy"]::after': { content: "\"\"", position: "absolute", inset: 2, ...spokesBox("#f2b01e") },
    [`${STILL} &[data-tone="busy"]::after`]: stillLoop(),
  },
});
spokesTurn(`${chatMark}[data-tone="busy"]::after`);

/** The same state as a dot in a line, before the chat's title: no gap round it, the row's ground is behind it. */
export const chatMarkInline = style({
  position: "relative", flex: "none", width: 8, height: 8, borderRadius: "50%", boxSizing: "border-box",
  selectors: {
    '&[data-tone="done"], &[data-tone="wait"]': { background: "#3b82f6" },
    '&[data-tone="alert"]': { background: "#e5484d" },
    '&[data-tone="busy"]': { width: 10, height: 10, ...spokesBox("#f2b01e") },
    [`${STILL} &[data-tone="busy"]`]: stillLoop(),
  },
});
spokesTurn(`${chatMarkInline}[data-tone="busy"]`);

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
/**
 * Waiting's dots breathe once, one after another, then rest; watching's dot beats and its arcs light up after it, inner
 * then outer, then rest (icons wait, watch: one path each). Every 3.1s, played from script (ChatMark.tsx LEAD_PLAYS):
 * here, how they stand between.
 *
 * Each part that moves is a copy of the icon showing that part alone, in a box of its own (`data-part`, the part's place
 * among the icon's children) laid over the icon and moved whole; the icon shows what stays. A part inside an SVG, or an
 * <svg> scaled, is moved on the main thread: the whole page drawn anew every frame, rests too, for as long as one shows.
 * A box the compositor moves alone.
 */
globalStyle(`${leadSlot}[data-motion]`, { position: "relative" });
globalStyle(`${leadSlot}[data-motion] > [data-part]`, { position: "absolute", left: "calc(50% - 7px)", top: "calc(50% - 7px)", width: 14, height: 14 });
globalStyle(`${leadSlot}[data-motion] > [data-part] > svg`, { display: "block" });
globalStyle(`${leadSlot}[data-motion="wait"] > svg > :not(:first-child), ${leadSlot}[data-motion="watch"] > svg > *, ${leadSlot}[data-motion] > [data-part] > svg > *`, { visibility: "hidden" });
for (const n of [1, 2, 3, 4]) globalStyle(`${leadSlot}[data-motion] > [data-part="${n}"] > svg > :nth-child(${n})`, { visibility: "visible" });
globalStyle(`${leadSlot}[data-motion="wait"] > [data-part]`, { opacity: .35 });
globalStyle(`${leadSlot}[data-motion="watch"] > :is([data-part="2"], [data-part="3"])`, { opacity: .3 });
export const leadRest = style({ minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
