// A new chat becoming its chat (madeChat.ts): only what leaves is pictured; the rest is the new page at once. The
// pictures hang off the document, not the phone's root: its easing variables are not theirs, so written out.
import { globalStyle, keyframes } from "@vanilla-extract/css";
import { msgMine } from "./styles/chat.css.ts";

const made = ":root[data-made]";
const upOut = keyframes({ to: { opacity: 0, transform: "translateY(-32px) scale(.96)" } });
const fadeOut = keyframes({ to: { opacity: 0 } });
globalStyle(`${made}::view-transition-old(root)`, { display: "none" });
globalStyle(`${made}::view-transition-new(root)`, { animation: "none" });
// Out of the way before the words pass where they were (going at once, slowing as they go): the scene out of view
// above, what lies by the composer where it is.
globalStyle(`${made}::view-transition-old(*.made-up)`, { animation: `${upOut} 140ms cubic-bezier(.2, .8, .2, 1) both` });
globalStyle(`${made}::view-transition-old(*.made-fade)`, { animation: `${fadeOut} 80ms cubic-bezier(.3, 0, .5, 1) both` });
// The words on their way, over what leaves (their own moves carry them).
globalStyle(`${made}::view-transition-group(made-arrive), ${made}::view-transition-new(made-arrive)`, { animation: "none" });
// The composer stays on the page, not pictured apart: what arrives passes over it.
globalStyle(`${made} [data-made-composer]`, { viewTransitionName: "none" });
// Its flight owns the entrance. Measuring the ordinary 6px row entrance would capture a moving destination.
globalStyle(`${made} ${msgMine}[data-enter]`, { animation: "none" });
// The first message is drawn on its way by a copy of it.
globalStyle(`${made} [data-made-list] ${msgMine}`, { visibility: "hidden" });
// In an open chat, the flying copy takes the row's place. Its handoff is instantaneous; opacity belongs to the
// chat's emphasis transition. Cover descendants too: a delayed sending/waiting status sets its own visibility.
globalStyle(`${msgMine}[data-send-covered], ${msgMine}[data-send-covered] *`, { visibility: "hidden !important" as "hidden" });
// The composer's hint is gone as the words are sent, and comes in where it is once they have left the composer (only
// that eased: going, or a theme's change, is not). So too for a message sent in an open chat (data-sent).
globalStyle(`:is(${made}, :root[data-sent]):not([data-made-hint]) [data-made-field]::placeholder`, { transition: "color 200ms cubic-bezier(.2, .8, .2, 1)" });
globalStyle(`:root[data-made-hint="hidden"] [data-made-field]::placeholder`, { color: "transparent" });
