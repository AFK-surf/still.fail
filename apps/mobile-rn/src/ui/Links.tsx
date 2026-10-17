// Web addresses in what people and agents write: found where they are written bare, as the web finds them
// (web/src/bareLinks.ts), and held for a menu of their own (open, copy) rather than the message's.
import * as Clipboard from "expo-clipboard";
import * as Haptics from "expo-haptics";
import { useContext, useMemo, useRef } from "react";
import { Platform, type GestureResponderEvent, type TextProps, type View } from "react-native";
import { MenuItem, MenuSpec } from "../AppState";
import { t } from "../i18n";
import { useUi } from "./Host";
import { Icons } from "./Icon";
import { AnnotatedString, LinkUrl, type AnnotatedStringBuilder, type TextLinkStyles } from "./Annotated";
import { LocalPickedWords, TextBox, lineRects, noHook, rectContains, useLaidOut, type TextHook } from "./Pick";
import type { IntRange } from "./TextMark";

// ── bare addresses ─────────────────────────────────────────────────────

/**
 * A bare address: http(s):// and the characters addresses are made of, ending at a space or at a letter outside ASCII
 * (Chinese words, full-width marks such as `）` `，` `。`); the marks closing a sentence after it (`.` `,` `:` …) and a
 * closing bracket it did not open are not its. GFM's own finding ends only at a space: `（https://…/2854）已改到` was
 * one link, its words with it.
 */
const ADDRESS = /(?<![A-Za-z0-9])https?:\/\/[A-Za-z0-9\-._~:/?#[\]@!$&'()*+,;=%]+/gi;
const HOST = /^https?:\/\/[A-Za-z0-9]/i;

/** Where the bare addresses in `text` are. */
export function bareLinks(text: string): IntRange[] {
  const out: IntRange[] = [];
  for (const m of text.matchAll(ADDRESS)) {
    const first = m.index!;
    const url = trimmed(m[0]);
    // A host, not the scheme alone; one cut short (`https://github.com/…`) is no address to open.
    if (!HOST.test(url) || text[first + m[0].length] === "…") continue;
    out.push({ first, last: first + url.length - 1 });
  }
  return out;
}

const count = (s: string, c: string) => s.split(c).length - 1;

/** An address without what closes the sentence or the bracket it is written in. */
function trimmed(address: string): string {
  let url = address;
  while (url.length > 0) {
    const last = url[url.length - 1]!;
    if (".,:;!?'*_~".includes(last)) url = url.slice(0, -1);
    else if (last === ")" && count(url, "(") < count(url, ")")) url = url.slice(0, -1);
    else if (last === "]" && count(url, "[") < count(url, "]")) url = url.slice(0, -1);
    else return url;
  }
  return url;
}

/** `text`, its bare addresses as links drawn in `style` (AnnotatedString.Builder.appendLinked). */
export function appendLinked(builder: AnnotatedStringBuilder, text: string, style: TextLinkStyles): void {
  let at = 0;
  for (const r of bareLinks(text)) {
    builder.append(text, at, r.first);
    builder.withLink(LinkUrl(text.substring(r.first, r.last + 1), style), () => { builder.append(text, r.first, r.last + 1); });
    at = r.last + 1;
  }
  builder.append(text, at, text.length);
}

const WEB_ADDRESS = /^https?:\/\/(?:localhost|[\w-]+(?:\.[\w-]+)+)(?::\d+)?(?:[/?#]\S*)?$/i;

/** A web address alone in inline code, which is a link too (as the web's Prose.tsx has it). */
export function isWebAddress(code: string): boolean {
  return !code.includes("…") && WEB_ADDRESS.test(code.trim());
}

/**
 * The words with their links drawn as links but none to tap: where a finger picks words from them (the annotate page,
 * Pick.tsx; the web's links there take no touches either).
 */
export function inert(text: AnnotatedString): AnnotatedString {
  const links = text.getLinkAnnotations(0, text.length);
  if (links.length === 0) return text;
  const spans = [...text.spanStyles];
  for (const l of links) if (l.item.styles?.style) spans.push({ item: l.item.styles.style, start: l.start, end: l.end });
  return new AnnotatedString(text.text, spans, [], text.inlines);
}

/** Android's touch slop (ViewConfiguration: 8dp) and long-press timeout (400ms since Android 12). */
const TOUCH_SLOP = 8;
const LONG_PRESS_MS = 400;

/** A link held a moment ago: the tap its finger's lifting makes is not the link's (takeLinkHeld). */
let held = false;

/**
 * Whether the press ending now was a hold on a link (its menu opened): the link's tap is to do nothing then, as the
 * Android app consumes the finger's lifting. What opens a tapped link asks it first (Annotated.tsx's link runs).
 */
export function takeLinkHeld(): boolean {
  const was = held;
  held = false;
  return was;
}

/**
 * The hook for words with links in them: a long press on one is its menu (open it, copy it), as the app's other long-
 * press menus are (Sheet.tsx MenuHost), not the message's own (its page) and not the link opening as the finger lifts;
 * a tap stays the link's. What to put on the text and what to give its onTextLayout. Nothing while a passage of the
 * words is picked (Pick.tsx: a tap there lets go of it). It only watches the touches (the text's own go on to the
 * link and what is under it), as the Android app's reads them before the link's own tap.
 */
export function linkHold(text: AnnotatedString): TextHook {
  const links = useMemo(() => text.getLinkAnnotations(0, text.length).filter((l) => l.item.kind === "url"), [text]);
  const words = useContext(LocalPickedWords);
  const ui = useUi();
  const [layout, laid] = useLaidOut(text.text);
  const view = useRef<View | null>(null);
  const press = useRef<{ id: string; x: number; y: number; url: string; timer: ReturnType<typeof setTimeout> } | null>(null);
  if (links.length === 0 || words?.picking === true) return noHook();
  const letGo = () => { if (press.current) { clearTimeout(press.current.timer); press.current = null; } };
  const open = (url: string, at: { x: number; y: number }) => {
    if (!layout) return;
    held = true;
    if (Platform.OS === "android") Haptics.performAndroidHapticsAsync(Haptics.AndroidHaptics.Long_Press).catch(() => undefined);
    else Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium).catch(() => undefined);
    view.current?.measureInWindow((wx, wy) => {
      // Under the line held (over it when there is no room below), centred on the finger: the menu is 180 wide.
      const line = layout.getLineForVerticalPosition(at.y);
      const x = wx + at.x - 90;
      const top = wy + layout.getLineTop(line);
      const bottom = wy + layout.getLineBottom(line);
      ui.menu = new MenuSpec({ left: x, top, right: x, bottom }, [
        // As a tap on it: still.fail's own open in the app, any other in the browser (AppState's follow).
        new MenuItem(t("common.link.open"), Icons.External, () => ui.follow(url, () => undefined)),
        new MenuItem(t("common.link.copy"), Icons.Copy, () => {
          Clipboard.setStringAsync(url).catch(() => undefined);
          ui.note(t("common.link.copied"));
        }),
      ]);
    });
  };
  const watch = {
    onTouchStart: (e: GestureResponderEvent) => {
      letGo();
      held = false;
      const l = layout;
      if (!l) return;
      const { locationX: x, locationY: y, identifier } = e.nativeEvent;
      const link = links.find((k) => lineRects(l, k.start, k.end).some((r) => rectContains(r, { x, y })));
      if (!link || link.item.kind !== "url") return;
      const url = link.item.url;
      // Let go, moved or taken by something else before a long press's time: a tap or a scroll, not this.
      press.current = { id: identifier, x: e.nativeEvent.pageX, y: e.nativeEvent.pageY, url, timer: setTimeout(() => { press.current = null; open(url, { x, y }); }, LONG_PRESS_MS) };
    },
    onTouchMove: (e: GestureResponderEvent) => {
      const p = press.current;
      if (p && Math.hypot(e.nativeEvent.pageX - p.x, e.nativeEvent.pageY - p.y) > TOUCH_SLOP) letGo();
    },
    onTouchEnd: letGo,
    onTouchCancel: letGo,
  };
  return [
    {
      props: watch as unknown as Partial<TextProps>,
      behind: <TextBox view={(v) => { view.current = v; }} />,
    },
    laid,
  ];
}
