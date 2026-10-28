// The film: still.fail at work, from a message on a phone to the change merged. Its file is the releases bucket's
// (served by cloud at /releases/site/film-<lang>-<n>.mp4, byte ranges and all, kept by browsers for good: too large
// for the site's own files; a new cut is a new number), read only once it is near; it plays, without sound, while it
// is in view (a picture where less motion is asked for), and the visitor turns its sound on or off.
import { useEffect, useRef, useState } from "react";
import { Volume, VolumeX } from "@stillfail/ui/icons.tsx";
import * as css from "./site.css.ts";
import { useSay } from "./words.ts";

/** The film and the picture shown before it plays (web/public). */
export const FILM = { src: "https://app.still.fail/releases/site/film-en-1.mp4", poster: "/film-poster.jpg", w: 2560, h: 1440 };

export function Film() {
  const say = useSay();
  const video = useRef<HTMLVideoElement>(null);
  const [muted, setMuted] = useState(true);
  useEffect(() => {
    const el = video.current;
    if (!el || matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const seen = new IntersectionObserver(([entry]) => {
      if (entry?.isIntersecting) void el.play().catch(() => {});
      else el.pause();
    }, { threshold: 0.4 });
    seen.observe(el);
    return () => seen.disconnect();
  }, []);
  const toggle = () => {
    const el = video.current;
    if (!el) return;
    el.muted = !el.muted;
    setMuted(el.muted);
    if (el.paused) void el.play().catch(() => {});
  };
  return (
    <div className={css.film}>
      <video ref={video} className={css.filmVideo} src={FILM.src} poster={FILM.poster} width={FILM.w} height={FILM.h} muted loop playsInline preload="none" onClick={toggle} />
      <button type="button" className={css.filmSound} onClick={toggle} aria-label={muted ? say.soundOn : say.soundOff}>
        {muted ? <VolumeX size={18} /> : <Volume size={18} />}
      </button>
    </div>
  );
}
