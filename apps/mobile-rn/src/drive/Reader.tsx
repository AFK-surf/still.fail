// A text of a drive, read (drive/Reader.kt, zdrive's reader, in still.fail's look): one column that scrolls, nothing
// over it until a tap brings the bars — frosted, floating over the page — and takes them away again. The top one says
// what and where (its chapter, how far) and searches; the bottom one steps chapters, jumps anywhere along a hairline with
// a knob, and opens the contents, the type and paper, and day or night. A hard-wrapped novel is reflowed into paragraphs,
// Markdown is drawn as Markdown, chapters (第X章, Chapter N, # headings) make the contents. Where it was left is kept on
// this device (drivePlace) and opened at next time.
import * as NavigationBar from "expo-navigation-bar";
import { setStatusBarStyle } from "expo-status-bar";
import { useEffect, useMemo, useRef, useState, useSyncExternalStore, type ReactNode } from "react";
import { FlatList, PixelRatio, Platform, Pressable, ScrollView, Text, TextInput, View, type CellRendererProps, type LayoutRectangle, type NativeScrollEvent, type NativeSyntheticEvent, type TextStyle } from "react-native";
import { Gesture, GestureDetector } from "react-native-gesture-handler";
import Animated, { runOnJS, useAnimatedStyle, useSharedValue, withTiming } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import Svg, { Polygon } from "react-native-svg";
import { core } from "../../../../web/src/core/react.ts";
import type { DrivePlace, ReaderPrefs } from "../../../../web/src/core/shapes.ts";
import { useReaderStyle } from "../../../../web/src/drive/readerStyle.ts";
import { SheetSpec, app } from "../AppState";
import { DriveCache } from "../data/DriveCache";
import { t } from "../i18n";
import { PickRow, fileSize } from "../ui/Controls";
import { Floating } from "../ui/Glass";
import { Icons, type IconPaths } from "../ui/IconSet";
import { Ease } from "../ui/Motion";
import { IconIn, Seg } from "../ui/Parts";
import { SheetGrab, SheetHead } from "../ui/Sheet";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { useC, withAlpha } from "../ui/Theme";
import { Progress, WaitPill } from "../ui/Waiting";
import { nameOf, parentOf } from "./DriveScreen";
import { MAX_NOVEL_BYTES, Novel, Paper, ReaderFamily, ReaderTypography, buildNovel, type PaperInk, type ReaderJump } from "./Novel";
import { folderOf } from "./Player";
import { MarkdownChunk, piecesOf, renderMarkdown, type MarkdownColors, type SpanStyle, type Styled } from "./ReaderMarkdown";
import { renderChunk, renderOffset, searchChunks, type TextMatch } from "./TextModel";

const ripple = (ink: string) => ({ color: withAlpha(ink, 0.1) });
const round = (size: number, ink: string) => ({ ripple: { ...ripple(ink), borderless: true, radius: size / 2 }, style: { width: size, height: size, borderRadius: size / 2, overflow: "hidden" as const, alignItems: "center" as const, justifyContent: "center" as const } });
const errorOf = (e: unknown) => (e instanceof Error ? e.message : String(e));
const TNUM: TextStyle = { fontVariant: ["tabular-nums"] };

/** A topic's first value (or its error), waited for at most `ms`: what the core holds on this device, no wait for a station. */
function firstOf<V>(topic: Record<string, unknown>, ms: number): Promise<V | undefined> {
  return new Promise((resolve) => {
    let off: (() => void) | null = null;
    let done = false;
    const end = (v: V | undefined) => { if (done) return; done = true; clearTimeout(timer); off?.(); resolve(v); };
    const timer = setTimeout(() => end(undefined), ms);
    off = core().subscribe(topic as never, (v) => end(v as V), () => end(undefined));
    if (done) off();
  });
}

/** How a text comes: how much of it so far (and of how much), then the text itself, or why not. */
type Opening =
  | { kind: "Coming"; got: number; of: number | null }
  | { kind: "Failed"; why: string }
  | { kind: "Ready"; novel: Novel; at: number | null };

/** The reader's state, which its page and its sheets (contents, search, type) share; drawn again as it changes. */
class Reading {
  #chunk: number;
  #within = 0;
  #jump: ReaderJump | null;
  #serial = 1;
  #query = "";
  #matches: TextMatch[] = [];
  #hit = -1;
  #version = 0;
  readonly #listeners = new Set<() => void>();

  constructor(readonly novel: Novel, start: [number, number]) {
    this.#chunk = start[0];
    this.#jump = start[1] > 0 ? { chunk: start[0], offset: start[1], serial: 1, lead: false } : null;
  }

  subscribe = (l: () => void) => { this.#listeners.add(l); return () => { this.#listeners.delete(l); }; };
  version = () => this.#version;
  #changed() { this.#version++; for (const l of this.#listeners) l(); }

  get chunk() { return this.#chunk; }
  set chunk(v) { if (v !== this.#chunk) { this.#chunk = v; this.#changed(); } }
  /** How far down its block the top of the screen is (0–1). */
  get within() { return this.#within; }
  set within(v) { if (v !== this.#within) { this.#within = v; this.#changed(); } }
  get jump() { return this.#jump; }
  get query() { return this.#query; }
  set query(v) { if (v !== this.#query) { this.#query = v; this.#changed(); } }
  get matches() { return this.#matches; }
  set matches(v) { this.#matches = v; this.#changed(); }
  get hit() { return this.#hit; }
  set hit(v) { if (v !== this.#hit) { this.#hit = v; this.#changed(); } }

  get last() { return Math.max(this.novel.chunks.length - 1, 0); }
  get fraction(): number { return Math.min(Math.max((this.#chunk + this.#within) / Math.max(this.novel.chunks.length, 1), 0), 1); }
  get offsetInChunk(): number { return Math.round((this.novel.chunks[this.#chunk] ?? "").length * this.#within); }
  /** The chapter the top of the screen is in (-1 before the first). */
  get chapter(): number {
    const within = this.offsetInChunk;
    return this.novel.chapters.findLastIndex((it) => it.chunk < this.#chunk || (it.chunk === this.#chunk && it.offset <= within));
  }
  /** Fewer than two markers is not a table of contents (one is usually a stray line that matched). */
  get hasChapters() { return this.novel.chapters.length >= 2; }

  jumpTo(chunk: number, offset: number) { this.#jump = { chunk: Math.min(Math.max(chunk, 0), this.last), offset, serial: ++this.#serial, lead: true }; this.#changed(); }
  jumpToFraction(fraction: number) { this.jumpTo(Math.round(fraction * this.last), 0); }
  step(delta: number) {
    if (this.#matches.length === 0) return;
    const n = this.#matches.length;
    this.hit = (((this.#hit + delta) % n) + n) % n;
    const m = this.#matches[this.#hit]!;
    this.jumpTo(m.chunk, m.start);
  }
}

const useReading = (r: Reading) => useSyncExternalStore(r.subscribe, r.version);

/** The text `path` of `root` on `station`, read. */
export function ReaderScreen({ station, root, path }: { station: string; root: string; path: string }) {
  const C = useC();
  const name = nameOf(path);
  // How it is laid out: the core's prefs (prefs.reader), the same on every page that reads.
  const prefs = useReaderStyle();
  const paper = Paper.of(prefs.paper);
  const typography = ReaderTypography.of(prefs);
  const p = paper.ink(C.dark);
  usePaperBars(p.dark, C.dark);
  const [opening, setOpening] = useState<Opening>({ kind: "Coming", got: 0, of: null });
  useEffect(() => {
    let live = true;
    const say = (o: Opening) => { if (live) setOpening(o); };
    say({ kind: "Coming", got: 0, of: null });
    void (async () => {
      try {
        // Kept on the phone by when it changed, as its folder says (DriveCache); one not in it is read each time.
        const entry = (await folderOf(station, root, parentOf(path))).find((it) => !it.dir && it.name === name);
        let bytes: Uint8Array;
        let size: number;
        if (entry !== undefined) {
          [bytes, size] = await DriveCache.bytes(app.api(station), root, path, entry.mtime, entry.size, MAX_NOVEL_BYTES, (got, of) => say({ kind: "Coming", got, of }));
        } else {
          let of: number | null = null;
          bytes = await app.api(station).driveBytes(root, path, MAX_NOVEL_BYTES, undefined, (got, total) => { of = total; say({ kind: "Coming", got, of: total }); });
          size = of ?? bytes.length;
        }
        const novel = buildNovel(name, bytes, size, size > bytes.length);
        // Where it was left on this device (held here: no wait for a station).
        const held = await firstOf<DrivePlace | null>({ topic: "drivePlace", station, root, path }, 1000);
        const at = typeof held?.at === "number" ? Math.trunc(held.at) : null;
        console.info("drive-reader", `open ${path}: ${novel.encoding}, ${novel.chapters.length} chapters, ${novel.length} chars; left at ${at} (${JSON.stringify(held)})`);
        say({ kind: "Ready", novel, at });
      } catch (e) {
        say({ kind: "Failed", why: errorOf(e) });
      }
    })();
    return () => { live = false; };
  }, [station, root, path]);

  return (
    <View style={{ flex: 1, backgroundColor: p.ground }}>
      {opening.kind === "Ready" ? (
        <Book station={station} root={root} path={path} novel={opening.novel} at={opening.at} p={p} typography={typography} />
      ) : (
        <>
          <View style={{ flex: 1, padding: 32, alignItems: "center", justifyContent: "center", gap: 10 }}>
            {/* Its size known: how much has come, a bar under the words; else a wait's pill on the paper (its words in the
                paper's grey), said only once it takes a while. */}
            {opening.kind === "Coming" ? (
              opening.of !== null && opening.of > 0 ? (
                <>
                  <T size={13} color={p.muted} align="center">{t("android-misc.drive.reader.loading.size", { got: fileSize(opening.got), size: fileSize(opening.of) })}</T>
                  <Progress part={opening.got / opening.of} style={{ maxWidth: 220 }} />
                </>
              ) : <WaitPill text={t("common.opening")} ground="transparent" ink={p.muted} />
            ) : (
              <T size={14} color={C.red} align="center">{t("android-misc.drive.reader.failed", { error: opening.why })}</T>
            )}
          </View>
          {/* The way back is there while it comes. */}
          <View style={{ position: "absolute", top: 0, left: 0, right: 0 }}>
            <TopBar p={p} title={name} sub="" onBack={() => app.pop()} />
          </View>
        </>
      )}
    </View>
  );
}

/** The system bars' icons readable on the paper (`dark`: light icons); the app's again once the reader is gone. */
function usePaperBars(dark: boolean, appDark: boolean) {
  useEffect(() => {
    setStatusBarStyle(dark ? "light" : "dark");
    if (Platform.OS === "android") NavigationBar.setStyle(dark ? "dark" : "light");
    return () => {
      setStatusBarStyle(appDark ? "light" : "dark");
      if (Platform.OS === "android") NavigationBar.setStyle(appDark ? "dark" : "light");
    };
  }, [dark, appDark]);
}

function Book({ station, root, path, novel, at, p, typography }: { station: string; root: string; path: string; novel: Novel; at: number | null; p: PaperInk; typography: ReaderTypography }) {
  const r = useMemo(() => new Reading(novel, at !== null ? novel.at(at) : [0, 0]), [novel]);
  useReading(r);
  const insets = useSafeAreaInsets();
  const [chrome, setChrome] = useState(false);
  // The bars drawn while they show or fade (Compose's `shown > 0f`).
  const [present, setPresent] = useState(false);
  const shown = useSharedValue(0);
  useEffect(() => {
    if (chrome) setPresent(true);
    shown.value = withTiming(chrome ? 1 : 0, { duration: 180, easing: Ease.Standard }, (finished) => { if (finished && !chrome) runOnJS(setPresent)(false); });
  }, [chrome]);
  const fade = useAnimatedStyle(() => ({ opacity: shown.value }));

  // Where it was left, written as the reader stops (not on every pixel), and as the page goes.
  const keep = () => {
    const at2 = novel.offsetOf(r.chunk, r.within);
    app.scope.launch(() => app.api(station).drivePlace(root, path, at2, novel.length).catch((e: unknown) => console.warn("drive-reader", `place not kept: ${(e as { code?: string }).code} ${errorOf(e)}`)));
  };
  const keepRef = useRef(keep);
  keepRef.current = keep;
  useEffect(() => {
    let last = `${r.chunk}|${Math.trunc(r.within * 50)}`;
    let timer: ReturnType<typeof setTimeout> | null = setTimeout(() => keepRef.current(), 800);
    const off = r.subscribe(() => {
      const now = `${r.chunk}|${Math.trunc(r.within * 50)}`;
      if (now === last) return;
      last = now;
      if (timer) clearTimeout(timer);
      timer = setTimeout(() => keepRef.current(), 800);
    });
    return () => { off(); if (timer) clearTimeout(timer); keepRef.current(); };
  }, [r]);

  useEffect(() => {
    if (r.query.trim().length === 0) { r.matches = []; r.hit = -1; return; }
    const timer = setTimeout(() => { r.matches = searchChunks(novel.chunks, r.query); r.hit = -1; }, 250);
    return () => clearTimeout(timer);
  }, [r, r.query]);

  const chapter = r.chapter;
  const sub = [
    chapter >= 0 && r.hasChapters ? novel.chapters[chapter]!.title : null,
    novel.truncated ? t("android-misc.drive.reader.truncated", { size: fileSize(MAX_NOVEL_BYTES) }) : null,
  ].filter((it): it is string => it !== null).join(" · ");
  return (
    <View style={{ flex: 1 }}>
      <TextColumn r={r} typography={typography} p={p} onTap={() => setChrome((c) => !c)} />
      {/* The clock and the icons stay on the paper, not over the text running under them. */}
      <View style={{ position: "absolute", top: 0, left: 0, right: 0, height: insets.top, backgroundColor: p.ground }} />
      <View style={{ position: "absolute", top: 0, left: 0, right: 0, alignItems: "center" }} pointerEvents="box-none">
        <Animated.View style={[{ alignSelf: "stretch" }, fade]} pointerEvents={chrome ? "box-none" : "none"}>
          {present ? <TopBar p={p} title={novel.title} sub={sub} onBack={() => app.pop()} /> : null}
        </Animated.View>
        {/* Gone to a hit: where among them, a step to the one before and after, and away. */}
        {r.hit >= 0 && r.matches.length > 0 ? <FoundPill p={p} r={r} /> : null}
      </View>
      <Animated.View style={[{ position: "absolute", left: 0, right: 0, bottom: 0 }, fade]} pointerEvents={chrome ? "box-none" : "none"}>
        {present ? <BottomBar p={p} r={r} onChapters={() => openChapters(r)} onFind={() => openSearch(r)} onLayout={() => openLayout()} /> : null}
      </Animated.View>
    </View>
  );
}

/** Waits a frame (Compose's withFrameNanos). */
const frame = () => new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));

/** The column of text: one block of it per row of a lazy list; a tap shows or hides the bars. */
function TextColumn({ r, typography, p, onTap }: { r: Reading; typography: ReaderTypography; p: PaperInk; onTap: () => void }) {
  const novel = r.novel;
  const list = useRef<FlatList<string>>(null);
  const insets = useSafeAreaInsets();
  const padTop = insets.top + 12;
  const style = useMemo(() => typography.style(p.ink), [typography.key(), p]);
  const colors = useMemo<MarkdownColors>(() => ({ muted: p.muted, accent: p.accent, code: withAlpha(p.ink, 0.8) }), [p]);
  const mark = withAlpha(p.accent, p.dark ? 0.28 : 0.18);
  const markNow = withAlpha(p.accent, p.dark ? 0.55 : 0.42);
  const byChunk = useMemo(() => {
    const m = new Map<number, TextMatch[]>();
    for (const it of r.matches) { const l = m.get(it.chunk); if (l) l.push(it); else m.set(it.chunk, [it]); }
    return m;
  }, [r.matches]);
  // Where each block is in the list once laid out (the list's own cells), for the jumps and for where the reader is.
  const cells = useRef(new Map<number, LayoutRectangle>()).current;
  const scrollY = useRef(0);

  // A jump (a chapter, a hit, the slider) puts its block at the top, then slides to the offset in it once the block is
  // laid out (its height is not known before).
  const jump = r.jump;
  useEffect(() => {
    let live = true;
    const target = jump ?? (r.chunk > 0 ? { chunk: r.chunk, offset: 0, serial: 0, lead: false } : null);
    if (target === null) return;
    void (async () => {
      const index = Math.min(Math.max(target.chunk, 0), r.last);
      // The block brought into the list (it lays out only what is near), then put at the top.
      for (let tries = 0; live && !cells.has(index) && tries < 30; tries++) {
        try { list.current?.scrollToIndex({ index, animated: false, viewPosition: 0 }); } catch { /* not laid out near it yet */ }
        await frame();
      }
      if (!live) return;
      const at0 = cells.get(index);
      if (at0) list.current?.scrollToOffset({ offset: at0.y - padTop, animated: false });
      const drawn = drawnChunk(novel.chunks[index] ?? "", novel.markdown, typography, colors);
      if (target.offset <= 0 || drawn.text.length === 0) return;
      let height = cells.get(index)?.height ?? 0;
      let waited = 0;
      while (height <= 0 && waited++ < 4) { await frame(); height = cells.get(index)?.height ?? 0; }
      if (!live || height <= 0) return;
      const at = Math.min(Math.max(drawn.at(target.offset), 0), drawn.text.length);
      // A little of what is before it in view, under the top bar (120 px, as the Kotlin's scroll offset is in pixels).
      const into = Math.max(0, height * (at / drawn.text.length) - (target.lead ? 120 / PixelRatio.get() : 0));
      list.current?.scrollToOffset({ offset: cells.get(index)!.y - padTop + into, animated: false });
    })();
    return () => { live = false; };
  }, [jump]);

  const follow = (y: number) => {
    scrollY.current = y;
    // The block under the top of the page (after the room left above the first), and how far down it that is.
    const line = y + padTop;
    let index = -1;
    let cell: LayoutRectangle | undefined;
    for (const [i, c] of cells) if (c.y <= line && c.y + c.height > line && (index < 0 || i < index)) { index = i; cell = c; }
    if (index < 0 || cell === undefined) return;
    r.chunk = index;
    r.within = Math.min(Math.max(cell.height > 0 ? (line - cell.y) / cell.height : 0, 0), 1);
  };

  // The list's own cell, telling where it is laid out.
  const Cell = useMemo(() => function Cell({ index, style: cellStyle, onLayout, children }: CellRendererProps<string>) {
    return <View style={cellStyle} onLayout={(e) => { cells.set(index, e.nativeEvent.layout); onLayout?.(e); }}>{children}</View>;
  }, [cells]);

  const tap = Gesture.Tap().maxDistance(10).maxDuration(100_000).runOnJS(true).onEnd((_e, success) => { if (success) onTap(); });
  return (
    <GestureDetector gesture={tap}>
      <FlatList
        ref={list}
        style={{ flex: 1 }}
        data={novel.chunks}
        keyExtractor={(_raw, i) => String(i)}
        extraData={[byChunk, r.hit, style, colors, typography.indent]}
        initialNumToRender={3}
        windowSize={7}
        contentContainerStyle={{ paddingLeft: typography.marginDp, paddingRight: typography.marginDp, paddingTop: padTop, paddingBottom: insets.bottom + 200 }}
        onScroll={(e: NativeSyntheticEvent<NativeScrollEvent>) => follow(e.nativeEvent.contentOffset.y)}
        scrollEventThrottle={16}
        onScrollToIndexFailed={(info) => list.current?.scrollToOffset({ offset: info.averageItemLength * info.index, animated: false })}
        CellRendererComponent={Cell}
        renderItem={({ item: raw, index: i }) => (
          <Block raw={raw} markdown={novel.markdown} typography={typography} colors={colors} style={style} marks={byChunk.get(i) ?? NONE} now={r.matches[r.hit]?.chunk === i ? r.matches[r.hit]! : null} mark={mark} markNow={markNow} />
        )}
      />
    </GestureDetector>
  );
}

const NONE: TextMatch[] = [];

function Block({ raw, markdown, typography, colors, style, marks, now, mark, markNow }: {
  raw: string; markdown: boolean; typography: ReaderTypography; colors: MarkdownColors; style: TextStyle; marks: TextMatch[]; now: TextMatch | null; mark: string; markNow: string;
}) {
  const drawn = useMemo(() => drawnChunk(raw, markdown, typography, colors), [raw, typography.indent, typography.fontSp, colors]);
  const text = useMemo(() => drawn.marked(marks, now, mark, markNow), [drawn, marks, now, mark, markNow]);
  return <StyledText styled={text} style={[style, { paddingTop: drawn.leadingDp }]} />;
}

/** A styled text drawn: its pieces as Text inside one Text, each with the styles over it. */
function StyledText({ styled, style, numberOfLines }: { styled: Styled | string; style: TextStyle | TextStyle[]; numberOfLines?: number }) {
  if (typeof styled === "string") return <Text style={style} numberOfLines={numberOfLines}>{styled}</Text>;
  const pieces = piecesOf(styled);
  return (
    <Text style={style} numberOfLines={numberOfLines}>
      {pieces.map((it, i) => (Object.keys(it.style).length === 0 ? it.text : <Text key={i} style={it.style as TextStyle}>{it.text}</Text>))}
    </Text>
  );
}

/** A block as it is drawn: plain text with its paragraphs indented, or Markdown with the map back to the raw offsets search and jumps use. */
class DrawnChunk {
  constructor(readonly text: string, readonly leadingDp: number, private readonly raw: string | null, private readonly indent: boolean, private readonly markdown: MarkdownChunk | null) {}

  at(rawOffset: number): number { return this.markdown?.renderedIndex(rawOffset) ?? renderOffset(this.raw!, rawOffset, this.indent); }

  marked(marks: TextMatch[], current: TextMatch | null, color: string, currentColor: string): Styled | string {
    const md = this.markdown;
    if (marks.length === 0 && current === null) return md !== null ? md.styled : this.text;
    const length = this.text.length;
    const spans: Styled["spans"] = md !== null ? [...md.styled.spans] : [];
    const paint = (m: TextMatch, hue: string) => {
      const from = Math.min(Math.max(this.at(m.start), 0), length);
      const to = Math.min(Math.max(this.at(m.start + m.length), from), length);
      if (to > from) spans.push({ start: from, end: to, style: { backgroundColor: hue } });
    };
    marks.forEach((it) => paint(it, color));
    if (current !== null) paint(current, currentColor);
    return { text: this.text, spans };
  }
}

function drawnChunk(raw: string, markdown: boolean, typography: ReaderTypography, colors: MarkdownColors): DrawnChunk {
  if (!markdown) return new DrawnChunk(renderChunk(raw, typography.indent), 0, raw, typography.indent, null);
  const parsed = renderMarkdown(raw, typography.fontSp, colors);
  return new DrawnChunk(parsed.styled.text, parsed.leadingDp, null, false, parsed);
}

// ── the bars ────────────────────────────────────────────────────────────

/** Frosted glass of the paper's own bar colour, floating over the text: a breath of shadow, taps kept on it (ui/Glass.tsx Floating, GlassBlur). */
function PaperGlass({ radius, p, style, children }: { radius: number; p: PaperInk; style?: object; children: ReactNode }) {
  return (
    <Floating radius={radius} tint={p.bar} style={[{ backgroundColor: p.ground }, style]}>
      <View onStartShouldSetResponder={() => true} style={{ flexGrow: 1 }}>{children}</View>
    </Floating>
  );
}

function BarIcon({ icon, label, p, onClick }: { icon: IconPaths; label: string; p: PaperInk; onClick: () => void }) {
  const k = round(40, p.ink);
  return (
    <Pressable onPress={onClick} accessibilityLabel={label} android_ripple={k.ripple} style={k.style}>
      <IconIn icon={icon} size={20} tint={p.ink} />
    </Pressable>
  );
}

/** What is open and where in it: back, its name, its chapter under it. */
function TopBar({ p, title, sub, onBack }: { p: PaperInk; title: string; sub: string; onBack: () => void }) {
  const insets = useSafeAreaInsets();
  return (
    <View style={{ paddingTop: insets.top + 6, paddingBottom: 6, paddingHorizontal: 8 }}>
      <PaperGlass radius={16} p={p} style={{ height: 52 }}>
        <View style={{ flex: 1, paddingHorizontal: 4, justifyContent: "center" }}>
          <View style={{ position: "absolute", left: 4, top: 0, bottom: 0, justifyContent: "center" }}>
            <BarIcon icon={Icons.ChevronLeft} label={t("common.back")} p={p} onClick={onBack} />
          </View>
          <View style={{ paddingHorizontal: 48, alignItems: "center" }}>
            <T size={15} weight="600" color={p.ink} numberOfLines={1} align="center">{title}</T>
            {sub.length > 0 ? <T size={12} color={p.muted} numberOfLines={1} align="center">{sub}</T> : null}
          </View>
        </View>
      </PaperGlass>
    </View>
  );
}

/** A hit gone to: 「what」 which of how many, the one before and after, and the search let go. */
function FoundPill({ p, r }: { p: PaperInk; r: Reading }) {
  return (
    <View style={{ paddingTop: 6 }}>
      <PaperGlass radius={18} p={p} style={{ height: 40 }}>
        <View style={{ flex: 1, flexDirection: "row", alignItems: "center", gap: 2, paddingLeft: 14, paddingRight: 4 }}>
          <T size={13} color={p.ink} numberOfLines={1} style={[TNUM, { paddingRight: 6 }]}>{t("android-misc.drive.reader.foundAt", { query: r.query, at: r.hit + 1, n: r.matches.length })}</T>
          <BarIcon icon={Icons.ChevronLeft} label={t("android-misc.drive.reader.prevHit")} p={p} onClick={() => r.step(-1)} />
          <BarIcon icon={Icons.ChevronRight} label={t("android-misc.drive.reader.nextHit")} p={p} onClick={() => r.step(1)} />
          <BarIcon icon={Icons.Close} label={t("common.close")} p={p} onClick={() => { r.query = ""; r.hit = -1; }} />
        </View>
      </PaperGlass>
    </View>
  );
}

/** Chapters before and after, the jump along the whole text, and the contents, search, the layout. */
function BottomBar({ p, r, onChapters, onFind, onLayout }: { p: PaperInk; r: Reading; onChapters: () => void; onFind: () => void; onLayout: () => void }) {
  const insets = useSafeAreaInsets();
  const novel = r.novel;
  const ch = r.chapter;
  const before = ch > 0 ? novel.chapters[ch - 1]! : null;
  const after = novel.chapters[ch + 1] ?? null;
  return (
    <View style={{ paddingBottom: insets.bottom + 8, paddingTop: 8, paddingHorizontal: 8 }}>
      <PaperGlass radius={20} p={p}>
        <View style={{ paddingLeft: 14, paddingRight: 14, paddingTop: 10, paddingBottom: 6, gap: 6 }}>
          {r.hasChapters ? (
            <View style={{ flexDirection: "row", alignItems: "center" }}>
              <TextKey label={t("android-misc.drive.reader.prev")} p={p} onClick={before !== null ? () => r.jumpTo(before.chunk, before.offset) : null} />
              <T size={13} color={p.muted} numberOfLines={1} align="center" style={{ flex: 1, minWidth: 0, paddingHorizontal: 8 }}>
                {ch >= 0 ? novel.chapters[ch]!.title : t("android-misc.drive.reader.opening")}
              </T>
              <TextKey label={t("android-misc.drive.reader.next")} p={p} onClick={after !== null ? () => r.jumpTo(after.chunk, after.offset) : null} />
            </View>
          ) : null}
          <View style={{ flexDirection: "row", alignItems: "center", gap: 10 }}>
            <View style={{ flex: 1 }}>
              <Hairline fraction={r.fraction} track={withAlpha(p.ink, 0.14)} fill={p.accent} ring={p.bar} onPick={(it) => r.jumpToFraction(it)} />
            </View>
            <T size={12} weight="600" color={p.ink} align="right" style={[TNUM, { width: 40 }]}>{`${Math.round(r.fraction * 100)}%`}</T>
          </View>
          <View style={{ flexDirection: "row" }}>
            <Tool icon={Icons.List} label={t("android-misc.drive.reader.contents")} p={p} onClick={onChapters} />
            <Tool icon={Icons.Search} label={t("android-misc.drive.reader.search")} p={p} onClick={onFind} />
            <Tool icon={Icons.Text} label={t("android-misc.drive.reader.type")} p={p} onClick={onLayout} />
          </View>
        </View>
      </PaperGlass>
    </View>
  );
}

/** A small key on the bar (上一章, 下一章); faded and inert when there is nowhere to go. */
function TextKey({ label, p, onClick }: { label: string; p: PaperInk; onClick: (() => void) | null }) {
  return (
    <Smooth radius={10} style={{ backgroundColor: withAlpha(p.ink, onClick !== null ? 0.07 : 0.04) }}>
      <Pressable disabled={onClick === null} onPress={() => onClick?.()} android_ripple={ripple(p.ink)} style={{ paddingHorizontal: 12, paddingVertical: 6 }}>
        <T size={13} color={onClick !== null ? p.ink : withAlpha(p.ink, 0.3)} numberOfLines={1}>{label}</T>
      </Pressable>
    </Smooth>
  );
}

function Tool({ icon, label, p, onClick }: { icon: IconPaths; label: string; p: PaperInk; onClick: () => void }) {
  return (
    <Smooth radius={12} style={{ flex: 1 }}>
      <Pressable onPress={onClick} android_ripple={ripple(p.ink)} style={{ paddingVertical: 6, alignItems: "center", gap: 2 }}>
        <IconIn icon={icon} size={20} tint={p.ink} />
        <T size={11} color={p.muted}>{label}</T>
      </Pressable>
    </Smooth>
  );
}

/**
 * Where it is along the whole, to tap or drag to a place: a hairline, what is behind in the accent, a round knob. The
 * knob follows the finger while it drags; the text goes there once it is let go (re-laying a long text per pixel stutters).
 */
function Hairline({ fraction, track, fill, ring, onPick }: { fraction: number; track: string; fill: string; ring: string; onPick: (f: number) => void }) {
  const [draft, setDraftState] = useState(fraction);
  const drafted = useRef(fraction);
  const setDraft = (v: number) => { drafted.current = v; setDraftState(v); };
  const [dragging, setDragging] = useState(false);
  const [width, setWidth] = useState(1);
  useEffect(() => { if (!dragging) setDraft(fraction); }, [fraction]);
  const at = (x: number) => Math.min(Math.max(x / width, 0), 1);
  const tap = Gesture.Tap().runOnJS(true).onEnd((e, success) => { if (success) onPick(at(e.x)); });
  const drag = Gesture.Pan().activeOffsetX([-8, 8]).runOnJS(true)
    .onStart((e) => { setDragging(true); setDraft(at(e.x)); })
    .onUpdate((e) => setDraft(at(e.x)))
    .onEnd(() => { setDragging(false); onPick(drafted.current); })
    .onFinalize((_e, success) => { if (!success) setDragging(false); });
  const knob = dragging ? 8 : 6;
  const h = 2;
  const x = knob + (width - 2 * knob) * draft;
  return (
    <GestureDetector gesture={Gesture.Race(drag, tap)}>
      <View style={{ height: 28, justifyContent: "center" }} onLayout={(e) => setWidth(Math.max(e.nativeEvent.layout.width, 1))}>
        <View style={{ position: "absolute", left: 0, right: 0, top: 14 - h / 2, height: h, borderRadius: h / 2, backgroundColor: track }} />
        <View style={{ position: "absolute", left: 0, width: x, top: 14 - h / 2, height: h, borderRadius: h / 2, backgroundColor: fill }} />
        <View style={{ position: "absolute", left: x - (knob + 2), top: 14 - (knob + 2), width: (knob + 2) * 2, height: (knob + 2) * 2, borderRadius: knob + 2, backgroundColor: ring }} />
        <View style={{ position: "absolute", left: x - knob, top: 14 - knob, width: knob * 2, height: knob * 2, borderRadius: knob, backgroundColor: fill }} />
      </View>
    </GestureDetector>
  );
}

// ── the sheets ──────────────────────────────────────────────────────────

/** The contents: each chapter, the one being read checked; with none found, a jump by how far. */
function openChapters(r: Reading) {
  app.sheet = new SheetSpec(r.hasChapters ? 0.75 : 0.3, r.hasChapters, r.hasChapters ? null : 200, null, false, () => <ChaptersSheet r={r} />);
}

function ChaptersSheet({ r }: { r: Reading }) {
  const C = useC();
  useReading(r);
  const novel = r.novel;
  const now = r.chapter;
  const first = useRef(Math.max(now - 3, 0)).current;
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("android-misc.drive.reader.contents")} />
      {!r.hasChapters ? (
        <>
          <T size={13} color={C.muted} style={{ paddingHorizontal: 20, paddingVertical: 8 }}>{t("android-misc.drive.reader.noChapters")}</T>
          <View style={{ paddingHorizontal: 20 }}>
            <Hairline fraction={r.fraction} track={withAlpha(C.ink, 0.12)} fill={C.accent} ring={C.surface} onPick={(it) => r.jumpToFraction(it)} />
          </View>
        </>
      ) : (
        <FlatList
          style={{ flex: 1 }}
          contentContainerStyle={{ paddingBottom: 16 }}
          data={novel.chapters}
          initialScrollIndex={first}
          getItemLayout={(_d, i) => ({ length: CHAPTER_ROW, offset: CHAPTER_ROW * i, index: i })}
          keyExtractor={(_c, i) => String(i)}
          renderItem={({ item: c, index: i }) => <PickRow label={c.title} checked={i === now} onClick={() => { r.jumpTo(c.chunk, c.offset); app.sheet = null; }} />}
        />
      )}
    </>
  );
}

/** A PickRow with a title alone: its 12 above and below and a 15sp line (1.4 ×). */
const CHAPTER_ROW = 12 + 15 * 1.4 + 12;

/** Where a hit is, in a line: a little before it, it, a little after (as the web's search sheet lists them). */
function snippet(chunk: string, m: TextMatch, accent: string): Styled {
  const from = Math.max(m.start - 18, 0);
  const to = Math.min(m.start + m.length + 40, chunk.length);
  const clean = (s: string) => s.replaceAll("\n", " ").replaceAll("　", " ");
  const head = (from > 0 ? "…" : "") + clean(chunk.substring(from, m.start));
  const hit = clean(chunk.substring(m.start, Math.min(m.start + m.length, chunk.length)));
  const tail = clean(chunk.substring(Math.min(m.start + m.length, chunk.length), to)) + (to < chunk.length ? "…" : "");
  const style: SpanStyle = { color: accent, fontWeight: "600" };
  return { text: head + hit + tail, spans: [{ start: head.length, end: head.length + hit.length, style }] };
}

/** Search in the whole text: what is typed found as it is typed, each hit a line to go to; then the pill steps through them. */
function openSearch(r: Reading) {
  app.sheet = new SheetSpec(0.75, true, null, null, false, () => <SearchSheet r={r} />);
}

function SearchSheet({ r }: { r: Reading }) {
  const C = useC();
  useReading(r);
  const input = useRef<TextInput>(null);
  useEffect(() => {
    const timer = setTimeout(() => { if (r.query.length === 0) input.current?.focus(); }, 50);
    return () => clearTimeout(timer);
  }, []);
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("android-misc.drive.reader.search")} />
      <View style={{ paddingHorizontal: 20, gap: 10 }}>
        <View style={{ borderRadius: 999, borderWidth: 1, borderColor: C.line, paddingHorizontal: 18, paddingVertical: 11, overflow: "hidden" }}>
          <TextInput
            ref={input} value={r.query} onChangeText={(it) => { r.query = it; }} multiline={false} returnKeyType="search"
            placeholder={t("android-misc.drive.reader.searchAll")} placeholderTextColor={C.subtle} cursorColor={C.accent} selectionColor={withAlpha(C.accent, 0.4)}
            style={{ color: C.ink, fontSize: 15, padding: 0, includeFontPadding: false }}
          />
        </View>
        {r.query.trim().length > 0 ? (
          <T size={13} color={C.muted}>{r.matches.length === 0 ? t("android-misc.drive.reader.notFound") : t("android-misc.drive.reader.foundCount", { n: r.matches.length })}</T>
        ) : null}
      </View>
      <FlatList
        style={{ flex: 1, marginTop: 6 }}
        contentContainerStyle={{ paddingBottom: 16 }}
        keyboardShouldPersistTaps="handled"
        data={r.matches.slice(0, 300)}
        keyExtractor={(m) => `${m.chunk}:${m.start}`}
        renderItem={({ item: m, index: i }) => (
          <Pressable
            android_ripple={ripple(C.ink)} style={{ paddingHorizontal: 20, paddingVertical: 10 }}
            onPress={() => { input.current?.blur(); r.hit = i; r.jumpTo(m.chunk, m.start); app.sheet = null; }}
          >
            <StyledText styled={snippet(r.novel.chunks[m.chunk] ?? "", m, C.accent)} numberOfLines={2} style={{ fontSize: 15, lineHeight: 22, color: C.ink, letterSpacing: 0, includeFontPadding: false }} />
          </Pressable>
        )}
      />
    </>
  );
}

/** The layout: the type's size, the lines' height, the margins, the face, the indent and the paper, each kept by the core as it is changed. */
function openLayout() {
  app.sheet = new SheetSpec(0.62, true, null, null, false, () => <LayoutSheet />);
}

function LayoutSheet() {
  const C = useC();
  const prefs = useReaderStyle();
  const put = (shown: ReaderPrefs, field: keyof ReaderPrefs, value: string | number | boolean) => app.setReader(shown, field, value);
  return (
    <>
      <SheetGrab />
      <SheetHead title={t("android-misc.drive.reader.type")} />
      <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingHorizontal: 20, gap: 14 }}>
        <Stepper label={t("android-misc.drive.reader.size")} value={`${prefs.size}`} less={prefs.size > ReaderTypography.MIN_FONT_SP} more={prefs.size < ReaderTypography.MAX_FONT_SP}
          step={(d) => { const v = prefs.size + d; put({ ...prefs, size: v }, "size", v); }} />
        <Stepper label={t("android-misc.drive.reader.spacing")} value={prefs.line.toFixed(1)} less={prefs.line > ReaderTypography.MIN_LINE_SPACING + 1e-6} more={prefs.line < ReaderTypography.MAX_LINE_SPACING - 1e-6}
          step={(d) => { const v = Math.round((prefs.line + d * 0.1) * 10) / 10; put({ ...prefs, line: v }, "line", v); }} />
        <Stepper label={t("android-misc.drive.reader.margin")} value={`${prefs.margin}`} less={prefs.margin > ReaderTypography.MIN_MARGIN_DP} more={prefs.margin < ReaderTypography.MAX_MARGIN_DP}
          step={(d) => { const v = prefs.margin + d * 2; put({ ...prefs, margin: v }, "margin", v); }} />
        <SettingRow label={t("android-misc.drive.reader.font")}>
          <Seg options={ReaderFamily.entries.map((it) => it.label)} selected={ReaderFamily.of(prefs.face).ordinal} height={34}
            onSelect={(i: number) => { const f = ReaderFamily.entries[i]!.key as ReaderPrefs["face"]; put({ ...prefs, face: f }, "face", f); }} />
        </SettingRow>
        <SettingRow label={t("android-misc.drive.reader.indent")}>
          <Seg options={[t("android-misc.drive.reader.indent.on"), t("android-misc.drive.reader.indent.off")]} selected={prefs.indent ? 0 : 1} height={34}
            onSelect={(i: number) => put({ ...prefs, indent: i === 0 }, "indent", i === 0)} />
        </SettingRow>
        <View style={{ gap: 10 }}>
          <T size={15} color={C.ink}>{t("android-misc.drive.reader.paper")}</T>
          <View style={{ flexDirection: "row", justifyContent: "space-between" }}>
            {Paper.entries.map((option) => (
              <PaperSwatch key={option.key} option={option} chosen={option.key === prefs.paper} onClick={() => put({ ...prefs, paper: option.key as ReaderPrefs["paper"] }, "paper", option.key)} />
            ))}
          </View>
        </View>
        <View style={{ height: 12 }} />
      </ScrollView>
    </>
  );
}

/** A setting's name on the left, its control on the right. */
function SettingRow({ label, children }: { label: string; children: ReactNode }) {
  const C = useC();
  return (
    <View style={{ height: 44, flexDirection: "row", alignItems: "center" }}>
      <T size={15} color={C.ink} style={{ flex: 1 }}>{label}</T>
      {children}
    </View>
  );
}

/** A number stepped down and up (− value +), each step stopping at its end. */
function Stepper({ label, value, less, more, step }: { label: string; value: string; less: boolean; more: boolean; step: (d: number) => void }) {
  const C = useC();
  return (
    <SettingRow label={label}>
      <View style={{ flexDirection: "row", alignItems: "center", gap: 8 }}>
        <StepKey icon={Icons.Minus} label={t("android-misc.drive.reader.less", { what: label })} enabled={less} onClick={() => step(-1)} />
        <T size={17} weight="600" color={C.ink} align="center" style={[TNUM, { width: 48 }]}>{value}</T>
        <StepKey icon={Icons.Plus} label={t("android-misc.drive.reader.more", { what: label })} enabled={more} onClick={() => step(1)} />
      </View>
    </SettingRow>
  );
}

function StepKey({ icon, label, enabled, onClick }: { icon: IconPaths; label: string; enabled: boolean; onClick: () => void }) {
  const C = useC();
  const k = round(40, C.ink);
  return (
    <Pressable disabled={!enabled} onPress={onClick} accessibilityLabel={label} android_ripple={k.ripple} style={[k.style, { backgroundColor: withAlpha(C.ink, 0.07) }]}>
      <IconIn icon={icon} size={18} tint={enabled ? C.ink : C.subtle} />
    </Pressable>
  );
}

/** One paper, drawn in itself: 文 on its own ground, its name under it; the chosen one ringed in the accent. */
function PaperSwatch({ option, chosen, onClick }: { option: Paper; chosen: boolean; onClick: () => void }) {
  const C = useC();
  const ink = option.ink(C.dark);
  const inner = chosen ? 50 - 2 * 2 - 3 * 2 : 50 - 1 * 2;
  return (
    <Smooth radius={10}>
      <Pressable onPress={onClick} android_ripple={ripple(C.ink)} style={{ padding: 2, alignItems: "center", gap: 4 }}>
        <View style={{ width: 50, height: 50, borderRadius: 25, borderWidth: chosen ? 2 : 1, borderColor: chosen ? C.accent : C.line, padding: chosen ? 3 : 0, alignItems: "center", justifyContent: "center" }}>
          <View style={{ width: inner, height: inner, borderRadius: inner / 2, overflow: "hidden", backgroundColor: option === Paper.Follow ? Paper.White.ink(false).ground : ink.ground, alignItems: "center", justifyContent: "center" }}>
            {/* As the app looks: half its light page, half its dark one. */}
            {option === Paper.Follow ? (
              <Svg width={inner} height={inner} style={{ position: "absolute", left: 0, top: 0 }}>
                <Polygon points={`${inner},0 ${inner},${inner} 0,${inner}`} fill={Paper.Night.ink(true).ground} />
              </Svg>
            ) : null}
            <T size={18} color={option === Paper.Follow ? "#808080" : ink.ink} style={{ fontFamily: ReaderFamily.Serif.family }}>{t("android-misc.drive.reader.sample")}</T>
          </View>
        </View>
        <T size={12} color={chosen ? C.ink : C.muted}>{option.label}</T>
      </Pressable>
    </Smooth>
  );
}
