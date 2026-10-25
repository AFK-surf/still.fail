import { globalStyle, style } from "@vanilla-extract/css";

/** Virtual lists own their anchor. Native rubber-banding must not compete with their scrollTop corrections.
 * Apply from the shared hook so Home, chat, history and future virtual panes follow the same rule. */
export const pane = style({ selectors: { "&&": { overscrollBehaviorY: "none", overflowAnchor: "none" } } });

/** The room of the items not made (list.tsx): as tall as it says, the list's gap on the sides it has a neighbour taken back. */
export const spacer = style({
  flex: "none", padding: "0", pointerEvents: "none",
  selectors: {
    "&[data-where=\"first\"]": { marginBottom: "calc(-1 * var(--list-gap, 28px))" },
    "&[data-where=\"between\"]": { marginTop: "calc(-1 * var(--list-gap, 28px))", marginBottom: "calc(-1 * var(--list-gap, 28px))" },
    "&[data-where=\"last\"]": { marginTop: "calc(-1 * var(--list-gap, 28px))" },
  },
});

/** How far under the row before it a row that goes with it is (`data-joined`: the viewer's messages sent one after
 *  another), rather than the list's gap: its gap taken back but this much (list.tsx counts it so). */
export const JOINED_GAP = 4;
globalStyle("[data-vk][data-joined]:not([data-held])", { marginTop: `calc(-1 * var(--list-gap, 28px) + ${JOINED_GAP}px)` });
