// A new chat becoming its chat (madeChat.ts): the flight and departing scene are live DOM layers.
import { globalStyle } from "@vanilla-extract/css";
import { msgMine } from "./styles/chat.css.ts";

const made = ":root[data-made]";
// The composer stays on the page, not pictured apart: what arrives passes over it.
globalStyle(`${made} [data-made-composer]`, { viewTransitionName: "none" });
// Its flight owns the entrance. Measuring the ordinary 6px row entrance would capture a moving destination.
globalStyle(`${made} ${msgMine}[data-enter]`, { animation: "none" });
// The first message is drawn on its way by a copy of it.
globalStyle(`${made} ${msgMine}`, { visibility: "hidden" });
globalStyle(`${made} [data-made-arrive] ${msgMine}`, { visibility: "visible" });
// In an open chat, the flying copy takes the row's place. Its handoff is instantaneous; opacity belongs to the
// chat's emphasis transition. Cover descendants too: a delayed sending/waiting status sets its own visibility.
globalStyle(`${msgMine}[data-send-covered], ${msgMine}[data-send-covered] *`, { visibility: "hidden !important" as "hidden" });
// The composer's hint is gone as the words are sent, and comes in where it is once they have left the composer (only
// that eased: going, or a theme's change, is not). So too for a message sent in an open chat (data-sent).
globalStyle(`:is(${made}, :root[data-sent]):not([data-made-hint]) [data-made-field]::placeholder`, { transition: "color 200ms cubic-bezier(.2, .8, .2, 1)" });
globalStyle(`:root[data-made-hint="hidden"] [data-made-field]::placeholder`, { color: "transparent" });
