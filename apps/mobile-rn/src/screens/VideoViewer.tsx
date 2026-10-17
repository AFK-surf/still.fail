// A video to play and to step through frame by frame (web/src/VideoViewer.tsx), for a close look at an interface's
// motion: its frames' times read from the file, so a step is to the very next frame the file has, whatever its frame
// rate. Its controls float over the picture, frosted, and fade when left alone. Audio plays in a small player of the
// same kind.
import { requireOptionalNativeModule } from "expo";
import { File } from "expo-file-system";
import * as ScreenOrientation from "expo-screen-orientation";
import { useVideoPlayer, VideoView, type VideoPlayer } from "expo-video";
import { useEffect, useReducer, useRef, useState } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { Gesture, GestureDetector } from "react-native-gesture-handler";
import Animated, { useAnimatedStyle, type SharedValue } from "react-native-reanimated";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { app } from "../AppState";
import { t } from "../i18n";
import { Icon, Icons } from "../ui/Icon";
import { Smooth } from "../ui/Smooth";
import { T } from "../ui/Text";
import { CODE_FONT, useC, withAlpha } from "../ui/Theme";
import { WaitPill } from "../ui/Waiting";
import { Zoomable, ZoomState } from "../ui/Zoom";
import { PictureButton } from "./ImageMarks";
import { download, frameOf, type Picture } from "./ChatFiles";
import { DrawFitted, KeptFrame, NoStage, rectOf, type StageWrap, type StageWrapStyled } from "./FilePreview";

const RATES = [0.1, 0.25, 0.5, 1];
/** Without the file's own frames, a step is this long (µs). */
const GUESSED_STEP_US = Math.floor(1_000_000 / 60);

/** What reads a video file's frames (MediaExtractor's sample times). */
interface MediaNative { frameStarts(uri: string): Promise<number[] | null> }
// NATIVE: a module "StillfailMedia" with frameStarts(uri): when each frame of the file's video track starts (µs, in
// time order), read with MediaExtractor (selectTrack, sampleTime, advance) as VideoViewer.kt's frameStarts does; null
// when it has none to read. Without it, steps are of a guessed 60 fps.
const media = requireOptionalNativeModule<MediaNative>("StillfailMedia");

/** When each frame of the file's video starts (µs, in time order), or null when it has none to read. */
async function frameStarts(uri: string): Promise<number[] | null> {
  try {
    const times = await media?.frameStarts(uri);
    if (!times || times.length === 0) return null;
    return [...times].sort((a, b) => a - b);
  } catch {
    return null;
  }
}

/** The frame showing at `time` (the last to start by then). */
function frameAt(starts: number[], time: number): number {
  let lo = 0;
  let hi = starts.length - 1;
  while (lo < hi) {
    const mid = Math.floor((lo + hi + 1) / 2);
    if (starts[mid]! <= time + 100) lo = mid; else hi = mid - 1;
  }
  return lo;
}

/** Milliseconds as m:ss. */
const short = (ms: number) => `${Math.floor(ms / 60000)}:${String(Math.floor((ms / 1000) % 60)).padStart(2, "0")}`;

/** Follows the player's status as it changes. */
function usePlayerState(player: VideoPlayer) {
  const [, bump] = useReducer((n: number) => n + 1, 0);
  useEffect(() => {
    const subs = [player.addListener("statusChange", bump), player.addListener("playingChange", bump), player.addListener("sourceLoad", bump), player.addListener("videoTrackChange", bump)];
    return () => subs.forEach((s) => s.remove());
  }, [player]);
}

/**
 * The video in `file` (its uri on the phone's disk): pinch to zoom, controls over it (`awake`: shown; `wake`: a finger
 * on them keeps them a while longer; `onTap`: a tap on the picture shows or hides them).
 */
export function VideoViewer({
  file, name, awake, wake, onTap, glass: Glass,
  zoomOf = null, stage: Stage = NoStage, poster = null, chrome = null, startAtUs = 0, frameOut = null,
}: {
  file: string; name: string; awake: boolean; wake: () => void; onTap: () => void; glass: StageWrapStyled;
  /** Where the picture shows (the viewer's own, known from the still before the player is ready). */
  zoomOf?: ZoomState | null;
  /** On the picture (and the still over it): the viewer's flight from the chat's thumbnail (FilePreview.tsx). */
  stage?: StageWrap;
  /** The still the chat shows, over the picture until the player's first frame is drawn. */
  poster?: Picture | null;
  /** How much of the controls shows as the viewer comes and goes. */
  chrome?: SharedValue<number> | null;
  /** Where to start (µs): where it was left when closed before (the still over it is that frame). */
  startAtUs?: number;
  /** Hands over how to read the frame showing now and its time (for the viewer to close into the thumbnail with it). */
  frameOut?: ((read: () => Promise<KeptFrame | null>) => void) | null;
}) {
  const insets = useSafeAreaInsets();
  const own = useRef<ZoomState | null>(null);
  const zoom = zoomOf ?? (own.current ??= new ZoomState(1));
  const [, redraw] = useReducer((n: number) => n + 1, 0);
  useEffect(() => zoom.subscribe(redraw), [zoom]);
  const [framed, setFramed] = useState(false);
  const player = useVideoPlayer({ uri: file }, (p) => { p.timeUpdateEventInterval = 0; });
  usePlayerState(player);
  const [ready, setReady] = useState(false);
  const [playing, setPlaying] = useState(false);
  const [duration, setDuration] = useState(0);
  // Where it is, in µs: the frame shown when paused, the player's clock while it plays.
  const [time, setTime] = useState(0);
  const [frames, setFrames] = useState<number[] | null>(null);
  const [read, setRead] = useState(false);
  const [rate, setRate] = useState(1);
  const [turned, setTurned] = useState(false);
  // The player could not play it (a file it cannot read): said over the picture, the controls idle.
  const [failed, setFailed] = useState(false);
  const live = useRef({ frames, duration, time, framed });
  live.current = { frames, duration, time, framed };

  useEffect(() => {
    let prepared = false;
    const placeVideo = () => {
      const size = player.videoTrack?.size;
      if (size && size.width > 0 && size.height > 0) zoom.fitNatural({ width: size.width, height: size.height });
    };
    const status = player.addListener("statusChange", ({ status }) => {
      if (status === "error") { setReady(false); setPlaying(false); setFailed(true); return; }
      if (status !== "readyToPlay" || prepared) return;
      prepared = true;
      placeVideo();
      const d = Math.round(player.duration * 1_000_000);
      setDuration(d);
      // Opened again where it was left: from there; left at its end, it stays on that frame (play starts over).
      const resume = startAtUs >= 1 && startAtUs < d + 1;
      if (resume) { setTime(startAtUs); player.currentTime = Math.ceil(startAtUs / 1000) / 1000; }
      setReady(true);
      if (!resume || startAtUs < d - 50_000) { player.play(); setPlaying(true); }
    });
    const track = player.addListener("videoTrackChange", placeVideo);
    // Played to the end: it rests on its last frame (and says so), as it would be left.
    const end = player.addListener("playToEnd", () => {
      setPlaying(false);
      const f = live.current.frames;
      setTime(f ? f[f.length - 1]! : live.current.duration);
    });
    return () => { status.remove(); track.remove(); end.remove(); };
  }, [player]);
  useEffect(() => {
    let gone = false;
    frameStarts(file).then((f) => { if (!gone) { setFrames(f); setRead(true); } });
    return () => { gone = true; };
  }, [file]);
  // Playing, the time follows the player's clock.
  useEffect(() => {
    if (!playing) return;
    let on = true;
    const tick = () => {
      if (!on) return;
      // Not once it has stopped (at its end the player's clock reads back near the start; the end is kept).
      if (player.playing) setTime(Math.round(player.currentTime * 1_000_000));
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
    return () => { on = false; };
  }, [playing]);
  useEffect(() => {
    frameOut?.(async () => {
      const n = zoom.natural;
      const { framed: f, time: now } = live.current;
      // The frame at the video's own size: the whole frame, not as the zoom shows it.
      if (!f || n == null) return null;
      const p = await frameOf(file, now / 1000);
      return p ? new KeptFrame(p, now) : null;
    });
  }, [frameOut]);
  useEffect(() => () => { if (turnedRef.current) void ScreenOrientation.unlockAsync(); }, []);
  const turnedRef = useRef(turned);
  turnedRef.current = turned;

  const starts = frames;
  const at = starts ? frameAt(starts, time) : -1;
  const seekTo = (us: number) => { player.currentTime = Math.ceil(us / 1000) / 1000; };
  const play = () => {
    if (!ready) return;
    if (player.playing) { player.pause(); setPlaying(false); return; }
    if (starts) {
      // From the frame stepped to; from the start again at the end.
      const i = at >= starts.length - 1 ? 0 : at;
      seekTo(starts[i]!);
    }
    player.playbackRate = rate;
    player.play();
    setPlaying(true);
  };
  /** Paused, to the frame `to` makes of the one shown (without the file's frames, steps of a guessed 60 fps). */
  const go = (to: (i: number) => number) => {
    if (!ready) return;
    if (player.playing) { player.pause(); setPlaying(false); }
    const target = starts ? starts[Math.min(starts.length - 1, Math.max(0, to(frameAt(starts, time))))]!
      : Math.min(duration, Math.max(0, to(Math.floor(time / GUESSED_STEP_US)) * GUESSED_STEP_US));
    setTime(target);
    seekTo(target);
  };
  const seek = (us: number) => go(() => (starts ? frameAt(starts, us) : Math.floor(us / GUESSED_STEP_US)));

  const end = starts ? starts[starts.length - 1]! + (starts.length > 1 ? starts[starts.length - 1]! - starts[starts.length - 2]! : 0) : duration;
  const start = starts?.[0] ?? 0;
  const now = starts && at >= 0 ? starts[at]! : time;
  const shown = useAnimatedStyle(() => ({ opacity: chrome ? chrome.value : 1 }));
  const r = rectOf(zoom);
  const quiet = withAlpha("#FFFFFF", 0.6);
  return (
    // Its ground is the viewer's (black, coming in with it).
    <View style={StyleSheet.absoluteFill}>
      <Stage>
        <Zoomable state={zoom} onTap={onTap} style={StyleSheet.absoluteFill}>
          {r ? (
            <View pointerEvents="none" style={{ position: "absolute", left: r.left, top: r.top, width: r.width, height: r.height }}>
              <VideoView player={player} nativeControls={false} contentFit="fill" surfaceType="textureView" style={StyleSheet.absoluteFill} onFirstFrameRender={() => setFramed(true)} />
            </View>
          ) : null}
          {!framed && poster ? <DrawFitted p={poster} zoom={zoom} /> : null}
        </Zoomable>
      </Stage>
      {failed ? (
        <View pointerEvents="none" style={[StyleSheet.absoluteFill, { alignItems: "center", justifyContent: "center" }]}>
          <T size={14} color={quiet}>{t("android-chat.video.failed")}</T>
        </View>
      ) : null}
      {/* The controls: where it is, the steps and play, which frame, the speed, a frame saved, turned sideways. */}
      <Animated.View pointerEvents={awake ? "auto" : "none"} style={[{ position: "absolute", left: 0, right: 0, bottom: insets.bottom, paddingHorizontal: 8, paddingVertical: 8 }, shown]}>
        <View style={{ opacity: awake ? 1 : 0 }} onTouchStart={wake}>
          <Glass style={{ paddingLeft: 4, paddingRight: 4, paddingTop: 2, paddingBottom: 4 }}>
            <Timeline start={start} end={end} now={now} dark onSeek={(us) => { seek(us); wake(); }} />
            <View style={{ flexDirection: "row", alignItems: "center", gap: 12 }}>
              <View style={{ flexDirection: "row", gap: 2 }}>
                <PictureButton icon={Icons.ChevronLeft} label={t("android-chat.video.prev")} onClick={() => { go((i) => i - 1); wake(); }} />
                <PictureButton icon={playing ? Icons.Pause : Icons.Play} label={playing ? t("android-chat.video.pause") : t("android-chat.video.play")} onClick={() => { play(); wake(); }} />
                <PictureButton icon={Icons.ChevronRight} label={t("android-chat.video.next")} onClick={() => { go((i) => i + 1); wake(); }} />
              </View>
              <View style={{ flex: 1, minWidth: 0 }}>
                {starts ? (() => {
                  // Which frame in bold, where the sentence has it.
                  const sentence = t("android-chat.video.frames", { n: starts.length });
                  const cut = sentence.indexOf("{at}");
                  const before = cut >= 0 ? sentence.substring(0, cut) : sentence;
                  const after = cut >= 0 ? sentence.substring(cut + 4) : "";
                  return (
                    <Text numberOfLines={1} style={{ fontFamily: CODE_FONT, fontSize: 12, lineHeight: 12 * 1.4 }}>
                      <Text style={{ color: quiet }}>{before}</Text>
                      <Text style={{ color: "#F4F4F5", fontWeight: "600" }}>{`${at + 1}`}</Text>
                      <Text style={{ color: quiet }}>{after}</Text>
                    </Text>
                  );
                })() : !read ? (
                  // A wait's pill with no ground of its own (the bar's glass is its ground), its words in the bar's light
                  // grey, its start where the frames' count will start.
                  <View style={{ marginLeft: -12, alignSelf: "flex-start" }}>
                    <WaitPill text={t("android-chat.video.reading")} ground="transparent" ink={quiet} />
                  </View>
                ) : null}
              </View>
              <View style={{ flexDirection: "row", alignItems: "center", gap: 2 }}>
                <Smooth radius={10} style={{ height: 28, minWidth: 46, backgroundColor: withAlpha("#FFFFFF", 0.1) }}>
                  <Pressable
                    android_ripple={{ color: withAlpha("#FFFFFF", 0.2), borderless: false }}
                    style={{ height: 28, minWidth: 46, paddingHorizontal: 8, alignItems: "center", justifyContent: "center" }}
                    onPress={() => {
                      const next = RATES[(RATES.indexOf(rate) + RATES.length - 1) % RATES.length]!;
                      setRate(next);
                      if (ready && player.playing) player.playbackRate = next;
                      wake();
                    }}
                  >
                    <Text style={{ fontFamily: CODE_FONT, fontSize: 12, lineHeight: 12 * 1.4, fontWeight: "600", color: "#F4F4F5" }}>{`${rate === 1 ? "1" : String(rate)}×`}</Text>
                  </Pressable>
                </Smooth>
                <PictureButton icon={Icons.Camera} label={t("android-chat.video.saveFrame")} enabled={!playing && ready} onClick={() => {
                  void (async () => {
                    // The frame shown, drawn from the file (expo-video-thumbnails: a JPEG, where the Kotlin writes a PNG).
                    const frame = await frameOf(file, now / 1000);
                    const dot = name.lastIndexOf(".");
                    const saved = frame !== null && (await download(`${dot >= 0 ? name.substring(0, dot) : name}-${at + 1}.jpg`, new File(frame.uri), "image/jpeg"));
                    app.toast = saved ? t("android-chat.file.saved") : t("android-chat.video.saveFrame.failed");
                  })();
                }} />
                <PictureButton icon={Icons.Landscape} label={turned ? t("android-chat.video.landscape.exit") : t("android-chat.video.landscape")} pressed={turned} onClick={() => {
                  const next = !turned;
                  setTurned(next);
                  void (next ? ScreenOrientation.lockAsync(ScreenOrientation.OrientationLock.LANDSCAPE) : ScreenOrientation.unlockAsync());
                  wake();
                }} />
              </View>
            </View>
          </Glass>
        </View>
      </Animated.View>
    </View>
  );
}

/** Where in the media it is (µs), to tap or drag to a place: a thin track, what has played, a round head. */
function Timeline({ start, end, now, dark, onSeek }: { start: number; end: number; now: number; dark: boolean; onSeek: (us: number) => void }) {
  const C = useC();
  const span = Math.max(1, end - start);
  const [width, setWidth] = useState(1);
  const w = useRef(width);
  w.current = width;
  const seek = useRef(onSeek);
  seek.current = onSeek;
  const at = (x: number) => start + Math.round(Math.min(1, Math.max(0, x / w.current)) * span);
  const tap = Gesture.Tap().runOnJS(true).onEnd((e) => seek.current(at(e.x)));
  const drag = Gesture.Pan().runOnJS(true).onStart((e) => seek.current(at(e.x))).onUpdate((e) => seek.current(at(e.x)));
  const track = dark ? withAlpha("#FFFFFF", 0.2) : withAlpha(C.ink, 0.12);
  const played = dark ? "#F4F4F5" : C.accent;
  const part = Math.min(1, Math.max(0, (now - start) / span));
  return (
    <GestureDetector gesture={Gesture.Exclusive(drag, tap)}>
      <View style={{ height: 22, marginHorizontal: 6, justifyContent: "center" }} onLayout={(e) => setWidth(Math.max(1, Math.round(e.nativeEvent.layout.width)))}>
        <View style={{ height: 4, borderRadius: 2, backgroundColor: track }} />
        <View style={{ position: "absolute", left: 0, top: 9, height: 4, width: width * part, borderRadius: 2, backgroundColor: played }} />
        <View style={{ position: "absolute", left: width * part - 6, top: 5, width: 12, height: 12, borderRadius: 6, backgroundColor: played }} />
      </View>
    </GestureDetector>
  );
}

/** An audio file (its uri on the phone's disk): its name, and a player (play, where it is, how long) in the page's colours. */
export function AudioViewer({ file, name }: { file: string; name: string }) {
  const C = useC();
  const player = useVideoPlayer({ uri: file });
  const [ready, setReady] = useState(false);
  const [playing, setPlaying] = useState(false);
  const [duration, setDuration] = useState(0);
  const [time, setTime] = useState(0);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let prepared = false;
    const status = player.addListener("statusChange", ({ status }) => {
      if (status === "error") { setReady(false); setPlaying(false); setFailed(true); return; }
      if (status !== "readyToPlay" || prepared) return;
      prepared = true;
      setDuration(Math.round(player.duration * 1000));
      setReady(true);
      player.play();
      setPlaying(true);
    });
    const end = player.addListener("playToEnd", () => setPlaying(false));
    return () => { status.remove(); end.remove(); };
  }, [player]);
  useEffect(() => {
    if (!playing) return;
    let on = true;
    const tick = () => { if (!on) return; setTime(Math.round(player.currentTime * 1000)); requestAnimationFrame(tick); };
    requestAnimationFrame(tick);
    return () => { on = false; };
  }, [playing]);
  return (
    <View style={{ width: "100%", maxWidth: 480, paddingHorizontal: 24, alignItems: "center", gap: 14 }}>
      <T size={15} color={C.muted} numberOfLines={1}>{name}</T>
      <Smooth radius={27} style={{ width: "100%", minHeight: 54, backgroundColor: C.chip }}>
        <View style={{ minHeight: 54, paddingHorizontal: 8, flexDirection: "row", alignItems: "center", gap: 6 }}>
          <Pressable
            disabled={!ready}
            onPress={() => { if (player.playing) { player.pause(); setPlaying(false); } else { player.play(); setPlaying(true); } }}
            android_ripple={{ color: withAlpha(C.bg, 0.2), borderless: false }}
            style={{ width: 38, height: 38, borderRadius: 19, overflow: "hidden", backgroundColor: C.ink, alignItems: "center", justifyContent: "center" }}
          >
            <Icon icon={playing ? Icons.Pause : Icons.Play} size={16} color={C.bg} />
          </Pressable>
          <View style={{ flex: 1 }}>
            <Timeline start={0} end={duration * 1000} now={time * 1000} dark={false} onSeek={(us) => { if (ready) { player.currentTime = Math.floor(us / 1000) / 1000; setTime(Math.floor(us / 1000)); } }} />
          </View>
          <Text style={{ fontSize: 12, lineHeight: 12 * 1.4, color: C.muted, fontFamily: CODE_FONT, paddingRight: 10 }}>{failed ? t("android-chat.video.playFailed") : `${short(time)} / ${short(duration)}`}</Text>
        </View>
      </Smooth>
    </View>
  );
}

