// A video or a song of a drive (drive/Player.kt), played as it streams through the core (DriveSource): nothing is
// fetched whole first, a seek far ahead is one more ranged read; what was played is kept (DriveCache's played) and plays
// again from the phone. Dark, as the chat's viewer of pictures is; its controls float over the picture, frosted, and
// fade when left alone (a tap brings them back): where it is and how much is buffered, play, the next in the folder, the
// speed, the subtitle beside it (E01.srt for E01.mp4), fit or fill, and sideways (landscape, the system bars away). A
// double tap on the left or right third jumps 15 s, in the middle it pauses or plays. Where it was left is kept on this
// device (drivePlace) and played on from next time. The player is expo-video's (media3's ExoPlayer on Android).
import * as NavigationBar from "expo-navigation-bar";
import * as ScreenOrientation from "expo-screen-orientation";
import { setStatusBarHidden, setStatusBarStyle } from "expo-status-bar";
import { VideoView, useVideoPlayer } from "expo-video";
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { BackHandler, Platform, Pressable, Text, View, type TextStyle } from "react-native";
import { Gesture, GestureDetector } from "react-native-gesture-handler";
import Animated, { useAnimatedStyle, useSharedValue, withTiming } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { core } from "../../../../web/src/core/react.ts";
import type { DriveEntry, DriveFolder, DrivePlace } from "../../../../web/src/core/shapes.ts";
import { app } from "../AppState";
import { DriveCache } from "../data/DriveCache";
import { t } from "../i18n";
import { Frost } from "../ui/Glass";
import { Icons, type IconPaths } from "../ui/IconSet";
import { Ease } from "../ui/Motion";
import { IconIn } from "../ui/Parts";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { useC } from "../ui/Theme";
import { WaitPill } from "../ui/Waiting";
import { join, nameOf, parentOf } from "./DriveScreen";
import { DriveSource, DriveUri, StreamStats } from "./DriveSource";
import { clock, nextIn, pickSubtitle, playlistOf, speedLabel } from "./Playlist";
import { decodeText, normaliseLineEndings } from "./TextModel";

const TAG = "drive-player";

/** Dark whatever the theme, as a viewer of pictures: its text, what is quieter. */
const Ink = "#F4F4F5";
const Muted = "rgba(255,255,255,0.6)";

/** The speeds offered, slowest first. */
const SPEEDS = [1, 1.25, 1.5, 2, 0.5, 0.75];
/** What a double tap on a side jumps. */
const NUDGE_MS = 15_000;
/** The controls fade after this long left alone while it plays. */
const REST_MS = 2500;
const TNUM: TextStyle = { fontVariant: ["tabular-nums"] };
const errorOf = (e: unknown) => (e instanceof Error ? e.message : String(e));

/** A topic's first value (or its error) the core holds, waited for at most `ms`; undefined when none came. */
function firstOf<V>(topic: Record<string, unknown>, ms: number, ready: (v: unknown) => boolean = () => true): Promise<{ value?: V; error?: unknown } | undefined> {
  return new Promise((resolve) => {
    let off: (() => void) | null = null;
    let done = false;
    const end = (v: { value?: V; error?: unknown } | undefined) => { if (done) return; done = true; clearTimeout(timer); off?.(); resolve(v); };
    const timer = setTimeout(() => end(undefined), ms);
    off = core().subscribe(topic as never, (v) => { if (ready(v)) end({ value: v as V }); }, (error) => end({ error }));
    if (done) off();
  });
}

/** The folder a file is in as last read (held on the device): its entries, for the playlist and the subtitle. */
export async function folderOf(station: string, root: string, dir: string): Promise<DriveEntry[]> {
  const got = await firstOf<DriveFolder>({ topic: "drive", station, root, path: dir }, 5000, (v) => v != null);
  return got?.value?.entries ?? [];
}

/** What is playing, in the terms a person cares about. */
enum Phase { Opening, Buffering, Playing, Paused, Ended, Failed }

/** media3's Player.STATE_*, as the player's events say them. */
enum State { Idle, Buffering, Ready, Ended }

/** A subtitle's line: from when to when (ms), what it says. */
interface Cue { from: number; to: number; text: string }

/**
 * The videos played (by their DriveUri) and what reads them: a stream through the core, kept as it is played under its
 * key when the folder says what it is (DriveCache.playedKey), else read without being kept.
 */
export const DriveStreams = new Map<string, { source: InstanceType<typeof DriveSource.Factory>; cacheKey: ((path: string) => string) | null }>();

/** The video or song `path` of `root` on `station`, played. */
export function PlayerScreen({ station, root, path }: { station: string; root: string; path: string }) {
  return <Playing key={path} station={station} root={root} path={path} />;
}

function Playing({ station, root, path }: { station: string; root: string; path: string }) {
  const C = useC();
  const insets = useSafeAreaInsets();
  const dir = parentOf(path);
  const name = nameOf(path);
  const api = useMemo(() => app.api(station), [station]);
  const stats = useMemo(() => new StreamStats(), []);
  const player = useVideoPlayer(null, (p) => { p.timeUpdateEventInterval = 0.25; p.audioMixingMode = "doNotMix"; });

  const [entries, setEntries] = useState<DriveEntry[]>([]);
  const [subtitle, setSubtitle] = useState<string | null>(null);
  const [subtitleCues, setSubtitleCues] = useState<Cue[]>([]);
  const [subtitlesOn, setSubtitlesOn] = useState(true);
  const [speed, setSpeed] = useState(1);
  const [fill, setFill] = useState(false);
  const [sideways, setSideways] = useState(false);
  const [awake, setAwake] = useState(true);
  const [poke, setPoke] = useState(0);
  const [note, setNote] = useState<string | null>(null);
  const [attempt, setAttempt] = useState(0);

  const [state, setState] = useState(State.Idle);
  const [playing, setPlaying] = useState(false);
  const [started, setStarted] = useState(false);
  const [failure, setFailure] = useState<string | null>(null);
  const [position, setPosition] = useState(0);
  const [duration, setDuration] = useState(0);
  const [buffered, setBuffered] = useState(0);
  const [video, setVideo] = useState<{ width: number; height: number } | null>(null);
  const openedAt = useRef(0);
  const startedRef = useRef(false);

  let phase: Phase;
  if (failure !== null) phase = Phase.Failed;
  else if (!started) phase = Phase.Opening;
  else if (state === State.Ended) phase = Phase.Ended;
  else if (state === State.Buffering) phase = Phase.Buffering;
  else if (playing) phase = Phase.Playing;
  else phase = Phase.Paused;
  const playable = (e: DriveEntry) => !e.dir && (e.kind === "video" || e.kind === "audio");
  const list = useMemo(() => playlistOf(entries.filter(playable).map((it) => it.name), () => true), [entries]);
  const next = useMemo(() => nextIn(name, list), [list, name]);
  const cues = subtitleCues.filter((c) => c.from <= position && position < c.to).map((c) => c.text).join("\n");

  // Everything the player needs to start: the folder (sizes, the subtitle beside it, what comes next) and where it was left.
  useEffect(() => {
    let live = true;
    setFailure(null); setStarted(false); startedRef.current = false;
    openedAt.current = Date.now();
    void (async () => {
      const held = await folderOf(station, root, dir);
      if (!live) return;
      setEntries(held);
      const sizes = new Map(held.filter((it) => !it.dir).map((it) => [join(dir, it.name), it.size] as const));
      const sub = pickSubtitle(name, held.filter((it) => !it.dir).map((it) => it.name));
      setSubtitle(sub);
      // Kept by when each changed, as the folder says: one not in it is played without being kept.
      const known = new Map(held.filter((it) => !it.dir).map((it) => [join(dir, it.name), it] as const));
      const upstream = new DriveSource.Factory(api, root, sizes, stats);
      const cacheKey = known.has(path) ? (p: string) => { const k = known.get(p); return k ? DriveCache.playedKey(station, root, p, k.mtime, k.size) : `${station}\n${root}\n${p}`; } : null;
      DriveStreams.set(DriveUri.of(path), { source: upstream, cacheKey });
      // A subtitle that does not read is no reason for the film to stop.
      if (sub !== null && subtitleKind(sub) !== null) {
        api.driveBytes(root, join(dir, sub), 4 * 1024 * 1024).then(
          (bytes: Uint8Array) => { if (live) setSubtitleCues(parseSubtitle(sub, normaliseLineEndings(decodeText(bytes).text))); },
          (e: unknown) => console.warn(TAG, `subtitle ${sub} not read: ${errorOf(e)}`),
        );
      }
      const place = (await firstOf<DrivePlace | null>({ topic: "drivePlace", station, root, path }, 1000))?.value;
      if (!live) return;
      const at = typeof place?.at === "number" ? Math.trunc(place.at) : 0;
      const of = typeof place?.of === "number" ? Math.trunc(place.of) : 0;
      try {
        // NATIVE: expo-video reads http(s), file and asset sources only: a media3 DataSource for the stillfail-drive scheme that opens and reads DriveStreams' DriveSource (open/read/close over drive.read, as DriveSource.kt) under a CacheDataSource on DriveCache.played() keyed by its cacheKey is missing; until then this source does not play.
        await player.replaceAsync({ uri: DriveUri.of(path), contentType: "progressive", useCaching: cacheKey !== null });
      } catch (e) {
        if (live) setFailure(errorOf(e));
        return;
      }
      // Left near its end: from the start again.
      if (at > 0 && (of <= 0 || at < of - 5_000)) player.currentTime = at / 1000;
      player.play();
      console.info(TAG, `open ${path} size=${sizes.get(path)} subtitle=${sub ?? "none"} resume=${at}ms`);
    })();
    return () => { live = false; };
  }, [path, attempt]);

  useEffect(() => {
    const subs = [
      player.addListener("statusChange", ({ status, error }) => {
        if (status === "loading") setState(State.Buffering);
        else if (status === "readyToPlay") {
          setState((s) => (s === State.Ended ? s : State.Ready));
          if (!startedRef.current) {
            startedRef.current = true;
            setStarted(true);
            console.info(TAG, `ready ${Date.now() - openedAt.current}ms after opening, ${stats.bytesRead}B read in ${stats.readCount} reads`);
          }
        } else if (status === "error") {
          setFailure(error?.message?.trim() ? error.message : "ERROR_CODE_UNSPECIFIED");
          console.warn(TAG, `playback failed: ${error?.message}`);
        } else setState(State.Idle);
      }),
      player.addListener("playingChange", ({ isPlaying }) => { setPlaying(isPlaying); if (isPlaying) setState(State.Ready); }),
      player.addListener("playToEnd", () => setState(State.Ended)),
      player.addListener("videoTrackChange", ({ videoTrack }) => {
        const size = videoTrack?.size;
        if (size && size.width > 0 && size.height > 0) setVideo({ width: size.width, height: size.height });
      }),
      player.addListener("sourceLoad", ({ availableVideoTracks }) => {
        const size = availableVideoTracks[0]?.size;
        if (size && size.width > 0 && size.height > 0) setVideo({ width: size.width, height: size.height });
      }),
    ];
    return () => subs.forEach((s) => s.remove());
  }, [player]);

  // Where it is, read off the player as it plays (it says nothing of it by itself); and kept, every few seconds.
  const last = useRef<[number, number]>([0, 0]);
  useEffect(() => {
    let tick = 0;
    const timer = setInterval(() => {
      const pos = Math.max(0, player.currentTime * 1000);
      const dur = Number.isFinite(player.duration) ? Math.max(0, player.duration * 1000) : 0;
      setPosition(pos);
      setDuration(dur);
      setBuffered(Math.max(0, player.bufferedPosition * 1000));
      last.current = [pos, dur];
      if (++tick % 20 === 0) {
        console.info(TAG, `pos=${Math.round(pos)}ms buffered=${Math.round(player.bufferedPosition * 1000)}ms read=${stats.bytesRead}B reads=${stats.readCount} window=${stats.windowBytes}B rate=${(stats.rate / 1048576).toFixed(1)}MB/s`);
        if (startedRef.current && dur > 0) keepPlace(station, root, path, pos, dur);
      }
    }, 250);
    return () => clearInterval(timer);
  }, [player]);
  useEffect(() => () => { if (last.current[1] > 0) keepPlace(station, root, path, last.current[0], last.current[1]); }, [path]);
  useEffect(() => { player.playbackRate = speed; }, [speed]);
  useEffect(() => { if (note === null) return; const timer = setTimeout(() => setNote(null), 800); return () => clearTimeout(timer); }, [note]);
  // A song has no picture to clear the way for: its controls stay.
  const audio = entries.find((it) => it.name === name)?.kind === "audio" || (started && video === null);
  useEffect(() => {
    if (!(awake && phase === Phase.Playing && !audio)) return;
    const timer = setTimeout(() => setAwake(false), REST_MS);
    return () => clearTimeout(timer);
  }, [awake, phase, poke, audio]);

  // Sideways: landscape asked for (a phone with rotation locked turns too) and the system bars away; back, upright.
  useEffect(() => {
    if (Platform.OS === "android") void NavigationBar.setBehaviorAsync("overlay-swipe").catch(() => undefined);
    setStatusBarHidden(sideways, "fade");
    if (Platform.OS === "android") void NavigationBar.setVisibilityAsync(sideways ? "hidden" : "visible").catch(() => undefined);
    void (sideways ? ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.LANDSCAPE) : ScreenOrientation.unlockAsync()).catch(() => undefined);
    return () => {
      if (!sideways) return;
      setStatusBarHidden(false, "fade");
      if (Platform.OS === "android") void NavigationBar.setVisibilityAsync("visible").catch(() => undefined);
      void ScreenOrientation.unlockAsync().catch(() => undefined);
    };
  }, [sideways]);
  // The bars' icons light over the black page, as the app's again once it goes.
  useEffect(() => {
    setStatusBarStyle("light");
    if (Platform.OS === "android") NavigationBar.setStyle("dark");
    return () => {
      setStatusBarStyle(C.dark ? "light" : "dark");
      if (Platform.OS === "android") NavigationBar.setStyle(C.dark ? "dark" : "light");
    };
  }, []);
  useEffect(() => {
    if (!sideways) return;
    const sub = BackHandler.addEventListener("hardwareBackPress", () => { setSideways(false); return true; });
    return () => sub.remove();
  }, [sideways]);

  const wake = () => { setAwake(true); setPoke((n) => n + 1); };
  const playPause = () => {
    if (state === State.Ended) { player.currentTime = 0; setState(State.Ready); }
    if (player.playing) player.pause(); else player.play();
  };
  const seekBy = (delta: number) => {
    const end = Number.isFinite(player.duration) && player.duration > 0 ? player.duration * 1000 : null;
    const to = Math.max(0, player.currentTime * 1000 + delta);
    player.currentTime = (end !== null ? Math.min(to, end) : to) / 1000;
    if (state === State.Ended && delta < 0) setState(State.Ready);
  };
  const open = (other: string) => { player.pause(); app.replace({ kind: "DrivePlay", station, root, path: join(dir, other) }); };

  const shownOn = awake || phase !== Phase.Playing || audio;
  const shown = useSharedValue(1);
  const [shownNow, setShownNow] = useState(1);
  useEffect(() => {
    shown.value = withTiming(shownOn ? 1 : 0, { duration: 200, easing: Ease.Standard });
    setShownNow(shownOn ? 1 : 0);
  }, [shownOn]);
  const fade = useAnimatedStyle(() => ({ opacity: shown.value }));
  const controls = shownNow > 0;

  // A tap shows or hides the controls; a double tap on a side jumps, in the middle pauses or plays.
  const [width, setWidth] = useState(1);
  const single = Gesture.Tap().runOnJS(true).onEnd((_e, ok) => { if (!ok) return; if (awake && phase === Phase.Playing) setAwake(false); else wake(); });
  const double = Gesture.Tap().numberOfTaps(2).runOnJS(true).onEnd((e, ok) => {
    if (!ok) return;
    const third = width / 3;
    if (e.x < third) { seekBy(-NUDGE_MS); setNote(t("android-misc.drive.player.back", { n: NUDGE_MS / 1000 })); }
    else if (e.x > third * 2) { seekBy(NUDGE_MS); setNote(t("android-misc.drive.player.ahead", { n: NUDGE_MS / 1000 })); }
    else { const was = player.playing; playPause(); setNote(was ? t("android-misc.drive.player.paused") : t("android-misc.drive.player.playing")); }
  });

  const index = list.indexOf(name);
  const prev = index > 0 ? list[index - 1]! : null;
  return (
    <View style={{ flex: 1, backgroundColor: "#000000" }} onLayout={(e) => setWidth(e.nativeEvent.layout.width)}>
      <View style={{ position: "absolute", left: 0, right: 0, top: 0, bottom: 0 }}>
        {/* The picture: fitted inside the page, or filling it (cropped), centred. */}
        <VideoView player={player} nativeControls={false} contentFit={fill ? "cover" : "contain"} surfaceType="textureView" style={{ flex: 1 }} />
        {audio ? (
          <View style={{ position: "absolute", left: 0, right: 0, top: 0, bottom: 0, alignItems: "center", justifyContent: "center" }}>
            <View style={{ padding: 32, alignItems: "center", gap: 12 }}>
              <IconIn icon={Icons.FileAudio} size={56} tint={Muted} />
              <T size={16} color={Ink} align="center" numberOfLines={3}>{name}</T>
            </View>
          </View>
        ) : null}
      </View>
      <GestureDetector gesture={Gesture.Exclusive(double, single)}>
        <View style={{ position: "absolute", left: 0, right: 0, top: 0, bottom: 0 }} collapsable={false} />
      </GestureDetector>
      {subtitlesOn && cues.length > 0 ? (
        <View pointerEvents="none" style={{ position: "absolute", left: 24, right: 24, bottom: insets.bottom + (shownNow > 0.5 ? 132 : 28), alignItems: "center" }}>
          <Smooth radius={6} style={{ backgroundColor: "rgba(0,0,0,0.35)", paddingHorizontal: 8, paddingVertical: 2 }}>
            <Text style={{ fontSize: sideways ? 20 : 16, lineHeight: sideways ? 26 : 22, color: "#FFFFFF", textAlign: "center", textShadowColor: "#000000", textShadowOffset: { width: 0, height: 1 }, textShadowRadius: 6, includeFontPadding: false }}>{cues}</Text>
          </Smooth>
        </View>
      ) : null}
      <View pointerEvents="box-none" style={{ position: "absolute", left: 0, right: 0, top: 0, bottom: 0, alignItems: "center", justifyContent: "center" }}>
        {phase === Phase.Opening || phase === Phase.Buffering ? (
          // A wait's pill floating over the picture, on the controls' glass so it reads over any frame.
          <Glass radius={999}>
            <WaitPill text={phase === Phase.Opening ? t("common.opening") : t("android-misc.drive.player.buffering")} ground="transparent" ink={Ink} />
          </Glass>
        ) : phase === Phase.Failed ? (
          <View style={{ padding: 32, alignItems: "center", gap: 12 }}>
            <T size={15} weight="600" color={Ink}>{t("android-misc.drive.player.failed")}</T>
            {failure !== null ? <T size={12} color={Muted} align="center" numberOfLines={4}>{failure}</T> : null}
            <Chip label={t("android-misc.drive.player.retry")} onClick={() => setAttempt((n) => n + 1)} />
          </View>
        ) : phase === Phase.Ended && next !== null ? (
          <View style={{ alignItems: "center", gap: 12 }}>
            <T size={14} color={Muted}>{t("android-misc.drive.player.ended")}</T>
            <Chip label={t("android-misc.drive.player.nextOne", { name: next })} onClick={() => open(next)} />
          </View>
        ) : null}
      </View>
      {note !== null ? (
        <View pointerEvents="none" style={{ position: "absolute", left: 0, right: 0, top: 0, bottom: 0, alignItems: "center", justifyContent: "center" }}>
          <Smooth radius={12} style={{ marginBottom: 120, backgroundColor: "rgba(0,0,0,0.55)", paddingHorizontal: 16, paddingVertical: 9 }}>
            <T size={14} color={Ink}>{note}</T>
          </Smooth>
        </View>
      ) : null}

      {/* The bar at the top: back, the name, which of the folder's it is (as the phone web's). */}
      <Animated.View style={[{ position: "absolute", top: insets.top, left: insets.left, right: insets.right, paddingHorizontal: 8, paddingVertical: 6 }, fade]} pointerEvents={controls ? "box-none" : "none"}>
        <Glass radius={16} style={{ height: 48 }}>
          <View style={{ flex: 1, flexDirection: "row", alignItems: "center", paddingLeft: 4, paddingRight: 14 }}>
            <Key icon={Icons.ChevronLeft} label={t("common.back")} enabled={controls} onClick={() => { if (sideways) setSideways(false); else app.pop(); }} />
            <T size={15} weight="600" color={Ink} numberOfLines={1} style={{ flexShrink: 1, paddingHorizontal: 4 }}>{name}</T>
            {list.length > 1 && index >= 0 ? <T size={12} color={Muted} numberOfLines={1} style={[TNUM, { paddingLeft: 4 }]}>{`${index + 1} / ${list.length}`}</T> : null}
          </View>
        </Glass>
      </Animated.View>
      {/* The controls at the foot: the time over where it is (and what is buffered beyond it); the one before, 15 s back,
          play, 15 s on, the one after; the speed, the subtitle, sideways. */}
      <Animated.View style={[{ position: "absolute", bottom: insets.bottom, left: insets.left, right: insets.right, paddingHorizontal: 8, paddingVertical: 8, alignItems: "center" }, fade]} pointerEvents={controls ? "box-none" : "none"}>
        <Glass radius={20} style={{ width: "100%", maxWidth: 720 }}>
          <View onTouchStart={wake} style={{ paddingLeft: 6, paddingRight: 6, paddingTop: 8, paddingBottom: 4 }}>
            <Text numberOfLines={1} style={[TNUM, { fontSize: 12, lineHeight: 12 * 1.4, color: Muted, paddingLeft: 10, includeFontPadding: false }]}>
              <Text style={{ color: Ink, fontWeight: "600" }}>{clock(position)}</Text>
              {` / ${duration > 0 ? clock(duration) : "--:--"}`}
            </Text>
            <Timeline position={position} duration={duration} buffered={buffered} enabled={controls} onSeek={(ms) => { player.currentTime = ms / 1000; if (state === State.Ended) setState(State.Ready); wake(); }} />
            <View style={{ flexDirection: "row", alignItems: "center" }}>
              {list.length > 1 ? <Key icon={Icons.SkipBack} label={t("android-misc.drive.player.prev")} enabled={controls && prev !== null} onClick={() => { if (prev !== null) open(prev); }} /> : null}
              <Key icon={Icons.Back15} label={t("android-misc.drive.player.back15")} enabled={controls} onClick={() => { seekBy(-NUDGE_MS); wake(); }} />
              <Key icon={phase === Phase.Playing || phase === Phase.Buffering ? Icons.Pause : Icons.Play} label={playing ? t("android-chat.video.pause") : t("android-chat.video.play")} enabled={controls} onClick={() => { playPause(); wake(); }} />
              <Key icon={Icons.Forward15} label={t("android-misc.drive.player.forward15")} enabled={controls} onClick={() => { seekBy(NUDGE_MS); wake(); }} />
              {list.length > 1 ? <Key icon={Icons.SkipForward} label={t("android-misc.drive.player.next")} enabled={controls && next !== null} onClick={() => { if (next !== null) open(next); }} /> : null}
              <View style={{ flex: 1 }} />
              <SpeedKey speed={speed} enabled={controls} next={() => { setSpeed(SPEEDS[(SPEEDS.indexOf(speed) + 1) % SPEEDS.length]!); wake(); }} />
              {subtitle !== null ? <Key icon={Icons.Captions} label={subtitlesOn ? t("android-misc.drive.player.subtitlesOff") : t("android-misc.drive.player.subtitlesOn")} pressed={subtitlesOn} enabled={controls} onClick={() => { setSubtitlesOn(!subtitlesOn); wake(); }} /> : null}
              {/* Turned sideways the picture can fill the screen (cropped) or fit in it. */}
              {!audio && sideways ? <Key icon={fill ? Icons.Shrink : Icons.Expand} label={fill ? t("android-misc.drive.player.fit") : t("android-misc.drive.player.fill")} pressed={fill} enabled={controls} onClick={() => { setFill(!fill); wake(); }} /> : null}
              {!audio ? <Key icon={Icons.Landscape} label={sideways ? t("android-misc.drive.player.unfull") : t("android-misc.drive.player.full")} pressed={sideways} enabled={controls} onClick={() => { setSideways(!sideways); wake(); }} /> : null}
            </View>
          </View>
        </Glass>
      </Animated.View>
    </View>
  );
}

/** Where it was left, kept on this device: its time and its length (ms). */
function keepPlace(station: string, root: string, path: string, at: number, of: number) {
  app.scope.launch(() => app.api(station).drivePlace(root, path, Math.round(at), Math.round(of)).catch((e: unknown) => console.warn(TAG, `place not kept: ${(e as { code?: string }).code} ${errorOf(e)}`)));
}

/** What a subtitle file is, by its name: SubRip, WebVTT or SubStation (media3's MimeTypes). */
function subtitleKind(name: string): "srt" | "vtt" | "ssa" | null {
  switch (name.substring(name.lastIndexOf(".") + 1).toLowerCase()) {
    case "srt": return "srt";
    case "vtt": return "vtt";
    case "ass": case "ssa": return "ssa";
    default: return null;
  }
}

/** `hh:mm:ss,mmm` (SubRip), `hh:mm:ss.mmm` or `mm:ss.mmm` (WebVTT), `h:mm:ss.cc` (SubStation) in ms. */
function timeOf(s: string): number {
  const parts = s.trim().replace(",", ".").split(":");
  let ms = 0;
  for (const p of parts) ms = ms * 60 + Number(p);
  return Math.round(ms * 1000);
}

/**
 * A side-loaded subtitle's lines (what media3's SubRip, WebVTT and SSA decoders make of one on Android): each cue's time
 * and its text, its markup (<i>, {\an8}…) left out.
 */
function parseSubtitle(name: string, text: string): Cue[] {
  const kind = subtitleKind(name);
  const clean = (s: string) => s.replace(/<[^>]+>/g, "").replace(/\{[^}]*\}/g, "").replace(/\\N/gi, "\n").trim();
  const out: Cue[] = [];
  if (kind === "ssa") {
    let format: string[] = [];
    for (const line of text.split("\n")) {
      if (/^Format:/i.test(line) && format.length === 0 && /Start/i.test(line)) format = line.substring(7).split(",").map((it) => it.trim().toLowerCase());
      if (!/^Dialogue:/i.test(line)) continue;
      const fields = line.substring(9).split(",");
      const at = (k: string) => format.indexOf(k);
      const n = format.length || 10;
      const start = fields[at("start") >= 0 ? at("start") : 1];
      const end = fields[at("end") >= 0 ? at("end") : 2];
      const said = fields.slice((at("text") >= 0 ? at("text") : n - 1)).join(",");
      if (start === undefined || end === undefined) continue;
      out.push({ from: timeOf(start), to: timeOf(end), text: clean(said) });
    }
  } else {
    for (const block of text.split(/\n{2,}/)) {
      const lines = block.split("\n");
      const timing = lines.findIndex((it) => it.includes("-->"));
      if (timing < 0) continue;
      const [a, b] = lines[timing]!.split("-->");
      out.push({ from: timeOf(a!), to: timeOf(b!.trim().split(/\s+/)[0]!), text: clean(lines.slice(timing + 1).join("\n")) });
    }
  }
  return out.filter((c) => c.text.length > 0).sort((x, y) => x.from - y.from);
}

/** Frosted glass over the picture (as the chat's viewer has). */
function Glass({ radius, style, children }: { radius: number; style?: object; children: ReactNode }) {
  return (
    <Smooth radius={radius} style={[{ backgroundColor: "#000000" }, style]}>
      <Frost tint="#121214" alpha={0.62} px={24} style={{ position: "absolute", left: 0, right: 0, top: 0, bottom: 0 }} />
      {children}
    </Smooth>
  );
}

/** A round key on the controls; `pressed`, a soft light behind it while what it turns on is on. */
function Key({ icon, label, pressed = false, enabled = true, onClick }: { icon: IconPaths; label: string; pressed?: boolean; enabled?: boolean; onClick: () => void }) {
  return (
    <Pressable
      disabled={!enabled} onPress={onClick} accessibilityLabel={label}
      android_ripple={{ color: "rgba(255,255,255,0.12)", borderless: true, radius: 20 }}
      style={{ width: 40, height: 40, borderRadius: 20, overflow: "hidden", backgroundColor: pressed ? "rgba(255,255,255,0.14)" : "transparent", alignItems: "center", justifyContent: "center" }}
    >
      <IconIn icon={icon} size={20} tint={Ink} />
    </Pressable>
  );
}

/** The speed, as a figure; a tap goes to the next (1×, 1.25×, 1.5×, 2×, 0.5×, 0.75×, as the phone web's). */
function SpeedKey({ speed, enabled, next }: { speed: number; enabled: boolean; next: () => void }) {
  return (
    <Smooth radius={10} style={{ backgroundColor: speed !== 1 ? "rgba(255,255,255,0.14)" : "rgba(255,255,255,0.06)" }}>
      <Pressable
        disabled={!enabled} onPress={next} accessibilityLabel={t("android-misc.drive.player.speed")} android_ripple={{ color: "rgba(255,255,255,0.12)" }}
        style={{ height: 30, minWidth: 44, paddingHorizontal: 8, alignItems: "center", justifyContent: "center" }}
      >
        <T size={12} weight="600" color={Ink}>{speedLabel(speed)}</T>
      </Pressable>
    </Smooth>
  );
}

function Chip({ label, onClick }: { label: string; onClick: () => void }) {
  return (
    <Smooth radius={12} style={{ maxWidth: 280, backgroundColor: "rgba(255,255,255,0.14)" }}>
      <Pressable onPress={onClick} android_ripple={{ color: "rgba(255,255,255,0.12)" }} style={{ paddingHorizontal: 16, paddingVertical: 9 }}>
        <T size={14} color={Ink} numberOfLines={1}>{label}</T>
      </Pressable>
    </Smooth>
  );
}

/**
 * Where it is, to tap or drag to a place: a thin track, what is buffered lighter on it, what has played, a round head.
 * The time follows the finger while it drags; the player is sent there once it is let go (not a read per pixel).
 */
function Timeline({ position, duration, buffered, enabled, onSeek }: { position: number; duration: number; buffered: number; enabled: boolean; onSeek: (ms: number) => void }) {
  const [scrub, setScrub] = useState<number | null>(null);
  const [width, setWidth] = useState(1);
  const shown = scrub ?? position;
  const at = (x: number) => Math.min(Math.max(x / width, 0), 1) * duration;
  const x = useRef(0);
  const drag = Gesture.Pan().minDistance(0).enabled(enabled).runOnJS(true)
    .onBegin((e) => { if (duration <= 0) return; x.current = e.x; setScrub(at(e.x)); })
    .onUpdate((e) => { if (duration <= 0) return; x.current = e.x; setScrub(at(e.x)); })
    .onEnd(() => { if (duration > 0) onSeek(at(x.current)); })
    .onFinalize(() => setScrub(null));
  const part = (ms: number) => (duration <= 0 ? 0 : Math.min(Math.max(ms / duration, 0), 1));
  const h = scrub !== null ? 4 : 3;
  const head = scrub !== null ? 8 : 6;
  return (
    <GestureDetector gesture={drag}>
      <View style={{ marginHorizontal: 10, height: 26 }} onLayout={(e) => setWidth(Math.max(e.nativeEvent.layout.width, 1))}>
        <View style={{ position: "absolute", left: 0, right: 0, top: 13 - h / 2, height: h, borderRadius: h / 2, backgroundColor: "rgba(255,255,255,0.2)" }} />
        <View style={{ position: "absolute", left: 0, width: width * part(buffered), top: 13 - h / 2, height: h, borderRadius: h / 2, backgroundColor: "rgba(255,255,255,0.35)" }} />
        <View style={{ position: "absolute", left: 0, width: width * part(shown), top: 13 - h / 2, height: h, borderRadius: h / 2, backgroundColor: Ink }} />
        <View style={{ position: "absolute", left: width * part(shown) - head, top: 13 - head, width: head * 2, height: head * 2, borderRadius: head, backgroundColor: Ink }} />
      </View>
    </GestureDetector>
  );
}
