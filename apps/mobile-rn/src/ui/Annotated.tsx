// Compose's AnnotatedString as this app has it: words with spans of style, links and inline content over ranges of
// them, made with a builder as Compose's buildAnnotatedString makes them (`b.withStyle(style, () => b.append(…))`),
// and drawn by `AnnotatedText` as nested Texts, a run for each stretch the same spans cover. What the Android app's
// text parts do with an AnnotatedString (Markdown.kt, Highlight.kt, Links.kt's appendLinked, TextMark.kt, Pick.kt) is
// done here with this. A Builder extension of Kotlin's (`AnnotatedString.Builder.appendLinked(text, style)`) is a
// function taking the builder first (`appendLinked(b, text, style)`).
//
// The text hooks (TextMark.kt passageMark, Pick.kt pickable, Links.kt linkHold) give, as Compose's give a Modifier and
// what to hand the text's onTextLayout, a `TextModifier` (props put on the text, what is drawn behind it and over it in
// its box) and an onTextLayout of their own; `thenText` puts several together, as Modifier.then does.
import { Fragment, type ReactNode } from "react";
import { Linking, StyleSheet, Text, View, type NativeSyntheticEvent, type StyleProp, type TextLayoutEventData, type TextProps, type TextStyle } from "react-native";
import { app } from "../AppState";

/** A span's style (Compose's SpanStyle): only what is given changes the words under it. */
export interface SpanStyle {
  color?: string;
  fontWeight?: TextStyle["fontWeight"];
  fontStyle?: "normal" | "italic";
  fontFamily?: string;
  /** In sp, as Compose's fontSize in sp. */
  fontSize?: number;
  /** Relative to the text's own size, as Compose's `0.9.em`. */
  fontSizeEm?: number;
  letterSpacing?: number;
  textDecorationLine?: TextStyle["textDecorationLine"];
  backgroundColor?: string;
}

/** Compose's TextLinkStyles: how a link is drawn. */
export interface TextLinkStyles { style?: SpanStyle }

/** Compose's LinkAnnotation: an address to open (Url), or something of the app's to do on a tap (Clickable). */
export type LinkAnnotation =
  | { kind: "url"; url: string; styles?: TextLinkStyles }
  | { kind: "clickable"; tag: string; styles?: TextLinkStyles; onClick: () => void };

export const LinkUrl = (url: string, styles?: TextLinkStyles): LinkAnnotation => ({ kind: "url", url, styles });
export const LinkClickable = (tag: string, styles: TextLinkStyles | undefined, onClick: () => void): LinkAnnotation => ({ kind: "clickable", tag, styles, onClick });

/** A range of the words (`start` inclusive, `end` exclusive) and what is over it. */
export interface Range<T> { item: T; start: number; end: number }

export class AnnotatedString {
  constructor(
    readonly text: string,
    readonly spanStyles: readonly Range<SpanStyle>[] = [],
    readonly links: readonly Range<LinkAnnotation>[] = [],
    /** Inline content by its id, over the alternate text that stands for it. */
    readonly inlines: readonly Range<string>[] = [],
  ) {}
  get length(): number { return this.text.length; }
  isEmpty(): boolean { return this.text.length === 0; }
  /** The links over `start`..`end` (Compose's getLinkAnnotations). */
  getLinkAnnotations(start = 0, end = this.text.length): Range<LinkAnnotation>[] {
    return this.links.filter((l) => l.start < end && l.end > start);
  }
}

/** Compose's AnnotatedString.Builder. */
export class AnnotatedStringBuilder {
  #text = "";
  readonly #spans: Range<SpanStyle>[] = [];
  readonly #links: Range<LinkAnnotation>[] = [];
  readonly #inlines: Range<string>[] = [];

  constructor(from?: AnnotatedString) { if (from) this.append(from); }

  get length(): number { return this.#text.length; }

  /** Words (a part of them, `from` until `until`), or an AnnotatedString with what is over it. */
  append(text: string | AnnotatedString, from?: number, until?: number): void {
    if (typeof text === "string") {
      this.#text += from === undefined ? text : text.substring(from, until ?? text.length);
      return;
    }
    const at = this.#text.length;
    this.#text += text.text;
    for (const r of text.spanStyles) this.#spans.push({ item: r.item, start: r.start + at, end: r.end + at });
    for (const r of text.links) this.#links.push({ item: r.item, start: r.start + at, end: r.end + at });
    for (const r of text.inlines) this.#inlines.push({ item: r.item, start: r.start + at, end: r.end + at });
  }

  withStyle<T>(style: SpanStyle, block: () => T): T {
    const start = this.#text.length;
    // Pushed before what is inside it is, so a span inside (added after) is drawn over it, as Compose's are.
    const range = { item: style, start, end: start };
    this.#spans.push(range);
    try { return block(); } finally { range.end = this.#text.length; }
  }

  withLink<T>(link: LinkAnnotation, block: () => T): T {
    const start = this.#text.length;
    try { return block(); } finally { this.#links.push({ item: link, start, end: this.#text.length }); }
  }

  /** A place for inline content `id`, its words `alternateText` where it cannot be drawn (Compose's appendInlineContent). */
  appendInlineContent(id: string, alternateText = "�"): void {
    const start = this.#text.length;
    this.#text += alternateText;
    this.#inlines.push({ item: id, start, end: this.#text.length });
  }

  addStyle(style: SpanStyle, start: number, end: number): void { this.#spans.push({ item: style, start, end }); }

  addLink(link: LinkAnnotation, start: number, end: number): void { this.#links.push({ item: link, start, end }); }

  toAnnotatedString(): AnnotatedString {
    return new AnnotatedString(this.#text, this.#spans.filter((s) => s.end > s.start), this.#links.filter((l) => l.end > l.start), this.#inlines);
  }
}

export function buildAnnotatedString(block: (b: AnnotatedStringBuilder) => void): AnnotatedString {
  const b = new AnnotatedStringBuilder();
  block(b);
  return b.toAnnotatedString();
}

/** Inline content's room in the line (Compose's Placeholder, in sp) and what is drawn in it. */
export interface InlineTextContent { width: number; height: number; children: ReactNode }

/**
 * Opens a link as a tap on one does (App.kt's UriHandler): still.fail's own in the app (AppState.openLink), any other
 * by the system.
 */
export function openUri(url: string): void {
  app.openLink(url, false, null, () => { void Linking.openURL(url).catch(() => undefined); });
}

/** What a text hook puts on a text (a Modifier of Compose's, for a Text): its props, and what is drawn behind and over it. */
export interface TextModifier { props?: Partial<TextProps>; behind?: ReactNode; over?: ReactNode }
export type TextLayout = NativeSyntheticEvent<TextLayoutEventData>;
export const NoTextModifier: TextModifier = {};

/** Several text modifiers as one (Modifier.then): their props put together, handlers of the same name each called. */
export function thenText(...mods: TextModifier[]): TextModifier {
  const props: Record<string, unknown> = {};
  for (const m of mods) {
    for (const [k, v] of Object.entries(m.props ?? {})) {
      const was = props[k];
      if (typeof v === "function" && typeof was === "function") props[k] = (...a: unknown[]) => { (was as (...a: unknown[]) => void)(...a); (v as (...a: unknown[]) => void)(...a); };
      else if (k === "style" && was !== undefined) props[k] = [was, v];
      else props[k] = v;
    }
  }
  const behind = mods.map((m) => m.behind).filter((n) => n != null);
  const over = mods.map((m) => m.over).filter((n) => n != null);
  return {
    props: props as Partial<TextProps>,
    behind: behind.length ? <>{behind.map((n, i) => <Fragment key={i}>{n}</Fragment>)}</> : undefined,
    over: over.length ? <>{over.map((n, i) => <Fragment key={i}>{n}</Fragment>)}</> : undefined,
  };
}

function spanStyle(s: SpanStyle, base: number): TextStyle {
  const out: TextStyle = {};
  if (s.color !== undefined) out.color = s.color;
  if (s.fontWeight !== undefined) out.fontWeight = s.fontWeight;
  if (s.fontStyle !== undefined) out.fontStyle = s.fontStyle;
  if (s.fontFamily !== undefined) out.fontFamily = s.fontFamily;
  if (s.fontSize !== undefined) out.fontSize = s.fontSize;
  if (s.fontSizeEm !== undefined) out.fontSize = base * s.fontSizeEm;
  if (s.letterSpacing !== undefined) out.letterSpacing = s.letterSpacing;
  if (s.textDecorationLine !== undefined) out.textDecorationLine = s.textDecorationLine;
  if (s.backgroundColor !== undefined) out.backgroundColor = s.backgroundColor;
  return out;
}

/** The runs of an AnnotatedString: each stretch the same spans, link and inline content cover, drawn as one Text. */
export function annotatedRuns(text: AnnotatedString, base: number, inlineContent?: Record<string, InlineTextContent>): ReactNode[] {
  const s = text.text;
  if (text.spanStyles.length === 0 && text.links.length === 0 && text.inlines.length === 0) return [s];
  const cuts = new Set<number>([0, s.length]);
  for (const r of text.spanStyles) { cuts.add(r.start); cuts.add(r.end); }
  for (const r of text.links) { cuts.add(r.start); cuts.add(r.end); }
  for (const r of text.inlines) { cuts.add(r.start); cuts.add(r.end); }
  const at = [...cuts].filter((c) => c >= 0 && c <= s.length).sort((a, b) => a - b);
  const out: ReactNode[] = [];
  for (let k = 0; k + 1 < at.length; k++) {
    const from = at[k]!;
    const to = at[k + 1]!;
    if (to <= from) continue;
    const inline = text.inlines.find((r) => r.start <= from && r.end >= to);
    if (inline) {
      // Drawn once, where its words begin.
      if (inline.start !== from) continue;
      const content = inlineContent?.[inline.item];
      if (content) {
        out.push(<View key={`i${from}`} style={{ width: content.width, height: content.height }}>{content.children}</View>);
        continue;
      }
    }
    const styles: TextStyle[] = [];
    for (const r of text.spanStyles) if (r.start <= from && r.end >= to) styles.push(spanStyle(r.item, base));
    let link: LinkAnnotation | undefined;
    for (const r of text.links) if (r.start <= from && r.end >= to) link = r.item;
    if (link?.styles?.style) styles.push(spanStyle(link.styles.style, base));
    const words = s.substring(from, to);
    const onPress = link ? (link.kind === "url" ? ((url: string) => () => openUri(url))(link.url) : link.onClick) : undefined;
    out.push(
      <Text key={from} style={styles.length ? StyleSheet.flatten(styles) : undefined} onPress={onPress}>
        {words}
      </Text>,
    );
  }
  return out;
}

/**
 * An AnnotatedString drawn (Compose's Text(AnnotatedString)): the style given is the paragraph's (its size, line height,
 * ink), each run's spans over it. `modifier`: what the text hooks put on it.
 */
export function AnnotatedText({ text, style, inlineContent, modifier, onTextLayout, ...rest }: TextProps & { text: AnnotatedString; style?: StyleProp<TextStyle>; inlineContent?: Record<string, InlineTextContent>; modifier?: TextModifier }) {
  const flat = StyleSheet.flatten(style) ?? {};
  const base = typeof flat.fontSize === "number" ? flat.fontSize : 16;
  const props = modifier?.props ?? {};
  const laid = (e: TextLayout) => { onTextLayout?.(e); props.onTextLayout?.(e); };
  const body = (
    <Text {...rest} {...props} style={[{ letterSpacing: 0, includeFontPadding: false }, style, props.style]} onTextLayout={laid}>
      {annotatedRuns(text, base, inlineContent)}
    </Text>
  );
  if (!modifier?.behind && !modifier?.over) return body;
  return (
    <View>
      {modifier.behind}
      {body}
      {modifier.over}
    </View>
  );
}
