// A video or a song of the drive, played as it comes (file.ts `stream`: the app's page has its service worker answer
// the player's ranges from `drive.read`), never fetched whole first: it starts at once and seeks anywhere. Its controls are still.fail's
// media controls (the chat's VideoViewer): floating frosted glass that fades when the pointer rests (a tap brings them
// back on a phone), a timeline drawn here, not the browser's. And zdrive's: speed, a subtitle beside it (E01.srt for
// E01.mp4, E01.zh.srt; SubRip and ASS turned into WebVTT for the <track>), the folder's others as a playlist (the next
// one plays at the end), 15 s back and on, full screen; where it was left kept on this device (`drive.place`).
// With a mouse it sits in the page as a desktop's player: a toolbar over the picture (the way back, the name, 选集
// when the folder has more), the picture under it with its controls over it, the volume beside them, a time under the
// pointer along the timeline, and the folder's others in a panel docked at the right.
// Where no service worker runs the page, a file of up to 200 MB is read whole first instead (its progress shown);
// a bigger one says it cannot be played here and offers the download.
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { Back15, Captions, Check, ChevronLeft, Close, Download, Expand, FileAudio, Forward15, List, Pause, Play, Shrink, SkipBack, SkipForward, Volume, VolumeX } from "../icons.tsx";
import { Tip } from "../parts.tsx";
import { Progress, WaitLine, WaitPill } from "../waiting.tsx";
import { fileSize as sizeOf } from "../fileSize.ts";
import { t } from "../i18n.ts";
import * as pageCss from "../styles/page.css.ts";
import { viewerHost } from "./host.ts";
import type { Got, ViewerEntry, ViewerFile } from "./file.ts";
import { compareNatural, sideSubtitle } from "./names.ts";
import { REST_MS, TAP_REST_MS } from "./rest.ts";
import * as vvCss from "./media.css.ts";
import { ViewerBar, ViewerDownload, ViewerTool } from "./ViewerBar.tsx";
import { decodeText } from "./text.ts";
import { toVtt } from "./subtitles.ts";
import * as css from "./Player.css.ts";

/** Without a stream, the most read whole to be played. */
const WHOLE_MAX = 200 * 1024 * 1024;
const RATES = [1, 1.25, 1.5, 2, 0.5, 0.75] as const;
const STEP = 15;

type Source = { state: "opening"; got: Got | null } | { state: "ready"; url: string; streamed: boolean } | { state: "error"; message: string; save?: boolean };

/** Seconds as h:mm:ss or m:ss. */
function clock(seconds: number): string {
  const s = Math.max(0, Math.floor(Number.isFinite(seconds) ? seconds : 0));
  const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, r = s % 60;
  return h ? `${h}:${String(m).padStart(2, "0")}:${String(r).padStart(2, "0")}` : `${m}:${String(r).padStart(2, "0")}`;
}

/** How far ahead of what plays the file is read: this much playing time, and this much more. */
const AHEAD_S = 30;
const AHEAD_BYTES = 4 * 1024 * 1024;

function useSource(file: ViewerFile, media: React.RefObject<HTMLVideoElement | null>): Source {
  const { blob, stream } = file;
  const [source, setSource] = useState<Source>({ state: "opening", got: null });
  useEffect(() => {
    let live = true;
    let close: (() => void) | null = null;
    let url: string | null = null;
    // Here already (a chat's file a preview has fetched): played from here.
    if (blob) {
      url = URL.createObjectURL(blob);
      setSource({ state: "ready", url, streamed: false });
      return () => { if (url) URL.revokeObjectURL(url); };
    }
    setSource({ state: "opening", got: null });
    const type = file.type || (file.kind === "audio" ? "audio/mpeg" : "video/mp4");
    void (async () => {
      // Read about what is played soon, not as far as the browser would buffer (by the file's bytes a second).
      const s = stream ? await stream(type, () => {
        const v = media.current;
        if (!v || !Number.isFinite(v.duration) || v.duration <= 0) return null;
        return ((v.currentTime + AHEAD_S) / v.duration) * file.size + AHEAD_BYTES;
      }).catch(() => null) : null;
      if (s && !live) { s.close(); return; }
      if (!live) return;
      if (s) {
        close = s.close;
        setSource({ state: "ready", url: s.url, streamed: true });
        return;
      }
      if (file.size > WHOLE_MAX) {
        setSource({ state: "error", message: t("web-pages.drive.player.noStream", { size: sizeOf(WHOLE_MAX) }), save: true });
        return;
      }
      file.read({ type, onProgress: (got) => { if (live) setSource({ state: "opening", got }); } }).then((blob) => {
        if (!live) return;
        url = URL.createObjectURL(blob);
        setSource({ state: "ready", url, streamed: false });
      }, (e: unknown) => { if (live) setSource({ state: "error", message: e instanceof Error ? e.message : String(e) }); });
    })();
    return () => { live = false; close?.(); if (url) URL.revokeObjectURL(url); };
  }, [file.blob ?? file.key ?? file, file.size, file.mtime]); // eslint-disable-line react-hooks/exhaustive-deps
  return source;
}

/** The subtitle beside it, as a WebVTT file's URL (none: null). */
function useSubtitle(file: ViewerFile, siblings: readonly ViewerEntry[]): { url: string; name: string } | null {
  const name = useMemo(() => sideSubtitle(file.name, siblings.filter((e) => !e.dir).map((e) => e.name)), [file.name, siblings]);
  const side = name ? siblings.find((e) => e.name === name) : undefined;
  const [shown, setShown] = useState<{ url: string; name: string } | null>(null);
  useEffect(() => {
    setShown(null);
    const beside = file.beside;
    if (!beside || !side || side.size > 8 * 1024 * 1024) return;
    let live = true;
    let url: string | null = null;
    beside(side, "text/plain").then(async (blob) => {
      const text = decodeText(new Uint8Array(await blob.arrayBuffer())).text;
      if (!live) return;
      url = URL.createObjectURL(new Blob([toVtt(side.name, text)], { type: "text/vtt" }));
      setShown({ url, name: side.name });
    }, () => undefined);
    return () => { live = false; if (url) URL.revokeObjectURL(url); };
  }, [file.blob ?? file.key ?? file, side?.name, side?.size, side?.mtime]); // eslint-disable-line react-hooks/exhaustive-deps
  return shown;
}

/**
 * A video or a sound played (file.ts): one of a station's drive (streamed, the folder's others its playlist and its
 * subtitles, where it was left kept), or a chat's file a preview has here already.
 */
export function Player({ file, siblings = [], backLabel, onBack, onGo = () => {} }: {
  file: ViewerFile; siblings?: readonly ViewerEntry[]; backLabel: string; onBack: () => void; onGo?: (name: string) => void;
}) {
  const entry = file;
  const narrow = viewerHost().useNarrow();
  const audio = entry.kind === "audio";
  const media = useRef<HTMLVideoElement>(null);
  const source = useSource(file, media);
  const subtitle = useSubtitle(file, siblings);
  const place = file.usePlace();
  const root = useRef<HTMLDivElement>(null);
  const [playing, setPlaying] = useState(false);
  const [time, setTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [buffered, setBuffered] = useState<[number, number][]>([]);
  const [waiting, setWaiting] = useState(false);
  const [rate, setRate] = useState<(typeof RATES)[number]>(1);
  const [captions, setCaptions] = useState(true);
  const [full, setFull] = useState(false);
  const [failed, setFailed] = useState<string | null>(null);
  const [volume, setVolume] = useState(heard.volume);
  const [muted, setMuted] = useState(heard.muted);
  const [listing, setListing] = useState(false);
  const desk = !narrow;

  // The folder's others of its kind, in their names' order: the playlist.
  const list = useMemo(() => siblings.filter((e) => !e.dir && e.kind === entry.kind).sort((a, b) => compareNatural(a.name, b.name)), [siblings, entry.kind]);
  const index = list.findIndex((e) => e.name === entry.name);
  const prev = index > 0 ? list[index - 1] : undefined;
  const next = index >= 0 ? list[index + 1] : undefined;

  // ── the controls float, and fade ──
  const [awake, setAwake] = useState(true);
  const resting = useRef(0);
  const onControls = useRef(false);
  const wake = useCallback((ms = REST_MS) => {
    setAwake(true);
    clearTimeout(resting.current);
    resting.current = window.setTimeout(() => { if (!onControls.current && !media.current?.paused) setAwake(false); }, ms);
  }, []);
  useEffect(() => { wake(); return () => clearTimeout(resting.current); }, [wake]);
  const keep = {
    onPointerEnter: (e: React.PointerEvent) => { if (e.pointerType !== "mouse") return; onControls.current = true; clearTimeout(resting.current); setAwake(true); },
    onPointerLeave: (e: React.PointerEvent) => { if (e.pointerType !== "mouse") return; onControls.current = false; wake(); },
    onPointerDown: (e: React.PointerEvent) => { if (e.pointerType !== "mouse") wake(TAP_REST_MS); },
  };

  // ── where it was left ──
  const resumed = useRef(false);
  const lastKept = useRef(0);
  const keepPlace = useCallback(() => {
    const v = media.current;
    if (!v || !resumed.current || !Number.isFinite(v.duration) || v.duration <= 0) return;
    file.keepPlace(v.currentTime * 1000, v.duration * 1000);
  }, [file]);
  useEffect(() => () => keepPlace(), [keepPlace]);
  useEffect(() => {
    const away = () => keepPlace();
    addEventListener("pagehide", away);
    return () => removeEventListener("pagehide", away);
  }, [keepPlace]);
  const resume = useCallback(() => {
    const v = media.current;
    if (!v || resumed.current || place === undefined || !Number.isFinite(v.duration)) return;
    resumed.current = true;
    const s = (place?.at ?? 0) / 1000;
    // Near its end it starts again; near its start it starts there anyway.
    if (s > 5 && s < v.duration - 5) v.currentTime = s;
    void v.play().catch(() => undefined);
  }, [place]);
  useEffect(() => { if (duration > 0) resume(); }, [duration, resume]);

  // ── doing ──
  const toggle = useCallback(() => {
    const v = media.current;
    if (!v) return;
    if (v.paused) void v.play().catch(() => undefined); else v.pause();
    wake();
  }, [wake]);
  const seek = useCallback((to: number) => {
    const v = media.current;
    if (!v || !Number.isFinite(v.duration)) return;
    v.currentTime = Math.max(0, Math.min(v.duration - 0.1, to));
    setTime(v.currentTime);
    wake();
  }, [wake]);
  const by = useCallback((s: number) => { const v = media.current; if (v) seek(v.currentTime + s); }, [seek]);
  const turn = useCallback(async () => {
    const el = root.current, v = media.current as (HTMLVideoElement & { webkitEnterFullscreen?: () => void }) | null;
    if (document.fullscreenElement) { await document.exitFullscreen().catch(() => undefined); return; }
    if (el?.requestFullscreen && document.fullscreenEnabled) { await el.requestFullscreen({ navigationUI: "hide" }).catch(() => undefined); return; }
    // iPhone Safari: only the video itself, in the system's player.
    v?.webkitEnterFullscreen?.();
  }, []);
  useEffect(() => {
    const on = () => setFull(!!root.current && document.fullscreenElement === root.current);
    document.addEventListener("fullscreenchange", on);
    return () => document.removeEventListener("fullscreenchange", on);
  }, []);
  useEffect(() => { if (media.current) media.current.playbackRate = rate; }, [rate, source]);
  // How loud, kept for the next one played while the page is open.
  useEffect(() => {
    heard.volume = volume; heard.muted = muted;
    if (media.current) { media.current.volume = volume; media.current.muted = muted; }
  }, [volume, muted, source]);
  const louder = useCallback((by: number) => { setMuted(false); setVolume((v) => Math.min(1, Math.max(0, Math.round((v + by) * 20) / 20))); }, []);
  // The subtitle's lines drawn here, not by the browser: above the controls while they show, lower when they fade.
  const [cue, setCue] = useState<string | null>(null);
  useEffect(() => {
    const track = media.current?.textTracks[0];
    if (!track) { setCue(null); return; }
    track.mode = "hidden";
    const change = () => setCue([...(track.activeCues ?? [])].map((c) => (c as VTTCue).text).join("\n") || null);
    track.addEventListener("cuechange", change);
    change();
    return () => track.removeEventListener("cuechange", change);
  }, [subtitle, source]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey || (e.target as Element | null)?.closest?.("input, textarea")) return;
      if (e.key === " " || e.key === "k") toggle();
      else if (e.key === "ArrowLeft" || e.key === "j") by(-STEP);
      else if (e.key === "ArrowRight" || e.key === "l") by(STEP);
      else if (e.key === "f") void turn();
      else if (e.key === "m") setMuted((m) => !m);
      else if (e.key === "ArrowUp" && desk) louder(0.05);
      else if (e.key === "ArrowDown" && desk) louder(-0.05);
      else if (e.key === "c" && subtitle) setCaptions((c) => !c);
      else if (e.key === "N" && next) onGo(next.name);
      else if (e.key === "P" && prev) onGo(prev.name);
      else return;
      e.preventDefault();
      wake();
    };
    addEventListener("keydown", onKey);
    return () => removeEventListener("keydown", onKey);
  }, [toggle, by, turn, wake, subtitle, next, prev, onGo, desk, louder]);

  const readBuffered = () => {
    const v = media.current;
    if (!v) return;
    const out: [number, number][] = [];
    for (let i = 0; i < v.buffered.length; i++) out.push([v.buffered.start(i), v.buffered.end(i)]);
    setBuffered(out);
  };

  const tapAt = useRef<{ x: number; y: number } | null>(null);
  let body: ReactNode;
  if (source.state === "error" || failed) {
    body = (
      <div className={css.note}>
        <span>{failed ?? (source.state === "error" ? source.message : "")}</span>
        {source.state === "error" && source.save && <button type="button" className={css.noteButton} onClick={file.save}><Download size={16} />{t("web-pages.drive.download")}</button>}
      </div>
    );
  } else if (source.state === "opening") {
    body = (
      <div className={css.note}>
        {source.got
          ? <><span>{t("web-pages.drive.reader.reading", { got: sizeOf(source.got.loaded), of: sizeOf(source.got.total) })}</span>
            <Progress part={source.got.total > 0 ? source.got.loaded / source.got.total : null} label={t("common.reading")} className={css.noteBar} /></>
          : <WaitLine text={t("common.opening")} />}
      </div>
    );
  } else {
    body = (
      <video ref={media} className={css.media} data-audio={audio || undefined} src={source.url} playsInline preload="metadata"
        onLoadedMetadata={(e) => { setDuration(e.currentTarget.duration); setFailed(null); }}
        onDurationChange={(e) => setDuration(e.currentTarget.duration)}
        onTimeUpdate={(e) => {
          const v = e.currentTarget;
          setTime(v.currentTime);
          if (Math.abs(v.currentTime * 1000 - lastKept.current) > 5000) { lastKept.current = v.currentTime * 1000; keepPlace(); }
        }}
        onProgress={readBuffered} onSeeked={readBuffered}
        onPlay={() => { setPlaying(true); wake(); }} onPause={() => { setPlaying(false); setAwake(true); keepPlace(); }}
        onWaiting={() => setWaiting(true)} onPlaying={() => setWaiting(false)} onCanPlay={() => setWaiting(false)}
        onEnded={() => { keepPlace(); if (next) onGo(next.name); }}
        onError={(e) => setFailed(t("web-pages.drive.player.failed", { error: e.currentTarget.error?.message || String(e.currentTarget.error?.code ?? "") }))}>
        {subtitle && <track kind="subtitles" src={subtitle.url} label={subtitle.name} default />}
      </video>
    );
  }

  return (
    <div ref={root} className={`${vvCss.vv} ${css.player}`} data-narrow={narrow || undefined} data-list={(desk && listing && list.length > 1) || undefined}
      onPointerMove={(e) => { if (e.pointerType === "mouse") wake(); }}
      onPointerLeave={(e) => { if (e.pointerType !== "mouse") return; clearTimeout(resting.current); if (!onControls.current && playing) setAwake(false); }}
      onPointerDown={(e) => { tapAt.current = { x: e.clientX, y: e.clientY }; }}
      onPointerUp={(e) => {
        const tap = tapAt.current;
        tapAt.current = null;
        if (!tap || Math.hypot(e.clientX - tap.x, e.clientY - tap.y) > 10 || (e.target as Element).closest("button, a, [role=slider]")) return;
        // A finger shows or hides the controls; a click plays or pauses.
        if (e.pointerType === "mouse") toggle();
        else if (awake) { clearTimeout(resting.current); setAwake(false); } else wake(TAP_REST_MS);
      }}
      onDoubleClick={(e) => { if (!(e.target as Element).closest("button, [role=slider]")) void turn(); }}>
      <div className={css.stage}>
        {audio && source.state === "ready" && <div className={css.cover}><FileAudio size={72} strokeWidth={1.2} /><span>{entry.name}</span></div>}
        {body}
        {waiting && source.state === "ready" && !failed && <WaitPill over text={t("web-pages.drive.player.buffering")} />}
      </div>
      {captions && cue && <div className={css.cue} data-awake={awake || undefined}><span>{cue.replace(/<[^>]+>/g, "")}</span></div>}
      {desk && !full ? (
        <ViewerBar back={{ label: backLabel, onClick: onBack }} name={entry.name} title={file.title} hidden={!awake && !listing}
          meta={[list.length > 1 && index >= 0 ? `${index + 1} / ${list.length}` : null, sizeOf(entry.size)].filter(Boolean).join(" · ")}
          tools={<>
            {list.length > 1 && <ViewerTool label={t("web-pages.drive.player.list")} on={listing} onClick={() => setListing((l) => !l)}><List size={18} /></ViewerTool>}
            <ViewerDownload name={entry.name} onSave={file.save} />
          </>} />
      ) : (
        <header className={css.head} data-awake={awake || undefined} {...keep}>
          <Tip label={backLabel}><button type="button" className={`${pageCss.iconBtn} ${css.bright}`} aria-label={backLabel} onClick={onBack}><ChevronLeft size={20} /></button></Tip>
          <span className={css.name}><b>{entry.name}</b>{list.length > 1 && index >= 0 && <small>{index + 1} / {list.length}</small>}</span>
        </header>
      )}
      {desk && listing && list.length > 1 && (
        <aside className={css.list}>
          <div className={css.listHead}>
            <b>{t("web-pages.drive.player.list")}</b><small>{index + 1} / {list.length}</small>
            <Tip label={t("common.close")}><button type="button" className={pageCss.iconBtn} aria-label={t("common.close")} onClick={() => setListing(false)}><Close size={16} /></button></Tip>
          </div>
          <div className={css.listRows}>
            {list.map((e, i) => (
              <button key={e.name} type="button" className={css.listRow} data-current={i === index || undefined} onClick={() => { if (i !== index) onGo(e.name); }}>
                <small>{i + 1}</small><span>{e.name}</span>{i === index && (playing ? <Play size={14} /> : <Check size={14} />)}
              </button>
            ))}
          </div>
        </aside>
      )}
      <div className={vvCss.vvBar} data-floats data-awake={awake || source.state !== "ready" || undefined} {...keep}>
        {/* On a phone the time goes over the timeline: the buttons take the row. */}
        <span className={css.timeTop}><b>{clock(time)}</b> / {clock(duration)}</span>
        <Timeline duration={duration} now={time} buffered={buffered} onSeek={seek} />
        <div className={vvCss.vvRow}>
          <span className={vvCss.vvGroup}>
            {list.length > 1 && <Tip label={t("web-pages.drive.player.prev")}><button type="button" className={pageCss.iconBtn} aria-label={t("web-pages.drive.player.prev")} disabled={!prev} onClick={() => prev && onGo(prev.name)}><SkipBack size={18} /></button></Tip>}
            <Tip label={t("web-pages.drive.player.back15")}><button type="button" className={pageCss.iconBtn} aria-label={t("web-pages.drive.player.back15")} onClick={() => by(-STEP)}><Back15 size={20} /></button></Tip>
            <Tip label={playing ? t("web-main.video.pauseKey") : t("web-main.video.playKey")}><button type="button" className={`${pageCss.iconBtn} ${css.bright}`} aria-label={playing ? t("web-main.video.pause") : t("web-main.video.play")} onClick={toggle}>
              {playing ? <Pause size={20} /> : <Play size={20} />}
            </button></Tip>
            <Tip label={t("web-pages.drive.player.forward15")}><button type="button" className={pageCss.iconBtn} aria-label={t("web-pages.drive.player.forward15")} onClick={() => by(STEP)}><Forward15 size={20} /></button></Tip>
            {list.length > 1 && <Tip label={t("web-pages.drive.player.next")}><button type="button" className={pageCss.iconBtn} aria-label={t("web-pages.drive.player.next")} disabled={!next} onClick={() => next && onGo(next.name)}><SkipForward size={18} /></button></Tip>}
          </span>
          <span className={`${vvCss.vvInfo} ${css.timeRow}`}><span className={vvCss.vvFact}><b className={vvCss.vvNow}>{clock(time)}</b><span className={vvCss.vvDim}> / {clock(duration)}</span></span></span>
          <span className={vvCss.vvGroup}>
            {desk && <VolumeControl volume={volume} muted={muted} onVolume={(v) => { setVolume(v); setMuted(v === 0); }} onMute={() => setMuted((m) => !m)} />}
            <Tip label={t("web-pages.drive.player.rate")}><button type="button" className={vvCss.vvRate} onClick={() => setRate((r) => RATES[(RATES.indexOf(r) + 1) % RATES.length]!)}>{rate}×</button></Tip>
            {subtitle && <Tip label={captions ? t("web-pages.drive.player.captionsOff") : t("web-pages.drive.player.captionsOn")}><button type="button" className={pageCss.iconBtn} aria-label={t("web-pages.drive.player.captions")} aria-pressed={captions} onClick={() => setCaptions((c) => !c)}><Captions size={18} /></button></Tip>}
            {!audio && <Tip label={full ? t("web-pages.drive.player.unfull") : t("web-pages.drive.player.full")}><button type="button" className={pageCss.iconBtn} aria-label={full ? t("web-pages.drive.player.unfull") : t("web-pages.drive.player.full")} onClick={() => void turn()}>{full ? <Shrink size={18} /> : <Expand size={18} />}</button></Tip>}
          </span>
        </div>
      </div>
    </div>
  );
}

/** How loud, for the next played as for this one while the page is open. */
const heard = { volume: 1, muted: false };

/** The sound: a button that mutes, and beside it a line to drag (wider while pointed at). */
function VolumeControl({ volume, muted, onVolume, onMute }: { volume: number; muted: boolean; onVolume: (v: number) => void; onMute: () => void }) {
  const box = useRef<HTMLSpanElement>(null);
  const [drag, setDrag] = useState<number | null>(null);
  const at = (x: number) => {
    const r = box.current!.getBoundingClientRect();
    return Math.round(Math.min(1, Math.max(0, (x - r.left) / r.width)) * 20) / 20;
  };
  const shown = drag ?? (muted ? 0 : volume);
  const silent = muted || volume === 0;
  return (
    <span className={css.volume}>
      <Tip label={silent ? t("web-pages.drive.player.unmute") : t("web-pages.drive.player.mute")}>
        <button type="button" className={pageCss.iconBtn} aria-label={silent ? t("web-pages.drive.player.unmute") : t("web-pages.drive.player.mute")} onClick={onMute}>
          {silent ? <VolumeX size={18} /> : <Volume size={18} />}
        </button>
      </Tip>
      <span ref={box} className={css.volumeLine} role="slider" aria-label={t("web-pages.drive.player.volume")} aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(shown * 100)} tabIndex={0}
        onPointerDown={(e) => { if (e.button !== 0) return; e.currentTarget.setPointerCapture(e.pointerId); const v = at(e.clientX); setDrag(v); onVolume(v); }}
        onPointerMove={(e) => { if (drag === null) return; const v = at(e.clientX); setDrag(v); onVolume(v); }}
        onPointerUp={() => setDrag(null)} onPointerCancel={() => setDrag(null)}>
        <span className={css.volumeTrack}><span style={{ transform: `scaleX(${shown})` }} /></span>
        <span className={vvCss.vvHeadRail} style={{ transform: `translateX(${shown * 100}%)` }}><span className={css.volumeHead} /></span>
      </span>
    </span>
  );
}

/** Where in it it is, to click or drag to a place; what has come so far a lighter band (VideoViewer's timeline). */
function Timeline({ duration, now, buffered, onSeek }: { duration: number; now: number; buffered: [number, number][]; onSeek: (time: number) => void }) {
  const box = useRef<HTMLDivElement>(null);
  const span = duration > 0 && Number.isFinite(duration) ? duration : 0;
  const [drag, setDrag] = useState<number | null>(null);
  // With a mouse over it, the time where it points.
  const [over, setOver] = useState<number | null>(null);
  const at = (x: number) => {
    const r = box.current!.getBoundingClientRect();
    return Math.min(1, Math.max(0, (x - r.left) / r.width)) * span;
  };
  const shown = drag ?? now;
  const pointed = drag ?? over;
  const share = span ? Math.min(1, Math.max(0, shown / span)) : 0;
  return (
    <div ref={box} className={vvCss.vvTimeline} role="slider" aria-label={t("web-main.video.position")} aria-valuemin={0} aria-valuemax={Math.round(span)} aria-valuenow={Math.round(shown)}
      onPointerDown={(e) => { if (e.button !== 0 || !span) return; e.currentTarget.setPointerCapture(e.pointerId); setDrag(at(e.clientX)); }}
      onPointerMove={(e) => { if (drag !== null) setDrag(at(e.clientX)); if (e.pointerType === "mouse" && span) setOver(at(e.clientX)); }}
      onPointerLeave={() => setOver(null)}
      onPointerUp={(e) => { if (drag === null) return; const to = at(e.clientX); setDrag(null); onSeek(to); }}
      onPointerCancel={() => setDrag(null)}>
      {pointed !== null && span > 0 && <span className={css.pointed} style={{ left: `${(pointed / span) * 100}%` }}>{clock(pointed)}</span>}
      <span className={vvCss.vvTrack}>
        {span > 0 && buffered.map(([a, b], i) => <span key={i} className={css.buffered} style={{ left: `${(a / span) * 100}%`, width: `${((b - a) / span) * 100}%` }} />)}
        <span className={vvCss.vvPlayed} style={{ transform: `scaleX(${share})` }} />
      </span>
      <span className={vvCss.vvHeadRail} style={{ transform: `translateX(${share * 100}%)` }}><span className={vvCss.vvHead} /></span>
    </div>
  );
}
