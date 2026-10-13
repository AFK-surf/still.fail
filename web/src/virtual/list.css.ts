import { style } from "@vanilla-extract/css";

/** The room of the items not made (list.tsx): as tall as it says, the list's gap on the sides it has a neighbour taken back. */
export const spacer = style({
  flex: "none", padding: "0", pointerEvents: "none",
  selectors: {
    "&[data-where=\"first\"]": { marginBottom: "calc(-1 * var(--list-gap, 28px))" },
    "&[data-where=\"between\"]": { marginTop: "calc(-1 * var(--list-gap, 28px))", marginBottom: "calc(-1 * var(--list-gap, 28px))" },
    "&[data-where=\"last\"]": { marginTop: "calc(-1 * var(--list-gap, 28px))" },
  },
});
