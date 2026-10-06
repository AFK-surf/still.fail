// A new chat becoming its chat, on either screen (the wide one's NewChat.tsx, the phone's mobile/NewChat.tsx): around
// what stays (the bar, the composer: one live box throughout, never pictured twice), what the new chat had leaves (its
// scene rises out of view, the things by the composer fade where they are), and what comes is drawn where it arrives
// and moved from where it comes from: the words just sent float up out of the composer to where the chat has its first
// message, their bubble forming around them, and what follows comes up after them out of the composer. Nothing is
// crossfaded over anything.
//
// What leaves is kept as DOM copies; what arrives moves on the page itself. No whole-page snapshot blocks painting
// while the chat mounts. The message flies as a copy because its row can be replaced by the station receipt.
import { pageChanging, transitionLive } from "./ui.tsx";
import { cubicBezier } from "motion";
import { reducedMotion } from "./motion.ts";
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
interface Picture { key: string; rect: DOMRect; stand: HTMLElement }
interface Sending { field: HTMLElement; from: Typed; top: number; stand: HTMLElement | null; pictures: Picture[]; release?: (() => void) | undefined }
let sending: Sending | null = null;

/**
 * The first message of a new chat is sent from `field` (a composer's text box, still showing `text`), which lies over
 * `layer` (where a stand-in for the words is drawn, at `z`): its words stay where they were, and its hint is gone,
 * until the chat's page takes them (`toMadeChat`) or the chat could not be made (`notSent`).
 */
export function sendingFirst(field: HTMLElement, text: string, layer: HTMLElement, z: string): void {
  notSent();
  // The PC dock holds its geometry while clearing the draft and waiting for the destination page.
  const hold = new CustomEvent<{ release?: () => void }>("hold-first-composer", { bubbles: true, detail: {} });
  field.dispatchEvent(hold);
  const stand = standIn(field, text, layer, z);
  // What follows the message comes out of the composer's top edge, as it was when sent.
  const composer = field.closest("[data-made-composer]") ?? field;
  const pictures = picturesIn(composer, layer, z);
  sending = { field, from: textAt(field), top: composer.getBoundingClientRect().top, stand, pictures, release: hold.detail.release };
  field.dataset.madeField = "";
  document.documentElement.dataset.madeHint = "hidden";
}

/** The images going with the message, drawn in `layer` (at `z`) where their thumbnails are in `composer`, cropped as there. */
function picturesIn(composer: Element, layer: HTMLElement, z: string): Picture[] {
  const base = layer.getBoundingClientRect();
  const pictures: Picture[] = [];
  for (const source of composer.querySelectorAll<HTMLElement>("[data-send-image]")) {
    const img = source.querySelector("img");
    if (!img?.complete || !img.naturalWidth) continue;
    const rect = source.getBoundingClientRect();
    const picture = document.createElement("div");
    picture.setAttribute("aria-hidden", "true");
    Object.assign(picture.style, {
      position: "absolute", left: `${rect.left - base.left}px`, top: `${rect.top - base.top}px`,
      width: `${rect.width}px`, height: `${rect.height}px`, overflow: "hidden",
      borderRadius: getComputedStyle(source).borderRadius, zIndex: z, pointerEvents: "none",
    });
    const copy = img.cloneNode(true) as HTMLImageElement;
    Object.assign(copy.style, { width: "100%", height: "100%", objectFit: "cover", display: "block" });
    picture.append(copy);
    layer.append(picture);
    pictures.push({ key: source.dataset.sendImage!, rect, stand: picture });
  }
  return pictures;
}

/** The words just sent, drawn in `layer` (at `z`) where they were in `field` (a composer's text box), as they were typed. */
function standIn(field: HTMLElement, text: string, layer: HTMLElement, z: string): HTMLElement | null {
  if (!text.trim()) return null;
  const box = field.getBoundingClientRect();
  const frame = layer.getBoundingClientRect();
  const style = getComputedStyle(field);
  const stand = document.createElement("div");
  stand.setAttribute("aria-hidden", "true");
  stand.textContent = text;
  Object.assign(stand.style, {
    position: "absolute", left: `${box.left - frame.left}px`, top: `${box.top - frame.top}px`, width: `${box.width}px`,
    height: `${box.height}px`, boxSizing: "border-box", padding: style.padding, overflow: "hidden", zIndex: z,
    pointerEvents: "none", font: style.font, lineHeight: style.lineHeight, color: style.color, whiteSpace: "pre-wrap",
    overflowWrap: style.overflowWrap, wordBreak: style.wordBreak, textAlign: style.textAlign,
  });
  layer.append(stand);
  return stand;
}

/** The first message did not go (no chat could be made): the composer is as it was. */
export function notSent(): void {
  if (!sending) return;
  sending.release?.();
  sending.stand?.remove();
  for (const picture of sending.pictures) picture.stand.remove();
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
  // Keep only the departing scene. Capturing the whole document with startViewTransition freezes painting
  // while the chat mounts, and turns its layout work into a visible pause before any of the flight can move.
  const leaving: { el: HTMLElement; original: HTMLElement; visibility: string; up: boolean }[] = [];
  const scene = layer();
  if (scene && !reducedMotion()) {
    const base = scene.getBoundingClientRect();
    for (const el of scope.querySelectorAll<HTMLElement>("[data-made-leave]")) {
      const at = el.getBoundingClientRect();
      const copy = el.cloneNode(true) as HTMLElement;
      const style = getComputedStyle(el);
      copy.setAttribute("aria-hidden", "true");
      copy.inert = true;
      Object.assign(copy.style, {
        position: "absolute", left: `${at.left - base.left}px`, top: `${at.top - base.top}px`,
        width: `${at.width}px`, height: `${at.height}px`, margin: "0", zIndex: z, pointerEvents: "none",
        font: style.font, color: style.color, textAlign: style.textAlign,
      });
      scene.append(copy);
      leaving.push({ el: copy, original: el, visibility: el.style.visibility, up: el.dataset.madeLeave === "up" });
      // React can keep the old page while its next topic is loading; do not draw it twice.
      el.style.visibility = "hidden";
    }
  }
  root.dataset.made = "";
  const moves: Promise<unknown>[] = [transitionLive(go, () => findList()?.querySelector(`.${msgCss.msgMine}`) != null, 480 + wait)];
  let ghost: HTMLElement | null = null;
  let list: HTMLElement | null = null;
  // The departing scene responds now, while the first row becomes ready behind it.
  for (const { el, up } of leaving) moves.push(el.animate([
    { opacity: 1, transform: "none" },
    { opacity: 0, transform: up ? "translateY(-32px) scale(.96)" : "none" },
  ], { duration: up ? 140 : 80, easing: EASE, fill: "forwards" }).finished);
  // The new page, before its first paint: what arrives set where it comes from.
  pageChanging()?.settle.push(() => {
    list = findList();
    const first = list?.querySelector<HTMLElement>(`.${msgCss.msgMine}`);
    const words = first?.querySelector(`.${msgCss.msgPlain}`);
    const into = layer();
    if (!now || !list || !first || !into) return;
    const anchor = words ?? first.querySelector("[data-send-image]");
    if (!anchor) return;
    // Where the message arrives, read before anything is moved.
    const to = textAt(anchor);
    const at = first.getBoundingClientRect();
    const box = list.getBoundingClientRect();
    const frame = into.getBoundingClientRect();
    // Capture image destinations before translating the list itself.
    const destinations = new Map([...first.querySelectorAll<HTMLElement>("[data-send-image]")].map((el) =>
      [el.dataset.sendImage!, { rect: el.getBoundingClientRect(), radius: getComputedStyle(el).borderRadius }]));
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
    ghost.dataset.madeArrive = "";
    now.stand?.remove();
    // Images leave from their own thumbnails, not from the text's baseline. Keep the decoded image throughout:
    // cloning the outbox alone would capture its loading placeholder and flash at the start of the flight.
    for (const picture of now.pictures) {
      const target = destinations.get(picture.key);
      const covered = [...copy.querySelectorAll<HTMLElement>("[data-send-image]")].find((el) => el.dataset.sendImage === picture.key);
      if (!target || !covered) continue;
      const end = target.rect;
      covered.style.visibility = "hidden";
      ghost.append(picture.stand);
      Object.assign(picture.stand.style, {
        left: `${end.left - frame.left}px`, top: `${end.top - frame.top}px`,
        width: `${end.width}px`, height: `${end.height}px`, transformOrigin: "0 0",
        borderRadius: target.radius,
      });
      moves.push(picture.stand.animate([
        { transform: `translate(${picture.rect.left - end.left}px, ${picture.rect.top - end.top}px)`, width: `${picture.rect.width}px`, height: `${picture.rect.height}px` },
        { transform: "none", width: `${end.width}px`, height: `${end.height}px` },
      ], timing).finished);
    }
    moves.push(copy.animate([
      { transform: `translate(${from.x - to.x}px, ${rise}px) scale(${from.size / to.size})` },
      { transform: "none" },
    ], timing).finished);
    const bubble = copy.querySelector<HTMLElement>(`.${conversationCss.msgBubble}`);
    if (bubble) moves.push(bubble.animate([{ backgroundColor: "transparent" }, { backgroundColor: getComputedStyle(bubble).backgroundColor }], timing).finished);
    for (const el of copy.querySelectorAll<HTMLElement>(`.${conversationCss.msgTime}`)) {
      // "sending" shows when the row's does (its row, the copy gone, shows it then).
      if (el.dataset.showsAt) showAt(el);
      else el.style.animation = "none";
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
    for (const { el, original, visibility } of leaving) { el.remove(); original.style.visibility = visibility; }
    ghost?.remove();
    now?.release?.();
    now?.stand?.remove();
    for (const picture of now?.pictures ?? []) picture.stand.remove();
    if (now) delete now.field.dataset.madeField;
    if (list) {
      // Removing the flight flag must not start the ordinary row entrance a second time.
      for (const row of list.querySelectorAll<HTMLElement>(`.${msgCss.msgMine}`)) row.style.animation = "none";
      delete list.dataset.madeList;
    }
    delete root.dataset.made;
    delete root.dataset.madeHint;
  });
}

/** A copy of what shows at `data-shows-at` (OutboxRow's "sending"): its delay begins anew with it, so is what is left of it. */
function showAt(el: HTMLElement): void {
  el.style.animationDelay = `${Math.max(0, Number(el.dataset.showsAt) - Date.now())}ms`;
}

// ── a message sent in a chat already open ──────────────────────────────

/** How long the words sent wait at the composer for their row before they are given back to it. */
const WAIT_FOR_ROW = 2000;
/** How long the words take to their row. */
const ARRIVE = 520;
/** How each way of it goes: slow to leave, quick between, gently into place. */
const FLIGHT = cubicBezier(0.6, 0, 0.2, 1);

/**
 * Where the words are on their way at `t` (0..1 of ARRIVE), each way apart: across first, and up a little after it, so
 * they rise on a curve rather than slide.
 */
function flight(t: number): { up: number; across: number } {
  return { across: FLIGHT(Math.min(1, t / 0.88)), up: FLIGHT(Math.max(0, (t - 0.12) / 0.88)) };
}

/** Words sent in an open chat, waiting for their row or on their way to it; `done` lets them go (at once). */
let flying: { done(): void } | null = null;

/**
 * A message is sent in an open chat from `field` (a composer's text box, still showing `text`) into `list` (the chat's
 * list): its words stay where they were typed, drawn in `layer` (over the composer, at `z`), its hint gone, until this
 * device's own row for it is in the list (the first of the viewer's own not there when it was sent: the outbox's, or
 * the station's message itself when it is quick). Then that row is drawn from there to its place, over what it
 * passes, its words from the size they were typed at to their own, its bubble's ground and its time coming in on the
 * way; where it goes is read again every frame (the list may move as it settles), and the list itself does not move.
 * The row itself, hidden meanwhile, is shown again as the copy of it goes, in the same frame. The images going with it
 * fly the same way, each from its thumbnail in the composer to its place in the row (the thumbnail's crop opening out
 * to the image's own proportions); sent with no words, they fly on their own and the row comes in where it is. With no
 * row within a while (it could not be sent), the words are the composer's again.
 */
export function sendingHere(field: HTMLElement, text: string, { layer, z, list }: { layer: HTMLElement; z: string; list: HTMLElement }): void {
  flying?.done();
  if (reducedMotion()) return;
  const composer = field.closest("[data-made-composer]") ?? field;
  const stand = standIn(field, text, layer, z);
  const pictures = picturesIn(composer, layer, z);
  if (!stand && !pictures.length) return;
  const root = document.documentElement;
  const mine = `.${msgCss.msgMine}`;
  const before = new Set(list.querySelectorAll(mine));
  const from = textAt(field);
  field.dataset.madeField = "";
  // Only words pass over the hint; images alone leave it where it is.
  if (stand) root.dataset.madeHint = "hidden";
  root.dataset.sent = "";
  // The rows it went into (the outbox's, then the message that takes its place): hidden while their copy is on its way,
  // and never easing in by themselves.
  const rows: HTMLElement[] = [];
  const take = () => {
    for (const el of list.querySelectorAll<HTMLElement>(mine)) {
      if (before.has(el) || rows.includes(el)) continue;
      el.style.animation = "none";
      // Hide the row and its delayed status together, without changing opacity: the chat's emphasis transition
      // would otherwise fade the real row back in after its flying copy has already gone.
      el.dataset.sendCovered = "";
      rows.push(el);
    }
    return rows.findLast((el) => el.isConnected) ?? null;
  };
  let ghost: HTMLElement | null = null;
  let copy: HTMLElement | null = null;
  let of: HTMLElement | null = null;
  let ground = "";
  let clock: Animation | null = null;
  let frame = 0;
  let over = false;
  const done = () => {
    if (over) return;
    over = true;
    if (flying?.done === done) flying = null;
    observer.disconnect();
    clearTimeout(timeout);
    cancelAnimationFrame(frame);
    clock?.cancel();
    ghost?.remove();
    stand?.remove();
    for (const picture of pictures) picture.stand.remove();
    for (const el of rows) delete el.dataset.sendCovered;
    delete root.dataset.madeHint;
    // The hint eases back (data-sent), then the field is as it was.
    setTimeout(() => {
      if (flying) return;
      delete field.dataset.madeField;
      delete root.dataset.sent;
    }, 200);
  };
  // Where the row is now, its copy drawn so far on its way from the composer.
  const place = () => {
    const row = take();
    if (!row || !ghost || !clock) return;
    if (row !== of || !copy) {
      // The first, or the one that took its place: drawn as it is now.
      of = row;
      const next = row.cloneNode(true) as HTMLElement;
      delete next.dataset.sendCovered;
      for (const el of next.querySelectorAll<HTMLElement>("[data-shows-at]")) showAt(el);
      // Its images are drawn by the pictures flying into them.
      for (const el of next.querySelectorAll<HTMLElement>("[data-send-image]")) {
        if (pictures.some((p) => p.key === el.dataset.sendImage)) el.style.visibility = "hidden";
      }
      if (copy) copy.replaceWith(next); else ghost.prepend(next);
      copy = next;
      if (!ground) {
        const bubble = copy.querySelector(`.${conversationCss.msgBubble}`);
        ground = bubble ? getComputedStyle(bubble).backgroundColor : "";
      }
    }
    const words = stand ? row.querySelector(`.${msgCss.msgPlain}`) : null;
    const at = row.getBoundingClientRect();
    const box = layer.getBoundingClientRect();
    const { up, across } = flight(clock.effect?.getComputedTiming().progress ?? 1);
    const e = Math.min(1, across);
    Object.assign(copy.style, { position: "absolute", left: `${at.left - box.left}px`, top: `${at.top - box.top}px`, width: `${at.width}px`, margin: "0" });
    if (words) {
      const to = textAt(words);
      const s = from.size / to.size + (1 - from.size / to.size) * up;
      Object.assign(copy.style, {
        transformOrigin: `${to.x - at.left}px ${to.y - at.top}px`,
        transform: `translate(${(from.x - to.x) * (1 - across)}px, ${(from.y - to.y) * (1 - up)}px) scale(${s})`,
      });
    }
    // Each image from its thumbnail to its place in the row as it is now: across and up as the words go, its box
    // growing from the thumbnail's to its own.
    for (const picture of pictures) {
      const target = row.querySelector<HTMLElement>(`[data-send-image="${picture.key}"]`);
      if (!target) continue;
      const end = target.getBoundingClientRect();
      const a = picture.rect;
      if (!picture.stand.dataset.flying) {
        picture.stand.dataset.flying = "";
        picture.stand.style.borderRadius = getComputedStyle(target).borderRadius;
      }
      Object.assign(picture.stand.style, {
        left: `${a.left + (end.left - a.left) * across - box.left}px`, top: `${a.top + (end.top - a.top) * up - box.top}px`,
        width: `${a.width + (end.width - a.width) * up}px`, height: `${a.height + (end.height - a.height) * up}px`,
      });
    }
    const bubble = copy.querySelector<HTMLElement>(`.${conversationCss.msgBubble}`);
    if (bubble && ground) bubble.style.backgroundColor = `color-mix(in srgb, ${ground} ${e * 100}%, transparent)`;
    // (Its own delay kept: "sending" shows when the row's does.)
    for (const el of copy.querySelectorAll<HTMLElement>(`.${conversationCss.msgTime}`)) el.style.opacity = `${e}`;
    // Out of the composer (its top edge as it is now): its hint comes back.
    if (words && root.dataset.madeHint && copy.getBoundingClientRect().bottom <= composer.getBoundingClientRect().top) delete root.dataset.madeHint;
  };
  const tick = () => { place(); frame = requestAnimationFrame(tick); };
  // The row comes as the list is drawn anew: its copy takes the words' place before the frame is painted.
  const start = () => {
    const row = take();
    if (!row || ghost) return;
    const flies = (stand && row.querySelector(`.${msgCss.msgPlain}`)) || pictures.some((p) => row.querySelector(`[data-send-image="${p.key}"]`));
    if (!flies) { done(); return; }
    clearTimeout(timeout);
    ghost = document.createElement("div");
    ghost.className = list.className;
    ghost.setAttribute("aria-hidden", "true");
    Object.assign(ghost.style, {
      position: "absolute", inset: "0", margin: "0", padding: "0", overflow: "visible", zIndex: z, pointerEvents: "none",
      transform: "none", clipPath: "none", maskImage: "none",
    });
    layer.append(ghost);
    stand?.remove();
    // Over the row's copy, as they were over the composer.
    for (const picture of pictures) ghost.append(picture.stand);
    // The one timeline all of it follows (what it moves is read anew each frame): paused and stepped, so is it.
    clock = ghost.animate([{ opacity: 1 }, { opacity: 1 }], { duration: ARRIVE, easing: "linear" });
    place();
    frame = requestAnimationFrame(tick);
    void clock.finished.then(done, () => {});
  };
  const observer = new MutationObserver(() => { if (ghost) take(); else start(); });
  observer.observe(list, { childList: true, subtree: true });
  const timeout = setTimeout(done, WAIT_FOR_ROW);
  flying = { done };
}
