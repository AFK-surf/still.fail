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
import { motionMs, play } from "@stillfail/ui/motion.ts";
import { listQueue } from "./listQueue.ts";
import * as msgCss from "./styles/chat.css.ts";
import * as conversationCss from "./styles/conversation.css.ts";

/** Where the text in a box starts (its first line's glyphs), and its size. */
interface Typed { x: number; y: number; size: number }

function textAt(el: Element): Typed {
  const box = el.getBoundingClientRect();
  const style = getComputedStyle(el);
  return {
    x: box.left + parseFloat(style.borderLeftWidth) + parseFloat(style.paddingLeft),
    // Its first line, above the box when it is scrolled (a long draft, its end in view).
    y: box.top - el.scrollTop + parseFloat(style.borderTopWidth) + parseFloat(style.paddingTop) + (parseFloat(style.lineHeight) - parseFloat(style.fontSize)) / 2,
    size: parseFloat(style.fontSize),
  };
}

/** How what arrives slows into place. */
const EASE = "cubic-bezier(.2, .8, .2, 1)";

/**
 * An image on its way, drawn as the message draws it (its picture covering its box, object-fit: cover, so cropped by
 * the same rule at every size), its box going from its thumbnail's to the message's: `rect` and `radius`, the
 * thumbnail's; `ground`, what the message's box is filled with behind it (seen through a picture's clear parts).
 */
interface Picture {
  key: string; rect: DOMRect; radius: number; stand: HTMLElement; ratio: number;
  ground?: string;
}
/** A first message on its way: the words sent, where they were, until the chat's page takes them. */
interface Sending { field: HTMLElement; from: Typed; top: number; stand: HTMLElement | null; pictures: Picture[]; leaves: Map<HTMLElement, Animation>; release?: (() => void) | undefined }
let sending: Sending | null = null;

/**
 * The first message of a new chat is sent from `field` (a composer's text box, still showing `text`), which lies over
 * `layer` (where a stand-in for the words is drawn, at `z`): its words stay where they were, and its hint is gone,
 * until the chat's page takes them (`toMadeChat`) or the chat could not be made (`notSent`). What `scope` marks
 * `data-made-leave` leaves from now, not once the chat is made (`toMadeChat` goes on with it; `notSent` brings it back).
 */
export function sendingFirst(field: HTMLElement, text: string, layer: HTMLElement, z: string, scope: ParentNode = document): void {
  notSent();
  // The PC dock holds its geometry while clearing the draft and waiting for the destination page.
  const hold = new CustomEvent<{ release?: () => void }>("hold-first-composer", { bubbles: true, detail: {} });
  field.dispatchEvent(hold);
  const stand = standIn(field, text, layer, z);
  // What follows the message comes out of the composer's top edge, as it was when sent.
  const composer = field.closest("[data-made-composer]") ?? field;
  const pictures = picturesIn(composer, layer, z);
  const leaves = new Map<HTMLElement, Animation>();
  for (const el of scope.querySelectorAll<HTMLElement>("[data-made-leave]")) leaves.set(el, leave(el));
  sending = { field, from: textAt(field), top: composer.getBoundingClientRect().top, stand, pictures, leaves, release: hold.detail.release };
  field.dataset.madeField = "";
  field.dataset.madeHint = "hidden";
}

/**
 * Where an image lands in `to` (its box in a message, at `end`): the whole box; or a letterboxed one's picture, its own
 * proportions fitted inside it (Chat.css.ts's `data-letterbox`, object-fit: contain).
 */
function landsAt(to: HTMLElement, end: DOMRect, ratio: number): { left: number; top: number; width: number; height: number } {
  if (to.dataset.letterbox === undefined) return { left: end.left, top: end.top, width: end.width, height: end.height };
  const height = Math.min(end.height, end.width / ratio), width = height * ratio;
  return { left: end.left + (end.width - width) / 2, top: end.top + (end.height - height) / 2, width, height };
}

/** `to` given the shape of `from`'s corners (their radius is copied apart): without it a squircle's radius is drawn
 * round, and one as large as the composer thumbnail's is near a circle. */
function corners(to: HTMLElement, from: Element) {
  to.style.setProperty("corner-shape", getComputedStyle(from).getPropertyValue("corner-shape"));
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
    corners(picture, source);
    const ratio = img.naturalWidth / img.naturalHeight;
    // As the thumbnail and the message draw it: covering its box, whatever shape the box has on the way.
    const copy = document.createElement("img");
    copy.src = img.currentSrc || img.src;
    copy.alt = "";
    Object.assign(copy.style, { width: "100%", height: "100%", objectFit: "cover", display: "block", maxWidth: "none", maxHeight: "none" });
    picture.append(copy);
    layer.append(picture);
    pictures.push({ key: source.dataset.sendImage!, rect, radius: parseFloat(getComputedStyle(source).borderTopLeftRadius) || 0, stand: picture, ratio });
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
  // Scrolled as the field was: the lines seen there, not its first ones.
  stand.scrollTop = field.scrollTop;
  return stand;
}

/** What leaves as the new chat becomes its chat (`data-made-leave`), fading where it is: "up", the scene, 140 ms; "fade", what is by the composer, 80 ms. */
function leave(el: HTMLElement): Animation {
  return play(el, [{ opacity: 1 }, { opacity: 0 }], { duration: el.dataset.madeLeave === "up" ? 140 : 80, easing: EASE, fill: "forwards" });
}

/** The first message did not go (no chat could be made): the composer is as it was, and what had begun to leave is back. */
export function notSent(): void {
  if (!sending) return;
  for (const a of sending.leaves.values()) {
    a.reverse();
    void a.finished.then(() => a.cancel(), () => {});
  }
  sending.release?.();
  sending.stand?.remove();
  for (const picture of sending.pictures) picture.stand.remove();
  delete sending.field.dataset.madeField;
  delete sending.field.dataset.madeHint;
  sending = null;
}

/**
 * The new chat becomes its chat (`go`, rendered at once). What leaves is what `scope` marks `data-made-leave`, fading
 * where it is (`leave`), on from where it had gone since the words were sent. The chat's page is waited for (a little) until it shows its first message
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
  const leaving: { el: HTMLElement; original: HTMLElement; visibility: string; gone: Animation | undefined }[] = [];
  const scene = layer();
  if (scene) {
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
      leaving.push({ el: copy, original: el, visibility: el.style.visibility, gone: now?.leaves.get(el) });
      // React can keep the old page while its next topic is loading; do not draw it twice.
      el.style.visibility = "hidden";
    }
  }
  root.dataset.made = "";
  const moves: Promise<unknown>[] = [transitionLive(go, () => findList()?.querySelector(`.${msgCss.msgMine}`) != null, 480 + wait)];
  let ghost: HTMLElement | null = null;
  let list: HTMLElement | null = null;
  let following: MutationObserver | null = null;
  // The departing scene goes on leaving, while the first row becomes ready behind it: its copy from where the words
  // sent had taken it (the original, hidden, as it was).
  for (const { el, gone } of leaving) {
    const a = leave(el);
    if (gone) {
      a.currentTime = gone.currentTime;
      gone.cancel();
    }
    moves.push(a.finished);
  }
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
      [el.dataset.sendImage!, { el, rect: el.getBoundingClientRect(), radius: getComputedStyle(el).borderRadius, corner: getComputedStyle(el).getPropertyValue("corner-shape"), ground: getComputedStyle(el).backgroundColor }]));
    const { from, top } = now;
    const timing = { duration: 480, delay: wait, easing: EASE, fill: "backwards" } as const;
    // The rest of the list comes up with it, out of the composer's top edge: cut there, wherever it has got to.
    const rise = from.y - to.y;
    const clip = Math.max(0, box.bottom - top);
    list.dataset.madeList = "";
    moves.push(play(list, [
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
      const end = landsAt(target.el, target.rect, picture.ratio);
      covered.style.visibility = "hidden";
      ghost.append(picture.stand);
      Object.assign(picture.stand.style, {
        left: `${end.left - frame.left}px`, top: `${end.top - frame.top}px`,
        width: `${end.width}px`, height: `${end.height}px`, transformOrigin: "0 0",
        borderRadius: target.radius,
      });
      picture.stand.style.setProperty("corner-shape", target.corner);
      // Its box's ground, if it has one, comes in on the way (the thumbnail has none): landed, it is on what the message's is.
      picture.stand.style.backgroundColor = target.ground;
      // Its corners from the thumbnail's to the message's, as its box grows.
      moves.push(play(picture.stand, [
        { transform: `translate(${picture.rect.left - end.left}px, ${picture.rect.top - end.top}px)`, width: `${picture.rect.width}px`, height: `${picture.rect.height}px`, borderRadius: `${picture.radius}px`, backgroundColor: "transparent" },
        { transform: "none", width: `${end.width}px`, height: `${end.height}px`, borderRadius: target.radius, backgroundColor: target.ground },
      ], timing).finished);
    }
    const clock = play(copy, [
      { transform: `translate(${from.x - to.x}px, ${rise}px) scale(${from.size / to.size})` },
      { transform: "none" },
    ], timing);
    moves.push(clock.finished);
    const bubble = copy.querySelector<HTMLElement>(`.${conversationCss.msgBubble}`);
    if (bubble) moves.push(play(bubble, [{ backgroundColor: "transparent" }, { backgroundColor: getComputedStyle(bubble).backgroundColor }], timing).finished);
    const lines = (row: Element) => [...row.querySelectorAll<HTMLElement>(`.${conversationCss.msgTime}`)];
    const comeIn = (el: HTMLElement) => {
      // "sending" shows when the row's does (its row, the copy gone, shows it then).
      if (el.dataset.showsAt) showAt(el);
      else el.style.animation = "none";
      const a = play(el, [{ opacity: 0 }, { opacity: 1 }], timing);
      a.currentTime = clock.currentTime;
      moves.push(a.finished);
    };
    for (const el of lines(copy)) comeIn(el);
    // The station's message taking the outbox row's place on the way: its line under it ("刚刚" for "sending") in the
    // copy from then on, as far in as the rest, rather than appearing as the copy goes.
    let shown: Element = first;
    following = new MutationObserver(() => {
      const row = list?.querySelector<HTMLElement>(`.${msgCss.msgMine}`);
      if (!row || row === shown) return;
      shown = row;
      const was = lines(copy);
      for (const [i, line] of lines(row).entries()) {
        const next = line.cloneNode(true) as HTMLElement;
        const old = was[i];
        if (old) old.replaceWith(next); else copy.append(next);
        comeIn(next);
      }
      for (const old of was.slice(lines(row).length)) old.remove();
    });
    following.observe(list, { childList: true, subtree: true });
    // The composer's hint comes in once the words are out of it (above its top edge), not while they pass over it.
    const out = () => {
      if (!copy.isConnected || copy.getBoundingClientRect().bottom <= top) { if (now) delete now.field.dataset.madeHint; }
      else requestAnimationFrame(out);
    };
    requestAnimationFrame(out);
  });
  void Promise.allSettled(moves).then(async () => {
    // The page's own moves, begun as the new page settled (within the transition), are over too.
    await Promise.allSettled(moves);
    for (const { el, original, visibility } of leaving) { el.remove(); original.style.visibility = visibility; }
    following?.disconnect();
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
    if (now) delete now.field.dataset.madeHint;
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

/** What a chat's list says of what it had (`data-last-seq`, `data-outbox`), for `sendingHere` to know the row sent. */
export function sentAfter(chat: { messages: readonly { seq: number }[]; outbox: readonly { id: string }[]; newer?: boolean }): Record<string, string> {
  return { "data-last-seq": chat.newer ? "" : String(chat.messages.at(-1)?.seq ?? 0), "data-outbox": chat.outbox.map((o) => o.id).join(" ") };
}

/** Words sent in an open chat, waiting for their row or on their way to it; `done` lets them go (at once). */
let flying: { done(): void } | null = null;
/** Whether words sent from a composer are waiting for their row or on their way to it (the outbox's row coming now is theirs). */
export const sendingNow = (): boolean => flying !== null;

/** Told once the row of what the reader just sent is in its chat's list (or it will not be): `sendingHere` waits for it. */
const rowIn: (() => void)[] = [];
let rowAwaited = false;
const rowCame = () => { rowAwaited = false; for (const then of rowIn.splice(0)) then(); };
/** Calls `then` once the row of what the reader just sent is in its chat's list (in the frame it comes, before it is
 *  painted), or now if none is awaited. */
export function whenRowIn(then: () => void): () => void {
  if (!rowAwaited) { then(); return () => {}; }
  rowIn.push(then);
  return () => { const i = rowIn.indexOf(then); if (i >= 0) rowIn.splice(i, 1); };
}

/**
 * A message is sent in an open chat from `field` (a composer's text box, still showing `text`) into `list` (the chat's
 * list): its words stay where they were typed, drawn in `layer` (over the composer, at `z`), its hint gone, until this
 * device's own row for it is in the list (the outbox's, or the station's message itself when it is quick). Then that row is drawn from there to its place, over what it
 * passes, its words from the size they were typed at to their own, its bubble's ground and its time coming in on the
 * way; where it goes is read again every frame (the list may move as it settles), and the list itself does not move.
 * The row itself, hidden meanwhile, is shown again as the copy of it goes, in the same frame. The images going with it
 * fly the same way, each from its thumbnail in the composer to its place in the row (the thumbnail's crop opening out
 * to the image's own proportions); sent with no words, they fly on their own and the row comes in where it is. With no
 * row within a while (it could not be sent), the words are the composer's again.
 */
export function sendingHere(field: HTMLElement, text: string, { layer, z, list }: { layer: HTMLElement; z: string; list: HTMLElement }): void {
  flying?.done();
  const composer = field.closest("[data-made-composer]") ?? field;
  const stand = standIn(field, text, layer, z);
  const pictures = picturesIn(composer, layer, z);
  if (!stand && !pictures.length) return;
  const mine = `.${msgCss.msgMine}`;
  // Which of the viewer's rows is this message's, by what the chat had when it was sent (`sentAfter`, on the list): an
  // outbox entry it did not have, or a message after its last (or, short of the chat's end, the one an entry it took
  // became). Not "any row not drawn before": rows of the viewer's older messages are made too as the list goes to its end
  // or grows taller, and the words would fly to them.
  const { lastSeq, outbox } = list.dataset;
  const after = lastSeq === undefined || lastSeq === "" ? null : Number(lastSeq);
  const queued = new Set(outbox?.split(" "));
  const sent = (el: HTMLElement) => {
    const key = el.dataset.vk ?? "";
    if (key.startsWith("o:")) return !queued.has(key.slice(2));
    if (!key.startsWith("m:")) return false;
    if (el.dataset.outgoing && rows.some((r) => r.dataset.vk === `o:${el.dataset.outgoing}`)) return true;
    return after !== null && Number(key.slice(2)) > after;
  };
  const from = textAt(field);
  field.dataset.madeField = "";
  // Only words pass over the hint; images alone leave it where it is.
  // On the field, not the page's root: a mark there has every element's style worked out anew (a long chat's, at once).
  if (stand) field.dataset.madeHint = "hidden";
  field.dataset.sent = "";
  // The rows it went into (the outbox's, then the message that takes its place): hidden while their copy is on its way,
  // and never easing in by themselves.
  const rows: HTMLElement[] = [];
  const take = () => {
    for (const el of list.querySelectorAll<HTMLElement>(mine)) {
      if (rows.includes(el) || !sent(el)) continue;
      el.style.animation = "none";
      // Hide the row and its delayed status together, without changing opacity: the chat's emphasis transition
      // would otherwise fade the real row back in after its flying copy has already gone.
      el.dataset.sendCovered = "";
      // Waiting its turn (listQueue.ts), it takes no room yet.
      if (!begun) el.dataset.queued = "";
      rows.push(el);
    }
    return rows.findLast((el) => el.isConnected) ?? null;
  };
  let ghost: HTMLElement | null = null;
  let copy: HTMLElement | null = null;
  let of: HTMLElement | null = null;
  let ground = "";
  /** Where the copy was set down (in the layer), its width: from there it is only moved (a transform), not laid out anew. */
  let set: { left: number; top: number; width: number } | null = null;
  let clock: Animation | null = null;
  let frame = 0;
  let over = false;
  const done = () => {
    if (over) return;
    over = true;
    if (flying?.done === done) {
      flying = null;
      rowCame();
    }
    // Over: its turn ends once the list is where it moved it to; given up before it came, it is taken out.
    if (turn) landed();
    else out();
    observer.disconnect();
    clearTimeout(timeout);
    cancelAnimationFrame(frame);
    clock?.cancel();
    ghost?.remove();
    stand?.remove();
    for (const picture of pictures) picture.stand.remove();
    for (const el of rows) { delete el.dataset.sendCovered; delete el.dataset.queued; }
    delete field.dataset.madeHint;
    // The hint eases back (data-sent), then the field is as it was.
    setTimeout(() => {
      if (flying) return;
      delete field.dataset.madeField;
      delete field.dataset.sent;
    }, motionMs(200));
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
      if (copy) copy.replaceWith(next); else ghost.append(next);
      copy = next;
      set = null;
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
    // Set down once where the row is (again only if its width changes); followed from there by a transform alone, on a
    // layer of its own: moving it each frame lays nothing out and draws nothing anew (a phone's frames go on that).
    if (!set || Math.abs(set.width - at.width) > 0.5) {
      set = { left: at.left - box.left, top: at.top - box.top, width: at.width };
      Object.assign(copy.style, { position: "absolute", left: `${set.left}px`, top: `${set.top}px`, width: `${set.width}px`, margin: "0", willChange: "transform" });
    }
    const dx = at.left - box.left - set.left, dy = at.top - box.top - set.top;
    if (words) {
      const to = textAt(words);
      const s = from.size / to.size + (1 - from.size / to.size) * up;
      Object.assign(copy.style, {
        transformOrigin: `${to.x - at.left}px ${to.y - at.top}px`,
        transform: `translate(${dx + (from.x - to.x) * (1 - across)}px, ${dy + (from.y - to.y) * (1 - up)}px) scale(${s})`,
      });
    } else copy.style.transform = `translate(${dx}px, ${dy}px)`;
    // Each image from its thumbnail to its place in the row as it is now: across and up as the words go, its box
    // growing from the thumbnail's to its own.
    for (const picture of pictures) {
      const target = row.querySelector<HTMLElement>(`[data-send-image="${picture.key}"]`);
      if (!target) continue;
      const end = landsAt(target, target.getBoundingClientRect(), picture.ratio);
      const a = picture.rect;
      if (!picture.stand.dataset.flying) {
        picture.stand.dataset.flying = "";
        corners(picture.stand, target);
      }
      // Its corners from the thumbnail's to the message's, and its box's ground, if it has one, coming in (the thumbnail
      // has none): landed, it is as the message draws it.
      const style = getComputedStyle(target);
      picture.ground ??= style.backgroundColor;
      const radius = parseFloat(style.borderTopLeftRadius) || 0;
      Object.assign(picture.stand.style, {
        left: `${a.left + (end.left - a.left) * across - box.left}px`, top: `${a.top + (end.top - a.top) * up - box.top}px`,
        width: `${a.width + (end.width - a.width) * up}px`, height: `${a.height + (end.height - a.height) * up}px`,
        borderRadius: `${picture.radius + (radius - picture.radius) * up}px`,
        backgroundColor: `color-mix(in srgb, ${picture.ground} ${up * 100}%, transparent)`,
      });
    }
    const bubble = copy.querySelector<HTMLElement>(`.${conversationCss.msgBubble}`);
    if (bubble && ground) bubble.style.backgroundColor = `color-mix(in srgb, ${ground} ${e * 100}%, transparent)`;
    // (Its own delay kept: "sending" shows when the row's does.)
    for (const el of copy.querySelectorAll<HTMLElement>(`.${conversationCss.msgTime}`)) el.style.opacity = `${e}`;
    // Out of the composer (its top edge as it is now): its hint comes back.
    if (words && field.dataset.madeHint && copy.getBoundingClientRect().bottom <= composer.getBoundingClientRect().top) delete field.dataset.madeHint;
  };
  const tick = () => { place(); frame = requestAnimationFrame(tick); };
  // Its turn among what changes the list's height (listQueue.ts), asked as it is sent (what comes after it, the agent
  // starting on it, waits for it): the words wait in the composer till then, its row taking no room. Its turn come
  // before its row, it waits for the row. Over once it has landed.
  let begun = false;
  let turn = false;
  let landed: () => void = () => {};
  let out: () => void = () => {};
  // The row comes as the list is drawn anew: in its turn, its copy takes the words' place before the frame is painted.
  const start = () => {
    const row = take();
    if (!row || !turn || begun) return;
    clearTimeout(timeout);
    begun = true;
    for (const el of rows) delete el.dataset.queued;
    begin();
  };
  const begin = () => {
    const row = take();
    if (!row || ghost) { done(); return; }
    rowCame();
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
    // Under the row's copy: where they cross the words on the way, the words stay readable.
    for (const picture of pictures) ghost.append(picture.stand);
    // The one timeline all of it follows (what it moves is read anew each frame): paused and stepped, so is it.
    clock = play(ghost, [{ opacity: 1 }, { opacity: 1 }], { duration: ARRIVE, easing: "linear" });
    place();
    frame = requestAnimationFrame(tick);
    void clock.finished.then(done, () => {});
  };
  const observer = new MutationObserver(() => { if (begun) take(); else start(); });
  observer.observe(list, { childList: true, subtree: true });
  const timeout = setTimeout(done, WAIT_FOR_ROW);
  flying = { done };
  rowAwaited = true;
  out = listQueue(list).take(() => new Promise<void>((resolve) => {
    landed = resolve;
    turn = true;
    start();
  }));
}
