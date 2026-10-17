// The chat's composer (web/src/mobile/ChatHost.tsx, and ../Chat.tsx's useComposerText and ComposerExtras): what is being
// written (each chat's own draft, kept on the device: web/src/draft.ts), the quotes and files going with it, `@` and a
// few letters naming another chat of the station (web/src/ChatRef.tsx), and the bar. An archived chat's composer says
// so and restores it (web/src/ArchiveNotice.tsx).
//
// What Compose keeps as snapshot state (mutableStateOf) here tells whoever watches (`useDraftWatch`): a Draft, its files
// and quotes draw again whatever reads them as they change.
import * as LegacyFS from "expo-file-system/legacy";
import { Fragment, useEffect, useLayoutEffect, useMemo, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { Image, Linking, PixelRatio, Pressable, ScrollView, Text, TextInput, View, type LayoutChangeEvent, type StyleProp, type TextLayoutEventData, type ViewStyle } from "react-native";
import Animated, { makeMutable, runOnJS, useAnimatedStyle, useReducedMotion, withTiming, type SharedValue } from "react-native-reanimated";
import { core, useTopic } from "../../../../web/src/core/react.ts";
import { CoreError } from "../../../../web/src/core/client.ts";
import type { Attachment, ChatItem, ChatSearchView, ChatView, ComposerLink, DraftView, Quote } from "../../../../web/src/core/shapes.ts";
import { useDoing } from "../../../../web/src/doing.ts";
import { app as theApp, type AppState, type ChatOf } from "../AppState";
import { APP_NAME } from "../build";
import { errorText, fromBase64, type ByteSource, type OutsideRef } from "../data/Calls";
import { Topics } from "../data/Topics";
import { t } from "../i18n";
import { Button, fileSize } from "../ui/Controls";
import { chatInk } from "../ui/ChatInk";
import { ComposerCorner, ComposerFilesIn, ComposerInset, Floating, InComposer, InComposerFiles } from "../ui/Glass";
import { Icon, Icons } from "../ui/Icon";
import { Ease } from "../ui/Motion";
import { MakerIcon } from "../ui/Parts";
import { SheetGrab, SheetHead } from "../ui/Sheet";
import { concentric, Smooth, smoothMiddle } from "../ui/Smooth";
import { sp, T } from "../ui/Text";
import { lerpColor, raised, useC, withAlpha } from "../ui/Theme";
import { BusyIcon, Spinner, WaitLine } from "../ui/Waiting";
import { openAttach, AttachLaunchers } from "./Attach";
import { quoteLine, type AgentHere } from "./Chat";
import { FileData, FileCard, isImage, type Picture } from "./ChatFiles";
import { SendTile, type ComposerSpec, type Host } from "./ChatHost";
import { encodeComponent, insertedRange, linkedRefs, type LinkedChat, type RefMatch } from "./ChatLink";
import { FilePreview, FileViewers, ForgetThumb, ViewerThumb } from "./FilePreview";
import { PASTE_THRESHOLD, PastedText, pastedPicked } from "./PastedText";
import { SendTextStyle } from "./SendText";
import { StationTag } from "./Stations";
import { openRefSheet, openStationFiles, pathWords, RefCard, type RefFile } from "./StationFiles";


// ── watching what changes ────────────────────────────────────────────────

const watchers = new Set<() => void>();
let tick = 0;
/** Something a composer shows changed: whoever watches draws again. */
function changed() {
  tick++;
  for (const w of watchers) w();
}
const watch = (l: () => void) => { watchers.add(l); return () => { watchers.delete(l); }; };
/** Draws the caller again whenever a draft, a file of one or a quote of one changes (Compose's snapshot reads). */
export function useDraftWatch(): number {
  return useSyncExternalStore(watch, () => tick);
}

/** System.nanoTime(): ever larger, never the same twice. */
let lastNano = 0;
export function nanoTime(): number {
  lastNano = Math.max(lastNano + 1, Math.floor(performance.now() * 1e6));
  return lastNano;
}

/** A list Compose watches (mutableStateListOf): what changes it tells the composer's watchers. */
export class StateList<T> implements Iterable<T> {
  #items: T[] = [];
  get length() { return this.#items.length; }
  [Symbol.iterator]() { return this.#items[Symbol.iterator](); }
  toList(): T[] { return this.#items.slice(); }
  at(i: number): T | undefined { return this.#items[i]; }
  push(...xs: T[]) { if (xs.length) { this.#items = [...this.#items, ...xs]; changed(); } }
  addAll(xs: Iterable<T>) { this.push(...xs); }
  remove(x: T) { const i = this.#items.indexOf(x); if (i >= 0) { this.#items = this.#items.filter((_, j) => j !== i); changed(); } return i >= 0; }
  clear() { if (this.#items.length) { this.#items = []; changed(); } }
  isEmpty() { return this.#items.length === 0; }
  isNotEmpty() { return this.#items.length > 0; }
  map<U>(f: (x: T, i: number) => U): U[] { return this.#items.map(f); }
  filter(f: (x: T) => boolean): T[] { return this.#items.filter(f); }
  some(f: (x: T) => boolean): boolean { return this.#items.some(f); }
  forEach(f: (x: T) => void) { this.#items.forEach(f); }
  find(f: (x: T) => boolean): T | undefined { return this.#items.find(f); }
}

// ── the draft ──────────────────────────────────────────────────────────

/**
 * A file on its way to the station: uploading, uploaded, or failed. `local`: a picture's bytes as picked (one read
 * whole), what the viewer shows it from before it is sent (no session keeps it yet), with its size. `pasted`: the text
 * it was made of, pasted (PastedText.tsx). `preview`: where its picture is read from (a picked image's own file).
 */
export class Pending {
  #done: Attachment | null = null;
  #sent: number | null = null;
  #error: string | null = null;
  constructor(
    readonly id: number, readonly name: string, readonly size: number, readonly preview: string | null,
    readonly local: Uint8Array | null = null, readonly width: number | null = null, readonly height: number | null = null,
    readonly pasted: PastedText | null = null, readonly ref: RefFile | null = null, readonly link: ComposerLink | null = null,
  ) {}
  get done() { return this.#done; }
  set done(v: Attachment | null) { this.#done = v; changed(); }
  /** How much of it the station has, as it goes up in parts. */
  get sent() { return this.#sent; }
  set sent(v: number | null) { this.#sent = v; changed(); }
  get error() { return this.#error; }
  set error(v: string | null) { this.#error = v; changed(); }
  /** A file of a station's named by its path (StationFiles.tsx), or a link shared in (share/): it goes as words, nothing goes up. */
  get named(): boolean { return this.ref?.mode === "path" || this.link != null; }
}

/** A passage quoted in the message being written, with what is said about it. */
export class DraftQuote {
  #comment = "";
  constructor(readonly id: number, readonly author: string, readonly text: string, readonly ts: string | null, readonly role: string, readonly file: string | null = null) {}
  get comment() { return this.#comment; }
  set comment(v: string) { this.#comment = v; changed(); }
  sent(): Quote {
    return { author: this.author, text: this.text, comment: this.comment.trim(), ...(this.ts != null ? { ts: this.ts } : {}), role: this.role, ...(this.file != null ? { file: this.file } : {}) };
  }
}

/** Where the cursor is in the text (TextRange there): `start` to `end`, the same when collapsed. */
export interface Selection { start: number; end: number }
/** The text and where the cursor is (TextFieldValue there). */
export interface FieldValue { text: string; selection: Selection }

/**
 * What is being written: text (with where the cursor is), quotes, files. A chat's draft is its own (Drafts): leaving the
 * chat, or the app, keeps it for when the chat is opened again; a new chat's lives while its page does.
 */
export class Draft {
  #text = "";
  #selection: Selection = { start: 0, end: 0 };
  /** Where the app put the cursor, until the field has it (a field's own moves are not told back to it). */
  placed: Selection | null = null;
  readonly quotes = new StateList<DraftQuote>();
  readonly files = new StateList<Pending>();
  #starting = false;
  /** What it refers to is being looked at before it goes (sendSharing): a second tap of send does nothing meanwhile. */
  checking = false;
  #error: string | null = null;
  #focusQuote: number | null = null;
  #focus = 0;
  warmed = 0;
  #locked = false;
  #focused = false;
  #refClosed: number | null = null;

  /** The key it is kept on the device by (Drafts); null: not kept. */
  keptAs: string | null = null;
  /** What the core kept of it has been read: only then is it kept as it is (not written over before). */
  loaded = false;

  /** Its text and where the cursor is; set, both are replaced. */
  get input(): FieldValue { return { text: this.#text, selection: this.#selection }; }
  set input(value: FieldValue) {
    this.#text = value.text;
    this.#selection = value.selection;
    this.placed = value.selection;
    changed();
  }
  /** The text; set, the cursor goes to its end. */
  get text(): string { return this.#text; }
  set text(value: string) { this.input = { text: value, selection: { start: value.length, end: value.length } }; }
  /** What the field says it holds now (typed), and where its cursor is: told by the field itself, not put there. */
  typed(text: string) { if (text !== this.#text) { this.#text = text; changed(); } }
  get selection(): Selection { return this.#selection; }
  set selection(s: Selection) {
    if (s.start === this.#selection.start && s.end === this.#selection.end) return;
    this.#selection = s;
    if (this.placed && this.placed.start === s.start && this.placed.end === s.end) this.placed = null;
    changed();
  }

  /** A new chat is being made for the first message. */
  get starting() { return this.#starting; }
  set starting(v: boolean) { this.#starting = v; changed(); }
  get error() { return this.#error; }
  set error(v: string | null) { this.#error = v; changed(); }
  /** The quote whose comment line takes the focus. */
  get focusQuote() { return this.#focusQuote; }
  set focusQuote(v: number | null) { this.#focusQuote = v; changed(); }
  /** Bumped to put the cursor in the text. */
  get focus() { return this.#focus; }
  set focus(v: number) { this.#focus = v; changed(); }
  get uploading(): boolean { return this.files.some((f) => f.done == null && f.error == null && !f.named); }
  /** Nothing can be sent (its station is offline, or the chat archived). */
  get locked() { return this.#locked; }
  set locked(v: boolean) { if (v !== this.#locked) { this.#locked = v; changed(); } }
  get ready(): boolean {
    return (this.text.trim() !== "" || this.files.some((f) => f.done != null || f.named) || this.quotes.isNotEmpty()) && !this.uploading && !this.starting && !this.locked;
  }
  /** The text box has the focus (the menu of chats shows only then). */
  get focused() { return this.#focused; }
  set focused(v: boolean) { if (v !== this.#focused) { this.#focused = v; changed(); } }
  /** Where an `@` was put away (its menu closed by picking a chat): not offered again. */
  get refClosed() { return this.#refClosed; }
  set refClosed(v: number | null) { if (v !== this.#refClosed) { this.#refClosed = v; changed(); } }

  /** Keeps it on the device as it is now (a chat's draft). */
  save() { const k = this.keptAs; if (k != null && this.loaded) Drafts.save(k, this); }

  fill(kept: DraftView) {
    this.text = kept.text;
    for (const q of kept.quotes) { const d = new DraftQuote(nanoTime(), q.author, q.text, q.ts ?? null, q.role ?? "person", q.file ?? null); d.comment = q.comment; this.quotes.push(d); }
    for (const a of kept.files) { const p = new Pending(nanoTime(), a.name, a.size, null, null, a.width ?? null, a.height ?? null); p.done = a; this.files.push(p); }
    for (const l of kept.links ?? []) this.files.push(linkPending(l));
  }

  /**
   * What the core holds of it now, in place of what was kept (something shared into it while it was open: the core
   * put it there, share/ShareActivity.kt); files still going up stay.
   */
  replace(kept: DraftView) {
    const going = this.files.filter((f) => f.done == null && f.error == null && !f.named);
    this.quotes.clear(); this.files.clear();
    this.fill(kept);
    this.files.addAll(going);
  }
  get empty(): boolean { return this.text === "" && this.quotes.isEmpty() && this.files.isEmpty(); }

  quote(author: string, text: string, ts: string | null, role: string) {
    const q = new DraftQuote(nanoTime(), author, text, ts, role);
    this.quotes.push(q);
    this.focusQuote = q.id;
  }

  /** Empties it, for what is sent: the text (its references' marks, which the core makes links) with where each file
   *  named by its path is (StationFiles.tsx), the files up, the quotes. */
  take(): Taken {
    const named = this.files.filter((f) => f.named);
    // After the text: each link (its title on a line, then it), then where each file named by its path is (as the core's composer.take).
    const links = named.flatMap((f) => (f.link ? [[f.link.title ? f.link.title : null, f.link.url].filter((x): x is string => x != null).join("\n")] : []));
    const words = [this.text.trim(), ...links, ...named.flatMap((f) => (f.ref ? [pathWords(f.ref)] : []))].filter((w) => w !== "").join("\n");
    const taken = new Taken(words, this.files.filter((f) => !f.named), this.quotes.toList(), this.text, named);
    this.text = ""; this.files.clear(); this.quotes.clear(); this.error = null; this.refClosed = null;
    this.save();
    return taken;
  }

  /** Puts back what `take` took (sending it failed). */
  restore(t: Taken) { this.text = t.written; this.files.addAll([...t.named, ...t.files]); this.quotes.addAll(t.quotes); this.save(); }

  /** Whether the composer shows its bigger layout: the field over its buttons (composerExpanded there). */
  get composerExpanded(): boolean { return composerExpanded(this); }
}

/** What a draft held when it was sent: `text` as it goes (trimmed), `written` as it was typed. */
export class Taken {
  constructor(readonly text: string, readonly files: Pending[], readonly quotes: DraftQuote[], readonly written: string, readonly named: Pending[] = []) {}
}

/**
 * Each chat's draft, by its station's address and the chat ("<address>:<chat>", or "new:<address>" for a new chat
 * there, as the web keys it): the same one while the app runs (files still going up go on); what it holds (the text,
 * the quotes with what is said about them, the files already up; the station keeps those in no chat until a message
 * takes them) the core keeps on the device (its `draft` topic, `draft.put`), as it does for the web.
 *
 * The Android app moved drafts and chats' links it kept itself before the core did ("drafts", "chatRefs" preferences)
 * into the core; this app never kept any, so there is nothing to move.
 */
export const Drafts = {
  open: new Map<string, Draft>(),

  of(key: string): Draft {
    const had = this.open.get(key);
    if (had) return had;
    const d = new Draft();
    d.keptAs = key;
    this.open.set(key, d);
    void (async () => {
      // A core that keeps none (or refuses the key): nothing kept.
      const kept = await readKept(key);
      // Written here meanwhile: that is what is kept now.
      if (kept != null && d.empty) d.fill(kept);
      d.loaded = true;
      if (!d.empty) d.save();
    })();
    return d;
  },

  /** Something was put in `key`'s draft by the core (shared into it, share/): an open one takes what the core has now. */
  refresh(key: string) {
    const d = this.open.get(key);
    if (!d) return;
    void readKept(key).then((kept) => { if (kept != null) d.replace(kept); });
  },

  save(key: string, d: Draft) {
    const view: DraftView = {
      text: d.text,
      quotes: d.quotes.map((q) => ({ ...q.sent(), comment: q.comment })),
      files: d.files.toList().flatMap((f) => (f.done ? [f.done] : [])),
      links: d.files.toList().flatMap((f) => (f.link ? [f.link] : [])),
    };
    // A core that refuses it keeps nothing: the draft lives while the app does.
    core().call("draft.put", { key, ...view }).catch(() => undefined);
  },
};

async function readKept(key: string): Promise<DraftView | null> {
  try {
    const v = await core().call("draft.get", { key });
    return v != null && typeof v === "object" && typeof (v as DraftView).text === "string" ? (v as DraftView) : null;
  } catch {
    return null;
  }
}

/** A chat's draft key: "<station>:<its key>", or "<station>:thread:<id>". */
const draftKey = (station: string, of: ChatOf) => `${station}:` + ("session" in of ? of.session : `thread:${of.thread}`);

/**
 * The draft kept by `key` (Drafts): a chat's (`rememberDraft(station, of)`), or a new chat's on a station
 * ("new:<address>", as the web keys it). Kept on the device as it changes (the core writes it down a moment after) and
 * when the page goes. A hook.
 */
export function rememberDraft(stationOrKey: string, of?: ChatOf): Draft {
  const key = of ? draftKey(stationOrKey, of) : stationOrKey;
  const draft = useMemo(() => Drafts.of(key), [key]);
  useEffect(() => {
    const sig = () => JSON.stringify([draft.text, draft.quotes.map((q) => [q.id, q.comment]), draft.files.map((f) => [f.id, f.done?.path ?? null])]);
    let last = sig();
    const off = watch(() => { const now = sig(); if (now !== last) { last = now; draft.save(); } });
    return () => { off(); draft.save(); };
  }, [draft]);
  return draft;
}
export const useDraft = rememberDraft;

// ── references to other chats (web/src/chatRefs.ts, ChatRef.tsx) ───────────

/**
 * References to other chats in what is written: in the composer a short mark, `@[its title]`, drawn in the accent; sent,
 * a link, `[its title](<cloud>/w/<workspace>/s/<station>/chats/<key>)`, which the agent reads the chat by and a message
 * draws as a chip. The core makes the mark of a chat picked and keeps its link until the mark is sent (`chat.ref`,
 * client/core-ts/src/refs.ts).
 */
export const ChatRefs = {
  MARK: /@\[([^\]\n]{1,120})\]/,

  /** The `@words` the caret is at the end of, and where the `@` is; null when it is not in one. */
  at(text: string, caret: number): [number, string] | null {
    const m = /(?:^|\s)@([^\s@[\]()]{0,40})$/.exec(text.substring(0, Math.min(Math.max(caret, 0), text.length)));
    if (!m) return null;
    const query = m[1]!;
    return [caret - query.length - 1, query];
  },

  /** The mark just before `caret` (a backspace there takes it whole), or null. */
  before(text: string, caret: number): number | null {
    const m = /@\[[^\]\n]{1,120}\]$/.exec(text.substring(0, caret));
    return m ? m.index : null;
  },
};

/**
 * The composer's text with each mark drawn in the accent, both brackets unseen (RefMarks there, an output
 * transformation). The field shows its own letters, in their order: the `[` after the `@` (before it there, swapped)
 * is drawn a hair wide, so the title follows the `@` as it does there.
 */
function refMarks(text: string, accent: string): ReactNode[] {
  const out: ReactNode[] = [];
  let at = 0;
  for (const m of text.matchAll(new RegExp(ChatRefs.MARK.source, "g"))) {
    const s = m.index ?? 0;
    if (s > at) out.push(text.slice(at, s));
    out.push(
      <Fragment key={s}>
        <Text style={{ color: accent }}>@</Text>
        <Text style={{ color: "transparent", fontSize: 1 }}>[</Text>
        <Text style={{ color: accent }}>{m[1]}</Text>
        <Text style={{ color: "transparent" }}>]</Text>
      </Fragment>,
    );
    at = s + m[0].length;
  }
  if (at < text.length) out.push(text.slice(at));
  return out;
}

/**
 * Puts each chat's link pasted in `pasted` (`linkedRefs`) as its mark, the core keeping its link as for one picked with
 * `@` (a link to its agent's execution history kept as that link); one the core cannot make a mark of stays as it is.
 * Written on meanwhile: each link where it is now, if it still is.
 */
async function markPasted(draft: Draft, pasted: string, refs: [RefMatch, LinkedChat][]) {
  const made = await Promise.all(refs.map(async ([m, chat]) => {
    try {
      const told = await core().call("chat.ref", { station: chat.station, id: chat.id, title: m.groupValues[1], base: theApp.cloudOrigin }) as { mark?: string } | null;
      const mark = told?.mark ?? m.value;
      if (chat.history !== "" && mark !== m.value) {
        const at = chat.station.indexOf("/");
        const page = `${theApp.cloudOrigin.replace(/\/+$/, "")}/w/${chat.station.substring(0, at)}/s/${chat.station.substring(at + 1)}/chats/${encodeComponent(chat.id)}${chat.history}`;
        await core().call("chat.refs", { links: [[mark.substring(2, mark.length - 1), page]] });
      }
      return mark;
    } catch {
      return m.value;
    }
  }));
  const now = draft.input;
  let text = now.text;
  let caret = now.selection.start;
  // Last first, so the places of those before stay as they are.
  for (let i = refs.length - 1; i >= 0; i--) {
    const m = refs[i]![0];
    const at = now.text === pasted ? m.range.first : text.indexOf(m.value);
    if (at < 0) continue;
    text = text.substring(0, at) + made[i] + text.substring(at + m.value.length);
    if (caret >= at + m.value.length) caret += made[i]!.length - m.value.length;
  }
  if (text !== now.text) { const c = Math.min(Math.max(caret, 0), text.length); draft.input = { text, selection: { start: c, end: c } }; }
}

/** The address's workspace (the scope of its chats' list). */
const scopeOf = (address: string) => address.split("/")[0]!;

/**
 * `@` and a few letters in the text: the chats of this station it finds (another station's agents cannot read them,
 * the core's `chatSearch`), titles first, but not `here` (the chat written in); then those of the viewer's other
 * workspaces (`elsewhere`), each with its workspace's name after its title, as a tag (sent, one is shared with this
 * workspace first: sendSharing). The one picked goes in as the mark the core makes of it. Over the composer, in its glass.
 */
export function ChatRefMenu({ draft, station, here, style }: { draft: Draft; station: string; here: string | null; haze?: unknown; style?: StyleProp<ViewStyle> }) {
  useDraftWatch();
  const C = useC();
  const field = draft.input;
  const collapsed = field.selection.start === field.selection.end;
  const found = collapsed && draft.focused && !draft.locked ? ChatRefs.at(field.text, field.selection.start) : null;
  const ref = found && found[0] !== draft.refClosed ? found : null;
  useEffect(() => { if (found == null && draft.refClosed != null) draft.refClosed = null; });
  const search = useTopic<ChatSearchView>(ref ? Topics.chatSearch(scopeOf(station), ref[1], station, here, 8, null, true) : null);
  if (ref == null) return null;
  const [start, query] = ref;
  const items = search.value?.items ?? [];
  const pick = (item: ChatItem) => {
    const caret = field.selection.start;
    draft.refClosed = start;
    void (async () => {
      // Its mark, from the core, which keeps its link until it is sent; in its place if the `@words` are still there.
      let mark: string | undefined;
      try {
        mark = (await core().call("chat.ref", { station: item.station, id: item.id, title: item.title, base: theApp.cloudOrigin, into: scopeOf(station) }) as { mark?: string } | null)?.mark;
      } catch (e) {
        theApp.toast = t("android-chat.ref.failed", { error: errorOf(e) });
        return;
      }
      if (mark == null) return;
      const now = draft.input.text;
      if (now.charAt(start) !== "@" || caret > now.length) return;
      const c = start + mark.length + 1;
      draft.input = { text: now.substring(0, start) + mark + " " + now.substring(caret), selection: { start: c, end: c } };
    })();
  };
  const line = { paddingLeft: 12, paddingRight: 12, paddingTop: 6, paddingBottom: 4 } as const;
  let body: ReactNode;
  if (search.value == null && search.error != null) body = <T size={15} color={C.muted} style={line}>{t("android-chat.ref.update", { app: APP_NAME })}</T>;
  else if (search.value == null) body = <View style={line}><WaitLine text={t("common.reading")} /></View>;
  else if (items.length === 0) body = <T size={15} color={C.muted} style={line}>{query !== "" ? t("android-chat.ref.none.match") : t("android-chat.ref.none")}</T>;
  else body = items.map((item) => (
    <Smooth key={`${item.station}/${item.id}`} radius={20}>
      <Pressable
        onPress={() => pick(item)} android_ripple={{ color: withAlpha(C.ink, 0.12), borderless: false }}
        style={{ width: "100%", minHeight: 44, paddingHorizontal: 12, paddingVertical: 8, flexDirection: "row", alignItems: "center", gap: 10 }}
      >
        <View style={{ width: 16, alignItems: "center", justifyContent: "center" }}>
          {item.agents[0] && <MakerIcon maker={item.agents[0].maker ?? null} runtime={item.agents[0].runtime} size={14} />}
        </View>
        {/* Another workspace's: its name right after the title (cut short first), as a tag. */}
        <View style={{ flex: 1, minWidth: 0, flexDirection: "row", alignItems: "center", gap: 6 }}>
          <T size={15} color={C.ink} numberOfLines={1} ellipsizeMode="tail" style={{ flexShrink: 1 }}>{item.title}</T>
          {item.outside != null && <StationTag name={item.outside} emoji={null} icon={null} />}
        </View>
        {item.time?.["lastActiveAt"] && <T size={13} color={C.muted} numberOfLines={1}>{item.time["lastActiveAt"].ago}</T>}
      </Pressable>
    </Smooth>
  ));
  return (
    <View style={[{ width: "100%", paddingBottom: 8 }, style]}>
      <Floating radius={ComposerCorner} style={{ maxHeight: 320 }}>
        <ScrollView style={{ flexGrow: 0 }} contentContainerStyle={{ padding: 12 }} keyboardShouldPersistTaps="always">
          <View style={{ paddingLeft: 12, paddingRight: 12, paddingBottom: 6, flexDirection: "row", gap: 6 }}>
            <T size={13} color={C.muted}>{t("android-chat.ref.title")}</T>
            {query !== "" && <T size={13} color={C.ink}>{query}</T>}
          </View>
          {body}
        </ScrollView>
      </Floating>
    </View>
  );
}

// ── sharing what is referred to (docs/chat-share.md) ─────────────────────

/**
 * Sends what `draft` holds by `send`, written on `station`, once this workspace's agents can read what it refers to:
 * the chats of the viewer's other workspaces its marks name that are not shared with this one yet (the core's
 * `chat.outsideRefs`). With none, it goes at once; else a sheet says which first (as the phone's web does).
 */
export function sendSharing(app: AppState, draft: Draft, station: string, send: () => void) {
  const text = draft.text.trim();
  // No mark, nothing referred to: no need to ask.
  if (!ChatRefs.MARK.test(text)) { send(); return; }
  if (draft.checking) return;
  draft.checking = true;
  void (async () => {
    // A core that cannot say (one before sharing) leaves it as before: sent as it is.
    let outside: OutsideRef[];
    try { outside = await app.api(station).outsideRefs(text); } catch { outside = []; }
    draft.checking = false;
    if (outside.length === 0) send(); else askToShare(app, draft, station, outside, send);
  })();
}

/**
 * Which chats of other workspaces this workspace's agents will read once it is sent, each saying whose; those the
 * viewer may not share (neither its starter nor an owner or admin there) say so. 分享并发送 shares those they may with
 * this workspace (`chat.xshareAdd`, its station told first; the button turning meanwhile, as the phone's web does), then
 * closes the sheet and sends; a share failing is said in the sheet, and nothing is sent (the draft stays). With none they
 * may share, 仍然发送 sends it as it is. 取消 leaves the draft as it was.
 */
function askToShare(app: AppState, _draft: Draft, station: string, chats: OutsideRef[], send: () => void) {
  const rows = chats.reduce((n, c) => n + (c.may ? 34 : 54), 0);
  app.sheet = { height: 0.5, fit: 22 + 48 + 30 + rows + 16 + 38 + 24, content: () => <AskToShare app={app} station={station} chats={chats} send={send} /> };
}

function AskToShare({ app, station, chats, send }: { app: AppState; station: string; chats: OutsideRef[]; send: () => void }) {
  const C = useC();
  const may = chats.filter((c) => c.may);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("web-main.outside.title")} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 20 }}>
        <T size={14} line={20} color={C.muted} style={{ paddingBottom: 8 }}>{t("web-main.outside.lead")}</T>
        {/* Each as a reference shows (its title after `@`, in the accent), whose after it as the `@` menu says it. */}
        {chats.map((c) => (
          <View key={`${c.station}/${c.id}`} style={{ width: "100%", paddingVertical: 5 }}>
            <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
              <T size={15} line={22} color={C.accent} numberOfLines={1} ellipsizeMode="tail" style={{ flexShrink: 1 }}>
                <Text style={{ color: withAlpha(C.accent, 0.7) }}>@</Text>{c.title}
              </T>
              <StationTag name={t("web-main.outside.from", { name: c.workspaceName })} emoji={null} icon={null} />
            </View>
            {!c.may && <T size={13} line={18} color={C.red} style={{ paddingTop: 2 }}>{t("web-main.outside.cannot")}</T>}
          </View>
        ))}
        {error != null && <T size={13} line={18} color={C.red} style={{ paddingTop: 8 }}>{error}</T>}
        <View style={{ width: "100%", paddingTop: 16, paddingBottom: 24, flexDirection: "row", justifyContent: "flex-end", gap: 8 }}>
          <Button label={t("common.cancel")} primary={false} onClick={() => { app.sheet = null; }} />
          <Button
            label={t(may.length === 0 ? "web-main.outside.anyway" : "web-main.outside.share")} primary busy={busy}
            onClick={() => {
              if (busy) return;
              if (may.length === 0) { app.sheet = null; send(); return; }
              setBusy(true);
              setError(null);
              void (async () => {
                // All at once; each told on its own (one failing does not stop the rest).
                const failed = (await Promise.all(may.map(async (c) => {
                  try { await app.api(c.station).shareInto(c.id, scopeOf(station), station); return null; } catch (e) { return e; }
                }))).find((e) => e != null);
                setBusy(false);
                if (failed != null) setError(t("web-main.outside.failed", { error: errorOf(failed) }));
                else { app.sheet = null; send(); }
              })();
            }}
          />
        </View>
      </ScrollView>
    </>
  );
}

// ── files ──────────────────────────────────────────────────────────────

export const MAX_FILE = 1024 * 1024 * 1024;
/** A picked file up to this is read into memory (an image's preview and marks read it); a bigger one is read as it goes up. */
export const IN_MEMORY = 16 * 1024 * 1024;

/** A file that could not be read (an IOException there). */
export class ReadError extends Error {}

/** Bytes in memory read as they go (java.io.ByteArrayInputStream). */
export function bytesSource(bytes: Uint8Array): ByteSource {
  let at = 0;
  return {
    read: async (into, offset, length) => {
      if (at >= bytes.length) return -1;
      const n = Math.min(length, bytes.length - at);
      into.set(bytes.subarray(at, at + n), offset);
      at += n;
      return n;
    },
    skip: async (n) => { const k = Math.max(0, Math.min(n, bytes.length - at)); at += k; return k; },
    close: () => {},
  };
}

/**
 * A file where it is (`file://`, or a provider's `content://`) read as it goes (the ContentResolver's InputStream
 * there), through expo-file-system: each read the bytes from where the last one ended. `size`, when known, is where it
 * ends (a read past a file's end fails there, as it cannot say -1).
 */
export function uriSource(uri: string, size: number | null = null): ByteSource {
  let at = 0;
  return {
    read: async (into, offset, length) => {
      if (length <= 0) return 0;
      if (size != null && at >= size) return -1;
      const want = size != null ? Math.min(length, size - at) : length;
      let b: string;
      try {
        b = await LegacyFS.readAsStringAsync(uri, { encoding: LegacyFS.EncodingType.Base64, position: at, length: want });
      } catch (e) {
        // Past its end, its size not known: the end. Unreadable from its start: it cannot go.
        if (size == null && at > 0) return -1;
        throw new ReadError(e instanceof Error ? e.message : String(e));
      }
      const bytes = fromBase64(b);
      if (bytes.length === 0) return -1;
      into.set(bytes, offset);
      at += bytes.length;
      return bytes.length;
    },
    skip: async (n) => { const k = Math.max(0, size != null ? Math.min(n, size - at) : n); at += k; return k; },
    close: () => {},
  };
}

/**
 * A file picked on the phone; images also get their size and a preview (where it is read from). Up to [IN_MEMORY] it
 * is read whole (`bytes`); a bigger one is read from `open` as it goes up, a part at a time. `size` is the file's own:
 * one over MAX_FILE is neither (`bytes` empty, no `open`), and is refused.
 */
export class Picked {
  constructor(
    readonly name: string, readonly bytes: Uint8Array, readonly width: number | null, readonly height: number | null, readonly preview: string | null,
    readonly size: number = bytes.length, readonly open: (() => ByteSource) | null = null,
  ) {}
  /** Where its bytes are read from as it goes up. */
  source(): () => ByteSource { return this.open ?? (() => bytesSource(this.bytes)); }
}

/** An image's size as the system reads it from where it is; null for what is no image. */
function imageBounds(uri: string): Promise<{ width: number; height: number } | null> {
  return new Promise((resolve) => {
    Image.getSize(uri, (width, height) => resolve(width > 0 ? { width, height } : null), () => resolve(null));
  });
}

/** Up to `most` bytes of `input` (all of it when shorter). */
async function readUpTo(input: ByteSource, most: number): Promise<Uint8Array> {
  const chunks: Uint8Array[] = [];
  let got = 0;
  const buf = new Uint8Array(Math.min(4 * 1024 * 1024, Math.max(1, most)));
  while (got < most) {
    const n = await input.read(buf, 0, Math.min(buf.length, most - got));
    if (n < 0) break;
    chunks.push(buf.slice(0, n));
    got += n;
  }
  input.close();
  const out = new Uint8Array(got);
  let at = 0;
  for (const c of chunks) { out.set(c, at); at += c.length; }
  return out;
}

/**
 * Reads a file picked (`uri`; its `name` and `size` as the picker said them, as the provider's columns do there). Null
 * when it cannot be read.
 */
export async function readPicked(uri: string, name: string | null = null, size: number | null = null): Promise<Picked | null> {
  const shown = name ?? "file";
  let known: number | null = size;
  if (known == null) {
    try { const info = await LegacyFS.getInfoAsync(uri); if (info.exists && typeof info.size === "number") known = info.size; } catch { /* not said */ }
  }
  if (known != null && known > MAX_FILE) return new Picked(shown, new Uint8Array(0), null, null, null, known);
  // The provider may not say how big (or say wrong): read no further than one byte past IN_MEMORY into memory.
  let bytes: Uint8Array | null = null;
  if (!(known != null && known > IN_MEMORY)) {
    try { bytes = await readUpTo(uriSource(uri), IN_MEMORY + 1); } catch { return null; }
  }
  if (bytes != null && bytes.length <= IN_MEMORY) {
    const bounds = await imageBounds(uri);
    return new Picked(shown, bytes, bounds?.width ?? null, bounds?.height ?? null, bounds ? uri : null);
  }
  // Big: its size as read when the provider did not say (counted, not kept), its picture from a pass of its own.
  let total = known;
  if (total == null) {
    try {
      const input = uriSource(uri);
      const buf = new Uint8Array(1 << 22);
      let n = 0;
      for (;;) { const r = await input.read(buf, 0, buf.length); if (r < 0) break; n += r; if (n > MAX_FILE) break; }
      total = n;
    } catch { return null; }
  }
  if (total > MAX_FILE) return new Picked(shown, new Uint8Array(0), null, null, null, total);
  const bounds = await imageBounds(uri);
  const whole = total;
  return new Picked(shown, new Uint8Array(0), bounds?.width ?? null, bounds?.height ?? null, bounds ? uri : null, whole, () => uriSource(uri, whole));
}

/** The camera's photo (a JPEG at 90, as it was taken), as a file picked. */
export async function photoPicked(photo: { uri: string; width: number; height: number }): Promise<Picked | null> {
  try {
    const bytes = await readUpTo(uriSource(photo.uri), MAX_FILE + 1);
    return new Picked(`photo-${Date.now()}.jpg`, bytes, photo.width, photo.height, photo.uri);
  } catch {
    return null;
  }
}

/** Files go to the station as soon as they are added, and wait there in no chat: the message that sends them takes them
 * into its chat (a new chat is made only then). A chat's draft is kept once the file is up. (`scope`: what it goes up
 * in, the app's by default: it goes on whatever the page does.) */
export function upload(app: AppState, draft: Draft, station: string, picked: Picked, scope: AppState["scope"] = app.scope, pasted: PastedText | null = null) {
  const p = new Pending(nanoTime(), picked.name, picked.size, picked.preview, picked.preview != null && picked.bytes.length > 0 ? picked.bytes : null, picked.width, picked.height, pasted);
  draft.files.push(p);
  if (picked.size > MAX_FILE || (picked.bytes.length === 0 && picked.open == null && picked.size > 0)) { p.error = t("android-chat.file.tooBig"); return; }
  scope.launch(async () => {
    try {
      p.done = await app.api(station).upload(picked.name, picked.size, picked.source(), picked.width, picked.height, (s) => { p.sent = s; });
      const a = p.done;
      if (a && picked.preview) FileData.keepSent(station, a.path, { uri: picked.preview, width: picked.width ?? 0, height: picked.height ?? 0 });
      draft.save();
    } catch (e) {
      p.error = e instanceof CoreError ? e.message : t("android-chat.file.uploadFailed");
    }
  });
}

/** What a failure says (errorText there, for what the core refused; any other as it is). */
const errorOf = (e: unknown): string => (e instanceof CoreError ? errorText(e) : e instanceof Error ? e.message : String(e));

/** What a file going up says: how far it has gone, once that is known. */
export function uploadingText(f: Pending): string {
  const sent = f.sent;
  return sent == null || f.size <= 0 ? t("common.uploading") : t("android-chat.file.uploading.part", { percent: Math.floor((sent * 100) / f.size), size: fileSize(f.size) });
}

// ── the composer ───────────────────────────────────────────────────────

/**
 * What waits to go with the message, as the web's composer shows it (ComposerExtras): the quotes, each a card with a
 * line for a comment (the one just added takes the focus; its Enter goes back to the text), then the files (each kept
 * for `host`'s flight to take it from where it is, ChatHost.tsx).
 */
export function DraftExtras({ draft, host = null, station = host?.spec?.station ?? null, session = host?.spec?.here ?? null }: { draft: Draft; host?: Host | null; station?: string | null; session?: string | null }) {
  useDraftWatch();
  // As far from the capsule's edge as from its top (ComposerFilesIn), past its own room (ComposerInset).
  const beyond = ComposerFilesIn - ComposerInset;
  return (
    <>
      {draft.quotes.isNotEmpty() && (
        <ScrollView style={{ width: "100%", maxHeight: 176, flexGrow: 0 }} contentContainerStyle={{ gap: 6 }} keyboardShouldPersistTaps="always">
          {draft.quotes.map((q) => <DraftQuoteCard key={q.id} draft={draft} q={q} />)}
        </ScrollView>
      )}
      {/* A picture's remove button sits over its corner (PictureRemoveOut beyond it): the gap after it room for that too.
          Its room above the pictures is inside the strip (a strip here clips what goes past it), the strip as high as there. */}
      {draft.files.isNotEmpty() && (
        <ScrollView
          horizontal showsHorizontalScrollIndicator={false} keyboardShouldPersistTaps="always" style={{ flexGrow: 0, marginTop: -PictureRemoveOut }}
          contentContainerStyle={{ paddingLeft: beyond, paddingRight: beyond + PictureRemoveOut, paddingTop: beyond + PictureRemoveOut, gap: 6 + PictureRemoveOut }}
        >
          {draft.files.map((f) => <DraftFile key={f.id} draft={draft} f={f} host={host} station={station} session={session} />)}
        </ScrollView>
      )}
    </>
  );
}

function DraftQuoteCard({ draft, q }: { draft: Draft; q: DraftQuote }) {
  const C = useC();
  const ink = chatInk(C);
  const field = useRef<TextInput>(null);
  useEffect(() => {
    if (draft.focusQuote === q.id) { field.current?.focus(); draft.focusQuote = null; }
  }, [draft.focusQuote]); // eslint-disable-line react-hooks/exhaustive-deps
  // In the composer's capsule: corners concentric with it.
  return (
    <Smooth radius={InComposer} style={{ width: "100%", backgroundColor: ink.card }}>
      <View style={{ width: "100%" }}>
        <Text
          numberOfLines={2} ellipsizeMode="tail"
          style={{ fontSize: sp(13), lineHeight: 19.5, color: ink.muted, paddingLeft: 16, paddingRight: 34, paddingTop: 9, includeFontPadding: false, letterSpacing: 0 }}
        >{quoteLine(q.author, q.text)}</Text>
        <View style={{ width: "100%", paddingLeft: 16, paddingRight: 16, paddingTop: 3, paddingBottom: 10 }}>
          {q.comment === "" && <T size={15} line={22} color={ink.subtle} style={{ position: "absolute", left: 16, top: 3 }}>{t("android-chat.quote.comment")}</T>}
          <TextInput
            ref={field} value={q.comment} onChangeText={(v) => { q.comment = v; }} multiline={false}
            style={{ color: C.ink, fontSize: sp(15), lineHeight: 22, padding: 0, margin: 0, includeFontPadding: false, width: "100%" }}
            cursorColor={C.accent} selectionColor={withAlpha(C.accent, 0.35)}
            returnKeyType="next" submitBehavior="submit" onSubmitEditing={() => { draft.focus++; }}
          />
        </View>
      </View>
      <View style={{ position: "absolute", top: 5, right: 7, width: 28, height: 28, borderRadius: 14, overflow: "hidden" }}>
        <Pressable onPress={() => { draft.quotes.remove(q); }} android_ripple={{ color: withAlpha(C.ink, 0.12), borderless: false }} style={{ flex: 1, alignItems: "center", justifyContent: "center" }}>
          <Icon icon={Icons.Close} size={12} color={ink.subtle} />
        </Pressable>
      </View>
    </Smooth>
  );
}

/** One file of the draft as the composer shows it: a picture's tile, a paste's, a link's, a station file's, or its card. */
function DraftFile({ draft, f, host, station, session }: { draft: Draft; f: Pending; host: Host | null; station: string | null; session: string | null }) {
  const C = useC();
  const remove = () => { draft.files.remove(f); };
  const picture = useDraftPictureOf(f, station, session);
  if (picture != null) {
    return (
      <View>
        <DraftPicture f={f} station={station}>
          <SendTile host={host} id={f.id}>
            <Smooth radius={InComposerFiles} style={{ width: 56, height: 56, backgroundColor: C.chip }}>
              <Image source={{ uri: picture }} accessibilityLabel={f.name} resizeMode="cover" style={{ position: "absolute", left: 0, top: 0, right: 0, bottom: 0 }} />
              {f.done == null && (
                <View style={{ position: "absolute", left: 0, top: 0, right: 0, bottom: 0, backgroundColor: `rgba(0,0,0,${f.error != null ? 0.5 : 0.25})`, alignItems: "center", justifyContent: "center" }}>
                  {f.error != null ? <T size={11} color="#FFFFFF">{t("android-chat.file.failed")}</T> : <Spinner color="#FFFFFF" />}
                </View>
              )}
            </Smooth>
          </SendTile>
        </DraftPicture>
        {/* Only where it is drawn (no wider touch target): a tap meant to open the picture must not remove it. Over the
            picture's corner, its centre on the curve: solid, as part of it is on the composer's ground. */}
        <View style={{ position: "absolute", top: -PictureRemoveOut, right: -PictureRemoveOut, width: 20, height: 20, borderRadius: 10, overflow: "hidden", backgroundColor: C.ink }}>
          <Pressable onPress={remove} android_ripple={{ color: withAlpha(C.bg, 0.24), borderless: false }} style={{ flex: 1, alignItems: "center", justifyContent: "center" }}>
            <Icon icon={Icons.Close} size={12} color={raised(C)} />
          </Pressable>
        </View>
      </View>
    );
  }
  if (f.pasted != null) {
    const pasted = f.pasted;
    return (
      <SendTile host={host} id={f.id}>
        <PastedCard
          f={f} pasted={pasted} onRemove={remove}
          onRetry={f.error != null && station != null ? () => { draft.files.remove(f); pasteAsFile(draft, station, pasted.text); } : null}
          onRestore={pasted.restorable && !draft.starting ? () => { draft.files.remove(f); draft.text = draft.text === "" ? pasted.text : `${draft.text}\n${pasted.text}`; draft.focus++; } : null}
        />
      </SendTile>
    );
  }
  if (f.link != null) return <SendTile host={host} id={f.id}><LinkCard link={f.link} onRemove={remove} /></SendTile>;
  if (f.ref != null && station != null) return <SendTile host={host} id={f.id}><RefCard f={f} onRemove={remove} shape={InComposerFiles} onClick={() => openRefSheet(theApp, draft, f, station)} /></SendTile>;
  return (
    <SendTile host={host} id={f.id}>
      <FileCard name={f.done?.name ?? f.name} size={f.done?.size ?? f.size} note={f.error ?? (f.done == null ? uploadingText(f) : null)} busy={f.done == null && f.error == null} onRemove={remove} shape={InComposerFiles} />
    </SendTile>
  );
}

/** How far a composer picture's remove button (20 across) reaches beyond its edges: its centre on the corner's curve. */
const PictureRemoveOut = 10 - smoothMiddle(concentric(ComposerCorner, ComposerFilesIn));

/** A link shared in (share/), as a file of the draft: nothing goes up, it is sent as words after the text. */
export const linkPending = (link: ComposerLink) => new Pending(nanoTime(), link.title ?? link.url, 0, null, null, null, null, null, null, link);

/** A link in the composer, as a file's card: the web's mark, its title, its site; tapped, it opens. */
function LinkCard({ link, onRemove }: { link: ComposerLink; onRemove: () => void }) {
  const C = useC();
  return (
    <Smooth radius={InComposerFiles} style={{ width: 236, backgroundColor: chatInk(C).neutral }}>
      <Pressable
        onPress={() => { Linking.openURL(link.url).catch(() => undefined); }} android_ripple={{ color: withAlpha(C.ink, 0.12), borderless: false }}
        style={{ paddingHorizontal: 10, paddingVertical: 8, flexDirection: "row", alignItems: "center", gap: 10 }}
      >
        <Icon icon={Icons.Web} size={16} color={C.muted} />
        <View style={{ flex: 1, minWidth: 0 }}>
          <T size={15} line={20} color={C.ink} numberOfLines={1} ellipsizeMode="tail">{link.title ?? link.url}</T>
          <T size={11} line={16} color={C.muted} numberOfLines={1} ellipsizeMode="tail">{link.site ?? link.url}</T>
        </View>
        <RemoveDot onRemove={onRemove} />
      </Pressable>
    </Smooth>
  );
}

/** A card's remove button: a faint round 22 with a cross. */
function RemoveDot({ onRemove, label }: { onRemove: () => void; label?: string }) {
  const C = useC();
  return (
    <View style={{ width: 22, height: 22, borderRadius: 11, overflow: "hidden", backgroundColor: withAlpha(C.ink, 0.06) }}>
      <Pressable onPress={onRemove} accessibilityLabel={label} android_ripple={{ color: withAlpha(C.ink, 0.12), borderless: false }} style={{ flex: 1, alignItems: "center", justifyContent: "center" }}>
        <Icon icon={Icons.Close} size={12} color={C.muted} />
      </Pressable>
    </View>
  );
}

/**
 * Text pasted as a file, as the web's composer shows it: its first line, then how it goes (going up, failed, or a text
 * file of so many characters); 展开到输入框 puts it back in the text (not one too long for it), 重试上传 after it failed.
 */
function PastedCard({ f, pasted, onRemove, onRetry, onRestore }: { f: Pending; pasted: PastedText; onRemove: () => void; onRetry: (() => void) | null; onRestore: (() => void) | null }) {
  const C = useC();
  const busy = f.done == null && f.error == null;
  const action: [string, () => void] | null = onRetry != null ? [t("web-main.composer.retryPaste"), onRetry] : onRestore != null ? [t("web-main.composer.expandPaste"), onRestore] : null;
  return (
    <Smooth radius={InComposerFiles} style={{ width: 260, backgroundColor: chatInk(C).neutral }}>
      <View style={{ paddingLeft: 10, paddingRight: 8, paddingTop: 8, paddingBottom: 8, flexDirection: "row", alignItems: "center", gap: 10 }}>
        {busy ? <Spinner /> : <Icon icon={Icons.Read} size={16} color={C.muted} />}
        <View style={{ flex: 1, minWidth: 0 }}>
          <T size={15} line={20} color={C.ink} numberOfLines={1} ellipsizeMode="tail">{pasted.preview !== "" ? pasted.preview : t("web-main.composer.pastedText")}</T>
          <T size={11} line={16} color={f.error != null ? C.red : C.muted} numberOfLines={1} ellipsizeMode="tail">
            {f.error ?? (busy ? t("web-main.composer.pasteUploading") : t("web-main.composer.pasteAttachment", { count: pasted.characters }))}
          </T>
          {action != null && <T size={13} line={18} color={C.accent} style={{ paddingTop: 2 }} onPress={action[1]}>{action[0]}</T>}
        </View>
        <RemoveDot onRemove={onRemove} label={t("web-main.composer.removePaste")} />
      </View>
    </Smooth>
  );
}

/** A long paste: the file it goes as, up to `station` as any file added (`upload`). */
function pasteAsFile(draft: Draft, station: string, text: string) {
  const pasted = new PastedText(text);
  upload(theApp, draft, station, pastedPicked(pasted), theApp.scope, pasted);
}

/**
 * What a draft's picture shows (where it is read from): the one picked, or (a draft kept and opened again, which keeps
 * no picture, only the file it went up as) the one it was sent with this run, else the station's, fetched for its
 * chat's session (`key`). Null for a file that is no picture: it shows as a card.
 */
function useDraftPictureOf(f: Pending, station: string | null, key: string | null): string | null {
  const a = f.done;
  const wanted = f.preview == null && a != null && station != null && isImage(a.name);
  const longest = PixelRatio.getPixelSizeForLayoutSize(56) * 2;
  const id = wanted ? FileData.id(station!, key ?? "", a!, true) : null;
  const [picture, setPicture] = useState<Picture | null>(() => (wanted ? (FileData.sentPicture(station!, a!.path) ?? FileData.keptPicture(id!, longest) ?? null) : null));
  useEffect(() => {
    if (!wanted || picture != null || key == null) return;
    let live = true;
    FileData.fetch(theApp, station!, key, a!, true).await().then((bytes) => FileData.picture(id!, bytes, longest)).then(
      (p) => { if (live) setPicture(p); },
      () => undefined,
    );
    return () => { live = false; };
  }, [f.id, key]); // eslint-disable-line react-hooks/exhaustive-deps
  if (f.preview != null) return f.preview;
  return wanted ? picture?.uri ?? null : null;
}

/**
 * A picture waiting in the composer: tapped, shown whole in the viewer (growing out of its tile), from the bytes picked
 * (web Chat.tsx PendingFile: `draft:<id>`, no session's). Nothing to mark it into: it is already in the draft.
 */
function DraftPicture({ f, station, children }: { f: Pending; station: string | null; children: ReactNode }) {
  const bytes = f.local;
  const [open, setOpen] = useState(false);
  const file = useMemo<Attachment>(() => ({ name: f.name, path: `draft:${f.id}`, size: f.size, ...(f.width != null ? { width: f.width } : {}), ...(f.height != null ? { height: f.height } : {}) }), [f.id]); // eslint-disable-line react-hooks/exhaustive-deps
  if (station == null || bytes == null) return <>{children}</>;
  const id = FileViewers.id(station, "", file.path);
  return (
    <>
      <ForgetThumb id={id} />
      {open && <FilePreview station={station} sessionKey="" file={file} canDraft={false} onClose={() => setOpen(false)} />}
      <ViewerThumb id={id} radius={PixelRatio.getPixelSizeForLayoutSize(InComposerFiles)} picture={() => (f.preview != null ? { uri: f.preview, width: f.width ?? 0, height: f.height ?? 0 } : null)}>
        <Pressable onPress={() => { FileData.keep(FileData.id(station, "", file, false), bytes); setOpen(true); }}>
          {children}
        </Pressable>
      </ViewerThumb>
    </>
  );
}

/** Whether the composer shows its bigger layout: the field over its buttons. */
export const composerExpanded = (d: Draft): boolean => d.focused || d.text !== "" || d.files.isNotEmpty() || d.quotes.isNotEmpty();

/** Where the field is in the window, as it is laid out (LayoutCoordinates there). */
export interface FieldBox { x: number; y: number; width: number; height: number }

/**
 * The bar, inside a floating capsule that is its frame (web mobile/Chat.tsx → useComposerBar): ＋, a field that grows
 * with the text up to six lines right after it (its references drawn as marks, a backspace taking one whole), and a round
 * send button (a spinner while a new chat is made). Locked (offline, archived), neither ＋ nor send does anything.
 * `hint`: how much the placeholder shows (words just sent pass over it first: ChatHost.tsx); `morph`: the capsule's, whose
 * parts ＋, the field and send are (they move with it); `onField`: where the field is, as it is laid out, and
 * `onFieldText` how its words are (where each line breaks: words sent fly line by line from there, ChatHost.tsx).
 */
export function ComposerBar({
  draft, placeholder, onPlus, onType, onSend, hint, morph = null, onField = () => {}, onFieldText = () => {}, station = null,
}: {
  draft: Draft; placeholder: string; onPlus: () => void; onType: () => void; onSend: () => void;
  hint?: SharedValue<number>; morph?: Morph | null; onField?: (at: FieldBox) => void;
  onFieldText?: (layout: TextLayoutEventData) => void; station?: string | null;
}) {
  useDraftWatch();
  const C = useC();
  // One style for what is typed and the placeholder: the field is as tall empty as with a line in it.
  const style = { ...SendTextStyle, color: C.ink };
  const lineHeight = (SendTextStyle as { lineHeight?: number }).lineHeight ?? 21;
  const locked = draft.locked || draft.starting;
  const expanded = draft.composerExpanded;
  const field = useRef<TextInput>(null);
  const [fieldWidth, setFieldWidth] = useState(0);
  useEffect(() => { if (draft.focus > 0) field.current?.focus(); }, [draft.focus]);
  const hintStyle = useAnimatedStyle(() => ({ opacity: hint ? hint.value : 1 }));

  // What the text takes as it is written (the user's edits; what the app puts there goes as it is).
  const onChangeText = (now: string) => {
    // Typed: where the field has its cursor is where it is, whatever the app put before.
    draft.placed = null;
    const was = draft.text;
    const sel = draft.selection;
    if (now === was) return;
    // A backspace just after a reference takes it whole.
    const caret = sel.start;
    const mark = sel.start === sel.end && now.length === was.length - 1 && caret > 0 && now === was.slice(0, caret - 1) + was.slice(caret) ? ChatRefs.before(was, caret) : null;
    if (mark != null) {
      draft.input = { text: now.slice(0, mark) + now.slice(caret - 1), selection: { start: mark, end: mark } };
      onType();
      return;
    }
    const put = insertedRange(was, now);
    // A long paste goes as a file (PastedText.tsx), the text left as it was.
    if (put != null && put.last - put.first + 1 >= PASTE_THRESHOLD && station != null && !locked) {
      const text = now.substring(put.first, put.last + 1);
      // The field has it already: shown for the frame it takes to put back what was there.
      draft.typed(now);
      setTimeout(() => { draft.input = { text: was, selection: sel }; }, 0);
      pasteAsFile(draft, station, text);
      return;
    }
    draft.typed(now);
    onType();
    // A chat's link pasted (`[its title](its link)`, as copied) goes in as a reference, as on the web.
    if (station != null && put != null && put.last > put.first) {
      const refs = linkedRefs(now, station).filter(([m]) => m.range.first <= put.last && m.range.last >= put.first);
      if (refs.length > 0) void markPasted(draft, now, refs);
    }
  };

  const ready = draft.ready;
  // Not ready: the ink faint over the capsule's own ground (web: 18% text over --raised).
  const idle = lerpColor(C.surface, C.ink, 0.18);
  const ink = ready ? C.bg : C.surface;
  const marks = refMarks(draft.text, C.accent);
  const measureField = () => { field.current?.measureInWindow((x, y, width, height) => onField({ x, y, width, height })); };
  // Keep the field in one place in the tree while the buttons move below it, preserving focus and the keyboard: the
  // buttons stand at the foot either way, the field beside them or over them.
  const gap = 2;
  return (
    <View style={{ width: "100%", paddingBottom: expanded ? 4 + 36 : 0, minHeight: 36 }}>
      <Part
        m={morph} name="field"
        style={{ minHeight: 36, marginLeft: expanded ? 0 : 36 + gap, marginRight: expanded ? 0 : 36 + gap, paddingLeft: expanded ? 14 : 0, paddingRight: 14, paddingTop: 7, paddingBottom: 7, justifyContent: "center", marginTop: "auto" }}
      >
        {draft.text === "" && (
          <Animated.Text numberOfLines={1} ellipsizeMode="tail" style={[style, { color: C.subtle, position: "absolute", left: expanded ? 14 : 0, right: 14 }, hintStyle]}>
            {placeholder}
          </Animated.Text>
        )}
        {/* How the words lie in the field (its lines), measured as they are drawn: the field itself does not say. */}
        <Text
          style={[style, { position: "absolute", left: expanded ? 14 : 0, top: 7, width: fieldWidth || undefined, opacity: 0 }]} pointerEvents="none"
          onTextLayout={(e) => onFieldText(e.nativeEvent)}
        >
          {marks}
        </Text>
        <TextInput
          ref={field} multiline editable={!draft.starting}
          onChangeText={onChangeText}
          onSelectionChange={(e) => { draft.selection = e.nativeEvent.selection; }}
          selection={draft.placed ?? undefined}
          onFocus={() => { draft.focused = true; }} onBlur={() => { draft.focused = false; }}
          onLayout={(e: LayoutChangeEvent) => { setFieldWidth(e.nativeEvent.layout.width); measureField(); }}
          cursorColor={C.accent} selectionColor={withAlpha(C.accent, 0.35)}
          style={[style, { width: "100%", maxHeight: lineHeight * 6, padding: 0, margin: 0, textAlignVertical: "top", includeFontPadding: false }]}
        >
          {marks}
        </TextInput>
        {/* NATIVE: pictures and files pasted, or sent by the keyboard (its clipboard, stickers), go with the message as one added by ＋ is (Compose's contentReceiver): React Native's TextInput takes only text; it needs the field to take rich content (OnReceiveContentListener) and hand each item's uri to readPicked → upload. */}
      </Part>
      <Part m={morph} name="plus" style={{ position: "absolute", left: 0, bottom: 0, width: 36, height: 36, borderRadius: 18, overflow: "hidden" }}>
        <Pressable
          disabled={locked} onPress={onPlus} accessibilityLabel={t("android-chat.attach.title")}
          android_ripple={{ color: withAlpha(C.ink, 0.12), borderless: false }} style={{ flex: 1, alignItems: "center", justifyContent: "center" }}
        >
          <Icon icon={Icons.Plus} size={18} color={locked ? withAlpha(C.ink, 0.35) : C.ink} />
        </Pressable>
      </Part>
      <Part m={morph} name="send" style={{ position: "absolute", right: 0, bottom: 0, width: 36, height: 36, borderRadius: 18, overflow: "hidden", backgroundColor: ready ? C.ink : idle }}>
        <Pressable
          disabled={!ready} onPress={onSend} accessibilityLabel={t("android-chat.composer.send")}
          android_ripple={{ color: withAlpha(C.bg, 0.24), borderless: false }} style={{ flex: 1, alignItems: "center", justifyContent: "center" }}
        >
          <BusyIcon busy={draft.starting} solid={ink} icon={<Icon icon={Icons.ArrowUp} size={18} color={ink} />} />
        </Pressable>
      </Part>
    </View>
  );
}

// ── the capsule's change of shape (web morph.ts → useMorph) ─────────────

interface XY { x: number; y: number }

/** A part: where it is in the content as laid out, where it goes from, and where it was last drawn (from the capsule's bottom edge). */
class MorphPart {
  readonly inContent = makeMutable<XY>({ x: 0, y: 0 });
  readonly from = makeMutable<XY | null>(null);
  drawn: XY | null = null;
  laid = false;
}

/**
 * The composer's capsule growing or shrinking (a line more, a file or a quote, sent and emptied) in one motion, as the
 * web's: its height, and with it its corners (a capsule's ends are half its height), and its parts (＋, the field,
 * send) going from where they showed to where the new layout puts them, all on one timeline (260 ms, Ease.Out). The
 * capsule stands on its bottom edge: what it holds is laid out anew at once from its top, in the box as tall as it is
 * at that moment (the rest cut by its shape), and each part is carried from where it was to its place.
 */
export class Morph {
  /** How far the motion has got, eased (0 → 1). */
  readonly progress = makeMutable(1);
  readonly fromH = makeMutable(-1);
  readonly toH = makeMutable(-1);
  readonly #parts = new Map<string, MorphPart>();
  /** Bumped for each change of height: what starts the motion. */
  run = 0;
  still = false;
  content: View | null = null;

  part(key: string): MorphPart {
    let p = this.#parts.get(key);
    if (!p) { p = new MorphPart(); this.#parts.set(key, p); }
    return p;
  }

  /** The height drawn now. */
  height(): number {
    const f = this.fromH.value, to = this.toH.value;
    return f < 0 ? to : f + (to - f) * this.progress.value;
  }

  /** Where a part shows now, from the capsule's bottom edge. */
  #shown(p: MorphPart): XY {
    const ic = p.inContent.value;
    const at = { x: ic.x, y: ic.y - this.toH.value };
    const was = p.from.value;
    if (!was) return at;
    const e = this.progress.value;
    return { x: was.x + (at.x - was.x) * e, y: was.y + (at.y - was.y) * e };
  }

  /** The content laid out anew, `h` tall: from where it shows now to there. */
  retarget(h: number) {
    if (this.toH.value < 0 || this.still) { this.toH.value = h; this.fromH.value = -1; return; }
    const now = this.height();
    // From where each part was last seen (a layout may have moved it since, before this change of height was seen).
    for (const p of this.#parts.values()) { p.from.value = p.drawn ?? this.#shown(p); p.drawn = null; }
    this.fromH.value = now;
    this.toH.value = h;
    this.progress.value = 0;
    const run = ++this.run;
    // The callback runs on the UI thread: the JS function it calls taken out first (`this` is not there).
    const played = this.#played;
    this.progress.value = withTiming(1, { duration: 260, easing: Ease.Out }, (finished) => { if (finished) runOnJS(played)(run); });
  }

  #played = (run: number) => {
    if (run !== this.run) return;
    for (const p of this.#parts.values()) p.from.value = null;
    this.fromH.value = -1;
  };

  /** A part laid out: where it is in the content now. */
  placed(key: string, view: View) {
    const p = this.part(key);
    const content = this.content;
    if (!content) return;
    view.measureLayout(content, (x, y) => {
      const ic = p.inContent.value;
      if (p.laid && ic.x === x && ic.y === y) return;
      // Where it showed before this layout moved it: where the motion takes it from, should the height change too.
      if (p.laid) { p.drawn = this.#shown(p); setTimeout(() => { p.drawn = null; }, 0); }
      p.laid = true;
      p.inContent.value = { x, y };
    }, () => undefined);
  }

  /** The height it is going to. */
  get target(): number { return this.toH.value; }
}

/** A morph for a capsule, played whenever its height changes (at once with the system's animations off). A hook. */
export function rememberMorph(): Morph {
  const m = useMemo(() => new Morph(), []);
  m.still = useReducedMotion();
  return m;
}
export const useMorph = rememberMorph;

/** The capsule's content, its height the morph's (it measures itself as it would be, and shows as tall as the motion has got): Modifier.morph there. */
export function MorphContent({ m, style, children }: { m: Morph; style?: StyleProp<ViewStyle>; children?: ReactNode }) {
  const [measured, setMeasured] = useState(false);
  const holder = useRef<View>(null);
  useLayoutEffect(() => { m.content = holder.current; });
  // Its shared values alone into the worklet: the morph itself (a class, with its view and its private parts) is not
  // one the UI thread can take.
  const { fromH, toH, progress } = m;
  const box = useAnimatedStyle(() => {
    const f = fromH.value, to = toH.value;
    if (to < 0) return {};
    return { height: f < 0 ? to : f + (to - f) * progress.value };
  });
  return (
    <Animated.View style={[{ width: "100%", overflow: "hidden" }, measured ? box : null]}>
      <View
        ref={holder} collapsable={false}
        style={[measured ? { position: "absolute", left: 0, right: 0, top: 0 } : null, style]}
        onLayout={(e) => { const h = e.nativeEvent.layout.height; if (h !== m.target) m.retarget(h); if (!measured) setMeasured(true); }}
      >
        {children}
      </View>
    </Animated.View>
  );
}

/** One of the capsule's parts: carried with it while it changes shape (Modifier.part there). */
export function Part({ m, name, style, children }: { m: Morph | null; name: string; style?: StyleProp<ViewStyle>; children?: ReactNode }) {
  const view = useRef<View>(null);
  const p = m?.part(name) ?? null;
  // Shared values alone into the worklet (MorphContent).
  const fromH = m?.fromH ?? null, toH = m?.toH ?? null, progress = m?.progress ?? null;
  const inContent = p?.inContent ?? null, from = p?.from ?? null;
  const moved = useAnimatedStyle(() => {
    if (!fromH || !toH || !progress || !inContent || !from) return {};
    const f = fromH.value, to = toH.value, e = progress.value;
    const h = f < 0 ? to : f + (to - f) * e;
    const ic = inContent.value;
    const was = from.value;
    const at = { x: ic.x, y: ic.y - to };
    const shown = was ? { x: was.x + (at.x - was.x) * e, y: was.y + (at.y - was.y) * e } : at;
    return { transform: [{ translateX: shown.x - ic.x }, { translateY: shown.y - (ic.y - h) }] };
  });
  return (
    <Animated.View ref={view} collapsable={false} style={[style, moved]} onLayout={() => { if (m && view.current) m.placed(name, view.current as unknown as View); }}>
      {children}
    </Animated.View>
  );
}

/** An archived chat's composer keeps its draft and says so, with its restore (retried after an error): web ArchiveNotice.tsx. */
function ArchiveNotice({ offline, station, session, restore }: { offline: boolean; station: string; session: string; restore: () => Promise<unknown> }) {
  const C = useC();
  // As Action.kt has it: under way while the core's doing list has the call, its failure said (and toasted).
  const doing = useDoing("chat.archive", { station, session });
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const busy = doing || pending;
  return (
    <View style={{ paddingHorizontal: 8, paddingVertical: 2 }}>
      <View style={{ flexDirection: "row", alignItems: "center" }}>
        <T size={13} color={C.muted}>{t("android-chat.composer.archived")}</T>
        <T
          size={13} color={offline ? C.muted : C.ink} style={{ textDecorationLine: "underline" }}
          onPress={busy || offline ? undefined : () => {
            if (pending) return;
            setPending(true); setError(null);
            restore().then(
              () => setPending(false),
              (e: unknown) => { setPending(false); const m = e instanceof Error ? e.message : String(e); setError(m); theApp.toast = m; },
            );
          }}
        >
          {busy ? t("android-chat.composer.restoring") : t("android-chat.composer.restore")}
        </T>
      </View>
      {error != null && <T size={13} color={C.red}>{error}</T>}
    </View>
  );
}

/**
 * What the chat's composer (the host's: ChatHost.tsx) writes to. The composer empties at once: the message lives in the
 * chat's outbox until the station has it (a failure shows there too), its words flying from the composer to its place in
 * the list (Host.sending). Before the agent has a chat, what is sent waits in the outbox while the core has the station
 * make one, bound to the agent; the page becomes it. A hook.
 */
export function chatComposer(host: Host, station: string, of: ChatOf, view: ChatView, agents: AgentHere[], draft: Draft): ComposerSpec {
  const C = useC();
  const keeper = agents[0]?.key ?? null;
  // Uploads go on whatever the page does: a draft kept for the chat takes its files when they are up, the page gone or not.
  const launchers = AttachLaunchers((picked) => upload(theApp, draft, station, picked));
  const thread = view.thread;
  const archived = view.archived === true;
  draft.locked = view.offline || archived;
  const send = chatSend(host, station, of, view, keeper, draft);
  const session = ("session" in of ? of.session : null) ?? keeper ?? "";
  return {
    station, here: keeper, draft, placeholder: archived ? t("android-chat.composer.archived.placeholder") : t("android-chat.chat.placeholder"),
    notices: () => (
      <>
        {archived && (
          <ArchiveNotice
            offline={view.offline} station={station} session={session}
            restore={() => theApp.api(station).setArchived(thread?.id ?? null, session, false)}
          />
        )}
        {view.offline && <T size={13} color={C.muted} style={{ paddingHorizontal: 8, paddingVertical: 2 }}>{t("android-chat.composer.offline")}</T>}
      </>
    ),
    onPlus: () => openAttach(theApp, launchers, () => openStationFiles(theApp, draft, station)),
    // Typing starts the session's runtime, so a cold start overlaps the writing.
    onType: () => {
      if (!draft.locked && keeper != null && Date.now() - draft.warmed > 60_000) {
        draft.warmed = Date.now();
        theApp.scope.launch(() => theApp.api(station).warm(keeper).catch(() => undefined));
      }
    },
    onSend: () => { if (!draft.locked) sendSharing(theApp, draft, station, send); },
  } as ComposerSpec;
}

/** Sends what the chat's composer holds (once what it refers to can be read here: sendSharing). */
function chatSend(host: Host, station: string, of: ChatOf, view: ChatView, keeper: string | null, draft: Draft): () => void {
  return () => {
    if (draft.locked) return;
    // Its words stay where they were typed until its row is in the list, then go there. Not from a window short
    // of the chat's end: its row is past the window until the station has the message (at no time known); it
    // comes in as rows do.
    if (view.newer !== true) host.sending(draft.text.trim(), false, draft.files.toList());
    const taken = draft.take();
    // Refused by the core before it reached the outbox (`invalid_params`: no such chat, a bad address): the words
    // come back if nothing was written since, and why is said. A station's failure is in the outbox (未发送, 重试).
    const refused = (e: unknown) => {
      host.notSent();
      if (e instanceof CoreError && e.code === "invalid_params") {
        if (draft.empty) { draft.restore(taken); draft.error = errorOf(e); }
        else theApp.toast = t("android-chat.composer.send.failed", { error: errorOf(e) });
      }
    };
    // Sent to by the page's key until its thread is known: a chat made here (`new:…`), or the agent's, whose
    // chat the core has its station make behind what is sent (it waits in the outbox meanwhile).
    const to = view.thread?.id ?? null;
    const key = ("session" in of ? of.session : null) ?? keeper;
    const attachments = taken.files.flatMap((f) => (f.done ? [f.done] : []));
    const quotes = taken.quotes.map((q) => q.sent());
    // Sent from the app's scope: the page may move on before the station answers.
    theApp.scope.launch(async () => {
      try {
        if (to != null) await theApp.api(station).send(to, taken.text, attachments, quotes);
        else if (key != null) await theApp.api(station).sendIn(key, taken.text, attachments, quotes);
        else host.notSent();
      } catch (e) { refused(e); }
    });
  };
}
