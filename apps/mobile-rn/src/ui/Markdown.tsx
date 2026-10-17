// Agents write Markdown; the phone reads it as the web phone does (web/src/Prose.tsx, Prose.css.ts and the message's
// `.markdown` in styles/conversation.css.ts, at the phone's sizes: 15 with a 1.65 line). GFM: paragraphs with
// emphasis, inline code, links and strikethrough; headings; lists (bulleted, numbered, tasks, nested) with hanging
// indents; quotes beside a bar; code blocks with their language and a copy button on a row of their own (a finger
// has no hover), scrolling sideways; tables that wrap between words and scroll sideways when they still do not fit;
// rules. A link to another chat is a reference to it (chatRefs.ts), `@its title` in the accent; a web address written
// bare, or alone in inline code, is a link too (Links.tsx), and a link held is its menu (open, copy); a ```mermaid block
// is drawn as its chart (Viz.tsx). With `placing`, the message's files its text names are drawn where it names them.
//
// Spacing is the web's: each block keeps the margins the browser gives it, and two blocks next to each other are as
// far apart as the larger of the two margins between them (CSS margins collapse, through a list item or a quote too).
//
// (The Android app's ui/Markdown.kt.) The Android app parses with commonmark-java and its GFM extensions; here the
// same CommonMark/GFM tree comes from micromark (mdast-util-from-markdown with the tables, strikethrough and task
// list extensions, what the core's markdown.ts and the web read with): the tree's nodes are commonmark's under
// mdast's names (a soft line break is a "\n" in a text node, a reference link is resolved by its definition here).
import * as Clipboard from "expo-clipboard";
import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { Pressable, ScrollView, Text, View, type StyleProp, type ViewStyle } from "react-native";
import type { Definition, Image, Link, List, ListItem, Nodes, Paragraph, PhrasingContent, Root, RootContent, Table as MdTable, TableCell } from "mdast";
import { fromMarkdown } from "mdast-util-from-markdown";
import { gfmStrikethroughFromMarkdown } from "mdast-util-gfm-strikethrough";
import { gfmTableFromMarkdown } from "mdast-util-gfm-table";
import { gfmTaskListItemFromMarkdown } from "mdast-util-gfm-task-list-item";
import { gfmStrikethrough } from "micromark-extension-gfm-strikethrough";
import { gfmTable } from "micromark-extension-gfm-table";
import { gfmTaskListItem } from "micromark-extension-gfm-task-list-item";
import type { Attachment } from "../../../../web/src/core/shapes.ts";
import { t } from "../i18n";
import {
  AnnotatedString, AnnotatedStringBuilder, AnnotatedText, LinkClickable, LinkUrl, buildAnnotatedString, thenText,
  type InlineTextContent, type SpanStyle, type TextLinkStyles,
} from "./Annotated";
import { CodeInk } from "./CodeInk";
import { Icon, Icons } from "./Icon";
import { appendLinked, isWebAddress, linkHold } from "./Links";
import { pickable, pickedText } from "./Pick";
import { Smooth } from "./Smooth";
import { markWeight, passageMark } from "./TextMark";
import { CODE_FONT, useC, withAlpha, type StillFailColors } from "./Theme";
import { Mermaid } from "./Viz";

type Node = Nodes;

/** A document as drawn from: its tree, and the link definitions its references are resolved by. */
export interface MdDocument { root: Root; defs: ReadonlyMap<string, Definition> }

const normal = (id: string) => id.replace(/[\t\n\r ]+/g, " ").trim().toLowerCase();

function collect(node: Node, defs: Map<string, Definition>): void {
  if (node.type === "definition" && !defs.has(normal(node.identifier))) defs.set(normal(node.identifier), node);
  if ("children" in node) for (const c of node.children as Node[]) collect(c, defs);
}

/** A message's text as a document: [tablesApart] first, wherever it is parsed (as a chat is decoded, or as it is drawn). */
export function parseMarkdown(text: string): MdDocument {
  const root = fromMarkdown(tablesApart(text), {
    extensions: [gfmTable(), gfmStrikethrough(), gfmTaskListItem()],
    mdastExtensions: [gfmTableFromMarkdown(), gfmStrikethroughFromMarkdown(), gfmTaskListItemFromMarkdown()],
  });
  const defs = new Map<string, Definition>();
  collect(root, defs);
  return { root, defs };
}

/** A table's delimiter row: `|---|:--:|`, or `--- | ---` without the outer pipes. */
const tableDelimiter = /^ {0,3}\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$/;

/**
 * GFM (and the web's parser) starts a table on a paragraph's last line (`**这些**` and then the table, no blank line
 * between); commonmark-java only on a paragraph of its own, and prints the table as text. So a blank line goes before
 * such a table's header (outside fenced code). (micromark starts it there itself; kept so the two apps read the same
 * text alike.)
 */
export function tablesApart(text: string): string {
  if (!text.includes("|") || !text.includes("-")) return text;
  const lines = text.split("\n");
  let out = "";
  let fence: string | null = null;
  lines.forEach((line, i) => {
    const lead = line.trimStart();
    const open = fence;
    if (open == null && (lead.startsWith("```") || lead.startsWith("~~~"))) fence = lead.substring(0, 3);
    else if (open != null && lead.startsWith(open)) fence = null;
    else if (open == null && i > 0 && i < lines.length - 1 && line.includes("|") && lines[i + 1]!.includes("|") && tableDelimiter.test(lines[i + 1]!) &&
      lines[i - 1]!.trim() !== "" && !lines[i - 1]!.includes("|")) out += "\n";
    out += line;
    if (i < lines.length - 1) out += "\n";
  });
  return out;
}

/** Documents parsed, by their text, bound by its characters. */
const DOCUMENTS = 256 * 1024;
const documents = new Map<string, MdDocument>();
let documentChars = 0;
function documentOf(text: string): MdDocument | undefined {
  const hit = documents.get(text);
  if (hit) { documents.delete(text); documents.set(text, hit); }
  return hit;
}
function keepDocument(text: string, doc: MdDocument) {
  if (documents.has(text)) return;
  documents.set(text, doc);
  documentChars += Math.max(1, text.length);
  for (const [k] of documents) {
    if (documentChars <= DOCUMENTS) break;
    documents.delete(k);
    documentChars -= Math.max(1, k.length);
  }
}

/**
 * Parses `text` into the documents a message draws from, if not there yet: done ahead as a chat's messages come
 * (data/ChatDecoder.kt in the Android app), so they are drawn whole as the chat first shows, not "laying out" first.
 */
export function prepareMarkdown(text: string): void {
  if (text.length === 0 || documents.has(text)) return;
  keepDocument(text, parseMarkdown(text));
}

/** Text up to this long is parsed as it is first drawn, when it was not prepared: the JS thread parses it either way. */
const PARSED_AT_ONCE = 20_000;

const childrenOf = (n: Node): Node[] => ("children" in n ? (n.children as Node[]) : []);

/**
 * A message's files its text places (the core's `placed`, client/core-ts/src/placed.ts), and how they are drawn:
 * `shown` draws one on a line of its own (an HTML file as its visualization, an image whole, any other as its card) or
 * several images in a row (`row`, each given the style that sizes it); `open` opens one a link within a sentence
 * names.
 */
export class Placing {
  constructor(
    readonly files: ReadonlyMap<string, Attachment>,
    readonly shown: (file: Attachment) => ReactNode,
    readonly row: (file: Attachment, modifier: StyleProp<ViewStyle>) => ReactNode,
    readonly open: (file: Attachment) => void,
  ) {}
}

/** The file a link or image in the text names, by its file name (the last part of its path): `shot.png`, `/w/shot.png`, `ember-file://…/shot.png`. */
export function fileNameOf(url: string): string {
  let u = url.trim().replace(/^(ember-)?file:\/\//, "");
  try { u = decodeURIComponent(u.replace(/\+/g, "%2B")); } catch { /* as written */ }
  return u.substring(u.lastIndexOf("/") + 1);
}

// ── references to chats (chatRefs.ts) ─────────────────────────────────

/** A link to a chat's page (…/chats/<key>, or still.fail cloud's /o/<workspace>/<station>/<key>). */
export function isChatLink(href: string | null | undefined): boolean {
  return href != null && (/\/chats\/[^/?#\s]+\/?(?:[?#]|$)/.test(href) || /^https?:\/\/[^/]+\/o\/[^/]+\/[^/]+\/[^/?#]+\/?(?:#|$)/.test(href));
}

/** A reference as sent: `[its title](its page)`. */
const REF_LINK = /\[([^\]\n]{1,120})\]\((\S*?\/chats\/[^\s)]+)\)/g;

/** The alpha of a #RRGGBB or #RRGGBBAA colour, 0..1. */
const alphaOf = (hex: string) => (hex.length >= 9 ? parseInt(hex.slice(7, 9), 16) / 255 : 1);

/** A reference in a message: `@` (a little lighter) and the chat's title, in the accent; a tap opens the chat (AppState.openLink). */
export function appendRef(b: AnnotatedStringBuilder, title: AnnotatedString, href: string, accent: string): void {
  b.withLink(LinkUrl(href, { style: { color: accent, textDecorationLine: "none" } }), () => {
    b.withStyle({ color: withAlpha(accent, alphaOf(accent) * 0.7) }, () => b.append("@"));
    b.append(title);
  });
}

/** Plain text (what a person wrote) with its references to chats drawn as the chips a message draws, and its web addresses as links. */
export function withRefs(text: string): AnnotatedString {
  const C = useC();
  const accent = C.accent;
  const blue = C.blue;
  return useMemo(() => {
    const link: TextLinkStyles = { style: { color: blue } };
    return buildAnnotatedString((b) => {
      let at = 0;
      for (const m of text.matchAll(REF_LINK)) {
        appendLinked(b, text.substring(at, m.index), link);
        appendRef(b, new AnnotatedString(m[1]!), m[2]!, accent);
        at = m.index + m[0].length;
      }
      appendLinked(b, text.substring(at), link);
    });
  }, [text, accent, blue]);
}

// ── the web's own tones (styles/global.css.ts), where the message's parts use them ──

/** The web's --muted (a quote's words). */
export const webMuted = (C: StillFailColors) => (C.dark ? "#A3A5A9" : "#646970");
/** The web's --subtle. */
export const webSubtle = (C: StillFailColors) => (C.dark ? "#8C8F94" : "#73787D");
/** The web's --line (a table's rules). */
export const webLine = (C: StillFailColors) => (C.dark ? "#2D2E32" : "#E3E1DE");
/** A table's ground: the text at 2% in the canvas. */
const tableGround = (C: StillFailColors) => (C.dark ? "#232427" : "#FAFAFA");
/** A code block's ground: the text at 4% in the canvas; a table's header row too. */
export const codeGround = (C: StillFailColors) => (C.dark ? "#26272A" : "#F5F5F5");
const codeInline = (C: StillFailColors) => (C.dark ? "#C9A2E6" : "#7C3FA0");

// ── blocks ──────────────────────────────────────────────────────────────

/** A block with the margins the web gives it, above and below. */
interface Piece { top: number; bottom: number; draw: () => ReactNode }

interface Ctx { size: number; placing: Placing | null | undefined; fillTables: boolean; defs: ReadonlyMap<string, Definition> }

export function Markdown({ text, modifier, size = 15, placing, fillTables = false }: { text: string; modifier?: StyleProp<ViewStyle>; size?: number; placing?: Placing | null; fillTables?: boolean }) {
  const C = useC();
  const cached = useMemo(() => documentOf(text) ?? (text.length <= PARSED_AT_ONCE ? (prepareMarkdown(text), documentOf(text)) : undefined), [text]);
  const [ready, setReady] = useState<[string, MdDocument] | null>(cached ? [text, cached] : null);
  useEffect(() => {
    setReady(cached ? [text, cached] : null);
    if (cached) return;
    // A long one a frame later: the message is there at once, "laying out" a moment.
    const timer = setTimeout(() => {
      const doc = parseMarkdown(text);
      keepDocument(text, doc);
      setReady([text, doc]);
    }, 0);
    return () => clearTimeout(timer);
  }, [text]);
  const doc = ready?.[0] === text ? ready[1] : cached;
  const blocks = useMemo(() => (doc ? pieces(doc.root.children, { size, placing, fillTables, defs: doc.defs }, false, null, 0) : null), [doc, size, placing, fillTables]);
  return (
    <View style={modifier}>
      {blocks == null
        ? <Text style={{ color: webSubtle(C), fontSize: size, lineHeight: size * 1.4, includeFontPadding: false }}>{t("android-misc.markdown.laying")}</Text>
        : <Stack pieces={blocks} />}
    </View>
  );
}

/** Pieces one under another, as far apart as the larger margin between each two; the outer margins are the parent's. */
function Stack({ pieces }: { pieces: Piece[] }) {
  return (
    <View>
      {pieces.map((p, i) => {
        const gap = i > 0 ? Math.max(pieces[i - 1]!.bottom, p.top) : 0;
        return (
          <View key={i}>
            {gap > 0 && <View style={{ height: gap }} />}
            {p.draw()}
          </View>
        );
      })}
    </View>
  );
}

/** `task`: the box of a task item, given to its first paragraph. `lists`: how many lists this is in. */
function pieces(nodes: readonly Node[], ctx: Ctx, tight: boolean, task: boolean | null, lists: number): Piece[] {
  const firstParagraph = nodes.findIndex((n) => n.type === "paragraph");
  return nodes.flatMap((n, i) => piecesOf(n, ctx, tight, i === firstParagraph ? task : null, lists));
}

function piecesOf(node: Node, ctx: Ctx, tight: boolean, task: boolean | null, lists: number): Piece[] {
  const s = ctx.size;
  switch (node.type) {
    case "paragraph": return paragraph(node, ctx, tight ? 0 : s, task);
    case "heading": {
      const [em, margin] = node.depth === 5 ? [0.83, 1.67 * 0.83 * s] : node.depth === 6 ? [0.67, 2.33 * 0.67 * s] : [1, -1];
      const fs = s * em;
      const top = margin < 0 ? 14 : margin;
      const bottom = margin < 0 ? 6 : margin;
      return [{ top, bottom, draw: () => <Words nodes={node.children} ctx={ctx} size={fs} weight="700" /> }];
    }
    case "list": return [list(node, ctx, lists + 1)];
    case "blockquote": {
      const inner = pieces(node.children, ctx, false, null, lists);
      return [{
        top: Math.max(0, inner[0]?.top ?? 0),
        bottom: Math.max(8, inner[inner.length - 1]?.bottom ?? 0),
        draw: () => <Quote inner={inner} />,
      }];
    }
    case "code": {
      const language = node.lang?.trim().split(" ")[0] || null;
      const code = node.value.replace(/\n$/, "");
      if (language?.toLowerCase() === "mermaid" && code.trim() !== "") return [{ top: 0, bottom: 4, draw: () => <Mermaid code={code} /> }];
      return [{ top: 0, bottom: 8, draw: () => <CodeBlock code={code} language={language} /> }];
    }
    case "table": return [{ top: 0, bottom: 8, draw: () => <Table table={node} ctx={ctx} /> }];
    case "thematicBreak": return [{ top: s / 2, bottom: s / 2, draw: () => <Rule /> }];
    // Raw HTML is shown as written (react-markdown does not draw it).
    case "html": return [{ top: s, bottom: s, draw: () => <MdText raw={new AnnotatedString(node.value.trimEnd())} fontSize={ctx.size} lineHeight={lh(ctx.size)} /> }];
    // A link's definition draws nothing (commonmark-java's LinkReferenceDefinition has no children either).
    case "definition": return [];
    default: return pieces(childrenOf(node), ctx, tight, null, lists);
  }
}

function Rule() {
  const C = useC();
  return <View style={{ alignSelf: "stretch", height: 1, backgroundColor: webLine(C) }} />;
}

function Quote({ inner }: { inner: Piece[] }) {
  const C = useC();
  return (
    <View style={{ flexDirection: "row", alignItems: "stretch" }}>
      <View style={{ width: 2, backgroundColor: C.lineStrong }} />
      <View style={{ paddingLeft: 10, flex: 1, minWidth: 0 }}>
        <LocalMdInk.Provider value={webMuted(C)}><Stack pieces={inner} /></LocalMdInk.Provider>
      </View>
    </View>
  );
}

const lh = (size: number) => size * 1.65;

/** The ink of the words here: a quote's words are the web's muted. */
export const LocalMdInk = createContext<string | null>(null);

const blankText = (n: Node) => n.type === "text" && n.value.trim() === "";

/**
 * A paragraph; with files placed, one that is only a link to one of them is that file shown (a line of its own), and
 * one of only their images is them in a row. An image of theirs among words is shown between the words around it.
 */
function paragraph(node: Paragraph, ctx: Ctx, margin: number, task: boolean | null): Piece[] {
  const placing = ctx.placing;
  if (placing != null && placing.files.size > 0) {
    const parts = node.children.filter((n) => !blankText(n));
    const fileOf = (n: Node): Attachment | undefined =>
      n.type === "link" || n.type === "image" ? placing.files.get(fileNameOf(n.url))
        : n.type === "linkReference" || n.type === "imageReference" ? (() => { const d = ctx.defs.get(normal(n.identifier)); return d ? placing.files.get(fileNameOf(d.url)) : undefined; })()
        : undefined;
    const isImage = (n: Node) => n.type === "image" || n.type === "imageReference";
    const only = parts.length === 1 ? parts[0]! : null;
    if (only && (only.type === "link" || only.type === "linkReference") && task == null) {
      const f = fileOf(only);
      if (f) return [{ top: 8, bottom: 8, draw: () => placing.shown(f) }];
    }
    const images = parts.map((n) => (isImage(n) ? fileOf(n) : undefined));
    if (images.length > 1 && images.every((f) => f != null) && task == null) return [{ top: 8, bottom: 8, draw: () => <ImageRow files={images as Attachment[]} placing={placing} /> }];
    // Images of the message's among words: the words before, the image on a line of its own, the words after.
    if (parts.some((n) => isImage(n) && fileOf(n) != null)) {
      const out: Piece[] = [];
      let run: PhrasingContent[] = [];
      const flush = () => {
        const nodes = run;
        const box = out.length === 0 ? task : null;
        if (nodes.some((n) => !blankText(n))) out.push({ top: margin, bottom: margin, draw: () => <Words nodes={nodes} ctx={ctx} size={ctx.size} task={box} /> });
        run = [];
      };
      for (const n of node.children) {
        const f = isImage(n) ? fileOf(n) : undefined;
        if (f) { flush(); out.push({ top: margin, bottom: margin, draw: () => <View style={{ paddingVertical: 8 }}>{placing.shown(f)}</View> }); }
        else run.push(n);
      }
      flush();
      return out;
    }
  }
  return [{ top: margin, bottom: margin, draw: () => <Words nodes={node.children} ctx={ctx} size={ctx.size} task={task} /> }];
}

const ratioOf = (f: Attachment, low: number, high: number) =>
  f.width != null && f.height != null && f.height > 0 ? Math.min(high, Math.max(low, f.width / f.height)) : 1.5;

/**
 * Images written in one paragraph: side by side, wrapping onto the next line when a line is full. Each is as wide as
 * its shape asks (a line's images share one height, 120 or a little more, 200 at most), as the web's flex row has it.
 */
function ImageRow({ files, placing }: { files: Attachment[]; placing: Placing }) {
  const [full, setFull] = useState<number | null>(null);
  const ratios = files.map((f) => ratioOf(f, 0.25, 4));
  const gap = 8;
  let body: ReactNode = null;
  if (full != null) {
    // Lines as flex-wrap fills them: by each image's basis (120 × its ratio).
    const lines: number[][] = [];
    let used = 0;
    ratios.forEach((r, i) => {
      const basis = r * 120;
      if (lines.length === 0 || (used + gap + basis > full && lines[lines.length - 1]!.length > 0)) { lines.push([i]); used = basis; }
      else { lines[lines.length - 1]!.push(i); used += gap + basis; }
    });
    body = (
      <View style={{ gap }}>
        {lines.map((line, k) => {
          // Grown in proportion to their ratios, each kept to 200 × its ratio at most.
          const free = full - gap * (line.length - 1);
          const basis = line.reduce((a, i) => a + ratios[i]! * 120, 0);
          const grow = line.reduce((a, i) => a + ratios[i]!, 0);
          const extra = Math.max(0, (free - basis) / grow);
          return (
            <View key={k} style={{ flexDirection: "row", gap }}>
              {line.map((i) => {
                const r = ratios[i]!;
                const w = Math.min(r * 120 + r * extra, r * 200, free);
                return <View key={i}>{placing.row(files[i]!, { width: w, height: w / r })}</View>;
              })}
            </View>
          );
        })}
      </View>
    );
  }
  return <View style={{ alignSelf: "stretch" }} onLayout={(e) => setFull(e.nativeEvent.layout.width)}>{body}</View>;
}

/** Items with their markers in the list's 20 of indent, so wrapped lines hang under the words. */
function list(node: List, ctx: Ctx, depth: number): Piece {
  // Tight as commonmark has it: no item apart from the next by a blank line, nor within itself.
  const tight = !(node.spread || node.children.some((i) => i.spread));
  const items: Piece[] = node.children.map((item, i) => {
    const task = taskOf(item);
    const inner = pieces(item.children, ctx, tight, task, depth);
    return {
      top: inner[0]?.top ?? 0,
      bottom: inner[inner.length - 1]?.bottom ?? 0,
      draw: () => <Item ordered={node.ordered ? (node.start ?? 1) + i : null} depth={depth} size={ctx.size} inner={inner} />,
    };
  });
  return { top: Math.max(0, items[0]?.top ?? 0), bottom: Math.max(8, items[items.length - 1]?.bottom ?? 0), draw: () => <Stack pieces={items} /> };
}

function Item({ ordered, depth, size, inner }: { ordered: number | null; depth: number; size: number; inner: Piece[] }) {
  const C = useC();
  const ink = useContext(LocalMdInk) ?? C.ink;
  return (
    <View style={{ flexDirection: "row" }}>
      {ordered != null
        ? <Text numberOfLines={1} ellipsizeMode="clip" style={{ color: ink, fontSize: size, lineHeight: lh(size), textAlign: "right", width: 20, paddingRight: 5, includeFontPadding: false, letterSpacing: 0 }}>{`${ordered}.`}</Text>
        : <Bullet depth={depth} textSize={size} ink={ink} />}
      <View style={{ flex: 1, minWidth: 0 }}><Stack pieces={inner} /></View>
    </View>
  );
}

/**
 * A bulleted item's marker as the browser draws it outside the item (`disc`, then `circle`, then `square`): a third
 * of the text's size across, its middle 15 of the indent's 20 before the words, on the first line's middle.
 */
function Bullet({ depth, textSize, ink }: { depth: number; textSize: number; ink: string }) {
  const side = textSize / 3;
  const mark: ViewStyle = depth === 1 ? { backgroundColor: ink, borderRadius: side / 2 }
    : depth === 2 ? { borderWidth: 1, borderColor: ink, borderRadius: side / 2 }
    : { backgroundColor: ink };
  return (
    <View style={{ width: 20, height: lh(textSize), justifyContent: "center" }}>
      <View style={[{ marginLeft: 5 - side / 2, width: side, height: side }, mark]} />
    </View>
  );
}

/** A task item's box: checked or not, or null when the item is no task. */
function taskOf(item: ListItem): boolean | null {
  return item.checked ?? null;
}

/**
 * A code block as the web phone draws it: a quiet tinted block with no frame; above the code, on a row of its own
 * (there is no hover to bring the corner forward), its language and a copy button; highlighted when its language is
 * named. It scrolls sideways rather than wrapping.
 */
export function CodeBlock({ code, language, bar = true, modifier }: { code: string; language: string | null | undefined; bar?: boolean; modifier?: StyleProp<ViewStyle> }) {
  const C = useC();
  const [copied, setCopied] = useState(false);
  useEffect(() => {
    if (!copied) return;
    const timer = setTimeout(() => setCopied(false), 1500);
    return () => clearTimeout(timer);
  }, [copied]);
  return (
    <Smooth radius={12} style={[modifier, { alignSelf: "stretch", backgroundColor: codeGround(C) }]}>
      {bar && (
        <View style={{ flexDirection: "row", paddingLeft: 4, paddingRight: 4, paddingTop: 4, height: 28, justifyContent: "flex-end", alignItems: "center" }}>
          <Text style={{ fontSize: 10, lineHeight: 14, letterSpacing: 0.2, color: webSubtle(C), paddingHorizontal: 6, includeFontPadding: false }}>{language ?? "text"}</Text>
          <Smooth radius={6} style={{ height: 24, backgroundColor: withAlpha(C.surface, 0.8) }}>
            <Pressable
              onPress={() => { void Clipboard.setStringAsync(code); setCopied(true); }}
              android_ripple={{ color: withAlpha(C.ink, 0.12), borderless: false }}
              style={{ height: 24, flexDirection: "row", alignItems: "center", gap: 4, paddingHorizontal: 7 }}
            >
              <Icon icon={copied ? Icons.Check : Icons.Copy} size={12} color={webMuted(C)} />
              <Text style={{ fontSize: 11, lineHeight: 15.4, color: webMuted(C), includeFontPadding: false }}>{copied ? t("common.copied") : t("common.copy")}</Text>
            </Pressable>
          </Smooth>
        </View>
      )}
      <ScrollView horizontal nestedScrollEnabled showsHorizontalScrollIndicator={false} style={{ alignSelf: "stretch" }} contentContainerStyle={{ paddingHorizontal: 14, paddingVertical: 12 }}>
        <CodeInk code={code} language={language} dark={C.dark} />
      </ScrollView>
    </Smooth>
  );
}

/** Code blocks' weight: the code face's regular, as the web's SF Mono / Menlo. */
export const CodeWeight = "400" as const;

/** A cell's words, as the table draws them: the header row's 12, muted and medium; the rest 13. */
function cellWords(cell: TableCell, header: boolean, ctx: Ctx, measure?: "min" | "max") {
  return header
    ? <Words nodes={cell.children} ctx={ctx} size={12} weight="500" measure={measure} />
    : <Words nodes={cell.children} ctx={ctx} size={13} measure={measure} />;
}

/**
 * A table as the web draws it: in a card's frame (20 round, a faint ground), small type (13), the header row tinted
 * and its words muted (12), rows ruled between them only, their words kept whole (a cell wraps between words), at
 * least 4em wide. Columns are as wide as their content until the message is full (the browser's automatic layout);
 * past what its words allow, it scrolls sideways within the message.
 *
 * Compose measures each cell's least and most width (its intrinsics) as it lays the table out; here each cell is laid
 * out once, unseen, as wide as its words on one line and as wide as its widest word, and the table drawn from those.
 */
function Table({ table, ctx }: { table: MdTable; ctx: Ctx }) {
  const C = useC();
  const cells = table.children.map((r) => r.children);
  const columns = cells.reduce((m, r) => Math.max(m, r.length), 0);
  const [avail, setAvail] = useState<number | null>(null);
  const [mins, setMins] = useState<Record<number, number>>({});
  const [maxs, setMaxs] = useState<Record<number, number>>({});
  useEffect(() => { setMins({}); setMaxs({}); }, [table]);
  if (columns === 0) return null;
  const line = webLine(C);
  const muted = webMuted(C);
  const least = 4 * 13 + 24;
  // The flat index of each cell (r * columns + c), as the Kotlin's measurables are.
  const flat: { r: number; c: number; cell: TableCell | undefined }[] = [];
  cells.forEach((row, r) => { for (let c = 0; c < columns; c++) flat.push({ r, c, cell: row[c] }); });
  const imagesOf = (cell: TableCell | undefined) => (cell ? cellImages(cell, ctx) : null);
  // What needs laying out to be known: a cell of words (an image cell's width is known from its files).
  const unknown = flat.filter(({ cell }) => cell != null && imagesOf(cell) == null);
  const measured = unknown.every((_, k) => mins[k] !== undefined && maxs[k] !== undefined);
  let widths: number[] | null = null;
  if (measured && avail != null) {
    const mn = new Array<number>(columns).fill(0);
    const mx = new Array<number>(columns).fill(0);
    let k = 0;
    for (const { c, cell } of flat) {
      let lo = least, hi = least;
      const images = imagesOf(cell);
      if (images) { const w = cellImagesWidth(images) + 24; lo = Math.max(least, w); hi = lo; }
      else if (cell) { lo = Math.max(least, mins[k]! + 24); hi = Math.max(least, maxs[k]! + 24); k++; }
      mn[c] = Math.max(mn[c]!, lo); mx[c] = Math.max(mx[c]!, hi);
    }
    const sumMin = mn.reduce((a, b) => a + b, 0);
    const sumMax = mx.reduce((a, b) => a + b, 0);
    if (sumMax <= avail && ctx.fillTables) {
      const extra = avail - sumMax;
      widths = mx.map((w, c) => w + Math.floor(extra / columns) + (c < extra % columns ? 1 : 0));
    } else if (sumMax <= avail) widths = mx;
    else if (sumMin >= avail) widths = mn;
    else widths = mn.map((w, c) => w + Math.round(((mx[c]! - w) * (avail - sumMin)) / (sumMax - sumMin)));
  }
  const total = widths?.reduce((a, b) => a + b, 0) ?? 0;
  return (
    <View style={{ alignSelf: "stretch" }} onLayout={(e) => setAvail(Math.floor(e.nativeEvent.layout.width) - 2)}>
      {!measured && (
        // Laid out unseen, unbounded sideways: each cell's words on one line, and broken at every chance.
        <ScrollView horizontal scrollEnabled={false} pointerEvents="none" style={{ position: "absolute", opacity: 0, left: 0, top: 0, height: 0 }}>
          <View style={{ alignItems: "flex-start" }}>
            {unknown.map(({ r, cell }, k) => (
              <View key={k}>
                <View style={{ alignSelf: "flex-start" }} onLayout={(e) => { const w = Math.ceil(e.nativeEvent.layout.width); setMaxs((m) => (m[k] === w ? m : { ...m, [k]: w })); }}>
                  {cellWords(cell!, r === 0, ctx, "max")}
                </View>
                <View style={{ alignSelf: "flex-start" }} onLayout={(e) => { const w = Math.ceil(e.nativeEvent.layout.width); setMins((m) => (m[k] === w ? m : { ...m, [k]: w })); }}>
                  {cellWords(cell!, r === 0, ctx, "min")}
                </View>
              </View>
            ))}
          </View>
        </ScrollView>
      )}
      {widths != null && avail != null && (
        <Smooth radius={20} stroke={{ width: 1, color: line }} style={{ alignSelf: "flex-start", backgroundColor: tableGround(C), padding: 1 }}>
          <ScrollView horizontal nestedScrollEnabled showsHorizontalScrollIndicator={false} style={{ width: Math.min(total, avail) }}>
            <View style={{ width: total }}>
              {cells.map((row, r) => {
                const header = r === 0;
                return (
                  <View key={r} style={{ flexDirection: "row", alignItems: "stretch" }}>
                    {Array.from({ length: columns }, (_, c) => {
                      const cell = row[c];
                      const images = imagesOf(cell);
                      // Middle-aligned, as the browser's cells are; a rule under every row but the last.
                      return (
                        <View key={c} style={{ width: widths![c], backgroundColor: header ? codeGround(C) : undefined, paddingHorizontal: 12, paddingVertical: 7, justifyContent: "center" }}>
                          {r < cells.length - 1 && <View style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: 1, backgroundColor: line }} />}
                          {images != null ? <CellImageRow files={images} placing={ctx.placing!} />
                            : cell != null && header ? <LocalMdInk.Provider value={muted}>{cellWords(cell, true, ctx)}</LocalMdInk.Provider>
                            : cell != null ? cellWords(cell, false, ctx)
                            : null}
                        </View>
                      );
                    })}
                  </View>
                );
              })}
            </View>
          </ScrollView>
        </Smooth>
      )}
    </View>
  );
}

/**
 * A cell of only the message's images (`| ![](before.png) | ![](after.png) |`): them, side by side, each 160 wide at
 * most (the web's cell has the image fill it, as the table lets it); null for any other cell, drawn as words.
 */
function cellImages(cell: TableCell, ctx: Ctx): Attachment[] | null {
  const placing = ctx.placing;
  if (!placing) return null;
  const parts = cell.children.filter((n) => !blankText(n));
  const files = parts.map((n) => (n.type === "image" ? placing.files.get(fileNameOf(n.url)) : n.type === "imageReference" ? (() => { const d = ctx.defs.get(normal(n.identifier)); return d ? placing.files.get(fileNameOf(d.url)) : undefined; })() : undefined));
  return files.length > 0 && files.every((f) => f != null) ? (files as Attachment[]) : null;
}

/** As wide as 160 for a wide image, as tall as 240 for a tall one. */
const cellImageWidth = (f: Attachment) => Math.min(160, 240 * ratioOf(f, 0.25, 4));
const cellImagesWidth = (files: Attachment[]) => files.reduce((a, f) => a + cellImageWidth(f), 0) + 6 * (files.length - 1);

function CellImageRow({ files, placing }: { files: Attachment[]; placing: Placing }) {
  return (
    <View style={{ flexDirection: "row", paddingVertical: 4, gap: 6 }}>
      {files.map((f, i) => {
        const r = ratioOf(f, 0.25, 4);
        const w = cellImageWidth(f);
        return <View key={i}>{placing.row(f, { width: w, height: w / r })}</View>;
      })}
    </View>
  );
}

// ── words ───────────────────────────────────────────────────────────────

const TASK = "task";

/**
 * A block's words: its inline parts drawn (and, for a task item's first paragraph, its box ahead of them). `measure`:
 * laid out unseen for a table's widths ("max" as they are, "min" broken at every chance).
 */
function Words({ nodes, ctx, size, weight, task = null, measure }: { nodes: readonly Node[]; ctx: Ctx; size: number; weight?: "500" | "700"; task?: boolean | null; measure?: "min" | "max" }) {
  const C = useC();
  const text = useMemo(() => inline(nodes, ctx, task, C), [nodes, ctx, task, C]);
  const inlines: Record<string, InlineTextContent> | undefined = task == null ? undefined : { [TASK]: { width: 25, height: 13, children: <TaskBox checked={task} /> } };
  if (measure) return <MeasureText raw={measure === "min" ? breakable(text) : text} fontSize={size} lineHeight={lh(size)} fontWeight={weight} inline={inlines} />;
  return <MdText raw={text} fontSize={size} lineHeight={lh(size)} fontWeight={weight} inline={inlines} />;
}

/**
 * A task's box, as the browser draws a disabled checkbox (13 across, 4 before it and 3 after, then the space before
 * the words): faint grey, filled and ticked when done.
 */
function TaskBox({ checked }: { checked: boolean }) {
  const C = useC();
  const faint = C.dark ? "#A0A0A066" : "#7676764D";
  return (
    <View style={{ height: "100%", paddingLeft: 4, paddingRight: 8, alignItems: "center", justifyContent: "center" }}>
      <View
        style={[{ width: 13, height: 13, borderRadius: 2, alignItems: "center", justifyContent: "center", overflow: "hidden" },
          checked ? { backgroundColor: faint } : { backgroundColor: withAlpha(C.surface, 0.6), borderWidth: 1, borderColor: faint }]}
      >
        {checked && <Icon icon={Icons.Check} size={11} color={C.dark ? withAlpha(C.ink, 0.7) : "#FFFFFF"} />}
      </View>
    </View>
  );
}

/** Inline code as the web has it: no box, the code face in its own colour, a little smaller. */
function inline(nodes: readonly Node[], ctx: Ctx, task: boolean | null, C: StillFailColors): AnnotatedString {
  const code: SpanStyle = { fontFamily: CODE_FONT, fontSizeEm: 0.9, color: codeInline(C) };
  // A web address alone in code: the code's face, the link's colour (the web's `a > code`).
  const codeLink: SpanStyle = { fontFamily: CODE_FONT, fontSizeEm: 0.9 };
  const link: TextLinkStyles = { style: { color: C.blue } };
  const accent = C.accent;
  const placing = ctx.placing;
  const b = new AnnotatedStringBuilder();
  if (task != null) b.appendInlineContent(TASK, task ? "[x]" : "[ ]");
  const urlOf = (n: Node): string | null => {
    if (n.type === "link" || n.type === "image") return n.url;
    if (n.type === "linkReference" || n.type === "imageReference") return ctx.defs.get(normal(n.identifier))?.url ?? null;
    return null;
  };
  // `inLink`: within a link's words, where an address is only words.
  const walk = (n: Node, inLink: boolean): void => {
    switch (n.type) {
      // A soft line break is a space (commonmark's SoftLineBreak).
      case "text": { const words = n.value.replace(/\n/g, " "); if (inLink) b.append(words); else appendLinked(b, words, link); return; }
      case "inlineCode":
        if (!inLink && isWebAddress(n.value)) b.withLink(LinkUrl(n.value.trim(), link), () => b.withStyle(codeLink, () => b.append(n.value)));
        else b.withStyle(code, () => b.append(n.value));
        return;
      case "emphasis": b.withStyle({ fontStyle: "italic" }, () => n.children.forEach((c) => walk(c, inLink))); return;
      case "strong": b.withStyle({ fontWeight: "700" }, () => n.children.forEach((c) => walk(c, inLink))); return;
      case "delete": b.withStyle({ textDecorationLine: "line-through" }, () => n.children.forEach((c) => walk(c, inLink))); return;
      case "link": case "linkReference": {
        const url = urlOf(n) ?? "";
        const file = placing?.files.get(fileNameOf(url));
        // A link within a sentence to one of the message's files: looks like any link, opens the file.
        if (file && placing) b.withLink(LinkClickable(`file:${file.path}`, link, () => placing.open(file)), () => n.children.forEach((c) => walk(c, true)));
        else if (isChatLink(url)) appendRef(b, buildAnnotatedString((r) => n.children.forEach((c) => r.append(inlineText(c)))), url, accent);
        // Opened as a tap on a link is (Annotated.openUri): still.fail's own links in the app (AppState.openLink), the rest by the system.
        else b.withLink(LinkUrl(url, link), () => n.children.forEach((c) => walk(c, true)));
        return;
      }
      // An image the app cannot fetch (only the message's own files are fetched, through the station): its words, leading to it.
      case "image": case "imageReference": {
        const url = urlOf(n) ?? "";
        const alt = n.alt ?? "";
        const words = alt.length > 0 ? new AnnotatedString(alt) : new AnnotatedString(fileNameOf(url));
        // One of the message's files (drawn as words only where it cannot be drawn itself): opens it.
        const file = placing?.files.get(fileNameOf(url));
        if (file && placing) b.withLink(LinkClickable(`file:${file.path}`, link, () => placing.open(file)), () => b.append(words));
        else b.withLink(LinkUrl(url, link), () => b.append(words));
        return;
      }
      case "break": b.append("\n"); return;
      case "html": b.append(n.value); return;
      default: childrenOf(n).forEach((c) => walk(c, inLink));
    }
  };
  nodes.forEach((n) => walk(n, false));
  return b.toAnnotatedString();
}

/** A node's words, plain. */
function inlineText(n: Node): string {
  switch (n.type) {
    case "text": return n.value.replace(/\n/g, " ");
    case "inlineCode": return n.value;
    case "break": return " ";
    case "image": case "imageReference": return n.alt ?? "";
    default: return childrenOf(n).map(inlineText).join("");
  }
}

/**
 * Words with a line break at every place a line may break (a space, between CJK characters): laid out on their own,
 * as wide as their widest word (Compose's least intrinsic width). Spans are kept where they were.
 */
function breakable(text: AnnotatedString): AnnotatedString {
  const s = text.text;
  const map: number[] = new Array(s.length + 1);
  let out = "";
  for (let i = 0; i < s.length; i++) {
    map[i] = out.length;
    const c = s[i]!;
    if (c === " " || c === "\t") out += "\n";
    else {
      out += c;
      if (/[⺀-鿿가-힯豈-﫿＀-￯　-〿]/.test(c) && i + 1 < s.length) out += "\n";
    }
  }
  map[s.length] = out.length;
  const at = (i: number) => map[Math.min(s.length, Math.max(0, i))]!;
  return new AnnotatedString(
    out,
    text.spanStyles.map((r) => ({ item: r.item, start: at(r.start), end: at(r.end) })),
    text.links.map((r) => ({ item: r.item, start: at(r.start), end: at(r.end) })),
    text.inlines.map((r) => ({ item: r.item, start: at(r.start), end: at(r.end) })),
  );
}

/** Words laid out unseen to be measured: as MdText draws them, without what marks or picks them. */
function MeasureText({ raw, fontSize, lineHeight, fontWeight, inline: inlineContent }: { raw: AnnotatedString; fontSize: number; lineHeight: number; fontWeight?: "500" | "700"; inline?: Record<string, InlineTextContent> }) {
  return <AnnotatedText text={raw} style={{ fontSize, lineHeight, fontWeight }} inlineContent={inlineContent} />;
}

function MdText({ raw, fontSize, lineHeight, fontWeight, inline: inlineContent }: { raw: AnnotatedString; fontSize: number; lineHeight: number; fontWeight?: "500" | "700"; inline?: Record<string, InlineTextContent> }) {
  const C = useC();
  const ink = useContext(LocalMdInk) ?? C.ink;
  // A search's words in bold where it led (TextMark.tsx); while a passage of them is picked, its links drawn but not to tap (Pick.tsx).
  const text = markWeight(pickedText(raw));
  // A passage a quote led to, marked in these words (TextMark.tsx).
  const [mark, laid] = passageMark(text.text);
  // A passage picked from them (Pick.tsx).
  const [pick, picking] = pickable(text.text);
  // A link held: its menu (Links.tsx).
  const [hold, held] = linkHold(text);
  return (
    <AnnotatedText
      text={text}
      modifier={thenText(mark, pick, hold)}
      style={{ color: ink, fontSize, lineHeight, fontWeight }}
      inlineContent={inlineContent}
      onTextLayout={(e) => { laid(e); picking(e); held(e); }}
    />
  );
}
