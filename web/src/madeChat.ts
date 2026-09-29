// A new chat becoming its chat, on either screen (the wide one's NewChat.tsx, the phone's mobile/NewChat.tsx): around
// what stays (the bar, the composer: one live box throughout, never pictured twice), what the new chat had leaves (its
// scene rises out of view, the things by the composer fade where they are), and what comes is drawn where it arrives
// and moved from where it comes from: the words just sent float up out of the composer to where the chat has its first
// message, their bubble forming around them, and what follows comes up after them out of the composer. Nothing is
// crossfaded over anything.
//
// Only the leaving is a view transition (pictures of what is gone). What arrives moves on the page itself: a named
// element taken away ends a view transition at once, and the chat's rows are (the message sent is drawn anew once its
// station has it, maybe while it moves).
import { pageChanging, transitionTo } from "./ui.tsx";
import * as msgCss from "./styles/chat.css.ts";
import * as conversationCss from "./styles/conversation.css.ts";

/** Where the text in a box starts (its first line's glyphs), and its size. */
interface Typed { x: number; y: number; size: number }

function textAt(el: Element): Typed {
  const box = el.getBoundingClientRect();
  const style = getComputedStyle(el);
  return {
    x: box.left + parseFloat(style.borderLeftWidth) + parseFloat(style.paddingLeft),
    y: box.top + parseFloat(style.borderTopWidth) + parseFloat(style.paddingTop) + (parseFloat(style.lineHeight) - parseFloat(style.fontSize)) / 2,
    size: parseFloat(style.fontSize),
  };
}

/** How what arrives slows into place. */
const EASE = "cubic-bezier(.2, .8, .2, 1)";

/** A first message on its way: the words sent, where they were, until the chat's page takes them. */
interface Sending { field: HTMLElement; from: Typed; top: number; stand: HTMLElement | null }
let sending: Sending | null = null;

/**
 * The first message of a new chat is sent from `field` (a composer's text box, still showing `text`), which lies over
 * `layer` (where a stand-in for the words is drawn, at `z`): its words stay where they were, and its hint is gone,
 * until the chat's page takes them (`toMadeChat`) or the chat could not be made (`notSent`).
 */
export function sendingFirst(field: HTMLElement, text: string, layer: HTMLElement, z: string): void {
  notSent();
  const box = field.getBoundingClientRect();
  const frame = layer.getBoundingClientRect();
  const style = getComputedStyle(field);
  let stand: HTMLElement | null = null;
  if (text.trim()) {
    stand = document.createElement("div");
    stand.setAttribute("aria-hidden", "true");
    stand.textContent = text;
    Object.assign(stand.style, {
      position: "absolute", left: `${box.left - frame.left}px`, top: `${box.top - frame.top}px`, width: `${box.width}px`,
      height: `${box.height}px`, boxSizing: "border-box", padding: style.padding, overflow: "hidden", zIndex: z,
      pointerEvents: "none", font: style.font, lineHeight: style.lineHeight, color: style.color, whiteSpace: "pre-wrap",
      overflowWrap: style.overflowWrap, wordBreak: style.wordBreak, textAlign: style.textAlign,
    });
    layer.append(stand);
  }
  // What follows the message comes out of the composer's top edge, as it was when sent.
  const composer = field.closest("[data-made-composer]") ?? field;
  sending = { field, from: textAt(field), top: composer.getBoundingClientRect().top, stand };
  field.dataset.madeField = "";
  document.documentElement.dataset.madeHint = "hidden";
}

/** The first message did not go (no chat could be made): the composer is as it was. */
export function notSent(): void {
  if (!sending) return;
  sending.stand?.remove();
  delete sending.field.dataset.madeField;
  delete document.documentElement.dataset.madeHint;
  sending = null;
}

/**
 * The new chat becomes its chat (`go`, rendered at once). What leaves is what `scope` marks `data-made-leave` ("up":
 * out of view above, "fade": where it is). The chat's page is waited for (a little) until it shows its first message
 * of its own; then the words sent (`sendingFirst`) go there, drawn in `layer` at `z` (over the composer), and the rest
 * of its `list` comes up after them, `wait` ms after what leaves has begun to (a composer that stays put, with the
 * choices by it: they are gone first; one that moves away takes the words with it at once).
 */
export function toMadeChat(go: () => void, { scope, layer, z, list: findList, wait = 0 }: {
  scope: ParentNode; layer: () => HTMLElement | null; z: string; list: () => HTMLElement | null; wait?: number;
}): void {
  const now = sending;
  sending = null;
  const root = document.documentElement;
  const leaving = [...scope.querySelectorAll<HTMLElement>("[data-made-leave]")];
  leaving.forEach((el, i) => {
    el.style.viewTransitionName = `made-leave-${i}`;
    el.style.setProperty("view-transition-class", `made-${el.dataset.madeLeave}`);
  });
  root.dataset.made = "";
  const moves: Promise<unknown>[] = [transitionTo(go, () => findList()?.querySelector(`.${msgCss.msgMine}`) != null)];
  let ghost: HTMLElement | null = null;
  let list: HTMLElement | null = null;
  // The new page, before its picture is taken: what arrives set where it comes from.
  pageChanging()?.settle.push(() => {
    list = findList();
    const first = list?.querySelector<HTMLElement>(`.${msgCss.msgMine}`);
    const words = first?.querySelector(`.${msgCss.msgPlain}`);
    const into = layer();
    if (!now || !list || !first || !words || !into) return;
    // Where the message arrives, read before anything is moved.
    const to = textAt(words);
    const at = first.getBoundingClientRect();
    const box = list.getBoundingClientRect();
    const frame = into.getBoundingClientRect();
    const { from, top } = now;
    const timing = { duration: 480, delay: wait, easing: EASE, fill: "backwards" } as const;
    // The rest of the list comes up with it, out of the composer's top edge: cut there, wherever it has got to.
    const rise = from.y - to.y;
    const clip = Math.max(0, box.bottom - top);
    list.dataset.madeList = "";
    moves.push(list.animate([
      { transform: `translateY(${rise}px)`, clipPath: `inset(0 0 ${clip + rise}px 0)` },
      { transform: "none", clipPath: `inset(0 0 ${clip}px 0)` },
    ], timing).finished);
    // The message itself, drawn where it arrives by a copy of it (the row, hidden meanwhile, may be drawn anew): its
    // words from where they were typed, at the size they were typed, its bubble and time coming in around them. The
    // copy is in a layer drawn as the list is (its styles reach it).
    ghost = document.createElement("div");
    ghost.className = list.className;
    ghost.setAttribute("aria-hidden", "true");
    Object.assign(ghost.style, {
      position: "absolute", inset: "0", margin: "0", padding: "0", overflow: "visible", zIndex: z, pointerEvents: "none",
      transform: "none", clipPath: "none",
    });
    const copy = first.cloneNode(true) as HTMLElement;
    Object.assign(copy.style, {
      position: "absolute", left: `${at.left - frame.left}px`, top: `${at.top - frame.top}px`, width: `${at.width}px`,
      margin: "0", transformOrigin: `${to.x - at.left}px ${to.y - at.top}px`, animation: "none",
    });
    ghost.append(copy);
    into.append(ghost);
    // Over the pictures of what leaves (named, it is pictured after them; it is not taken away while they go).
    ghost.style.viewTransitionName = "made-arrive";
    now.stand?.remove();
    moves.push(copy.animate([
      { transform: `translate(${from.x - to.x}px, ${rise}px) scale(${from.size / to.size})` },
      { transform: "none" },
    ], timing).finished);
    const bubble = copy.querySelector<HTMLElement>(`.${conversationCss.msgBubble}`);
    if (bubble) moves.push(bubble.animate([{ backgroundColor: "transparent" }, { backgroundColor: getComputedStyle(bubble).backgroundColor }], timing).finished);
    for (const el of copy.querySelectorAll<HTMLElement>(`.${conversationCss.msgTime}`)) {
      el.style.animation = "none";
      moves.push(el.animate([{ opacity: 0 }, { opacity: 1 }], timing).finished);
    }
    // The composer's hint comes in once the words are out of it (above its top edge), not while they pass over it.
    const out = () => {
      if (!copy.isConnected || copy.getBoundingClientRect().bottom <= top) delete root.dataset.madeHint;
      else requestAnimationFrame(out);
    };
    requestAnimationFrame(out);
  });
  void Promise.allSettled(moves).then(async () => {
    // The page's own moves, begun as the new page settled (within the transition), are over too.
    await Promise.allSettled(moves);
    for (const el of leaving) { el.style.viewTransitionName = ""; el.style.removeProperty("view-transition-class"); }
    ghost?.remove();
    now?.stand?.remove();
    if (now) delete now.field.dataset.madeField;
    if (list) delete list.dataset.madeList;
    delete root.dataset.made;
    delete root.dataset.madeHint;
  });
}
