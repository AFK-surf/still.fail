// The pointer's light (docs/ui-panels.md 悬停): one ink, `vars.hover` (the words' colour faint; white faint in the dark),
// laid over what a thing is, never a colour in its place. A thing with no ground of its own takes it as its
// background (`background: vars.hover`), over what it stands on; one with a ground of its own (a button's canvas, a
// chip's tint, the selected grey under an open toggle) takes `litOver`, the ink over that ground. So a lit thing in a
// lit thing (a tab's ×, a row's buttons) is a step more, on any ground, in either theme.
import { vars } from "./tokens.css.ts";

/** The hover ink over a thing's own ground (its `background` kept under it). */
export const litOver = { backgroundImage: `linear-gradient(${vars.hover}, ${vars.hover})` } as const;
