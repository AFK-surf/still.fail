# Render a scene

From `apps/mbui` on macOS, give the same action script to either output:

```sh
mkdir -p out
printf 'until 整理发布清单\nexit\n' > out/home.drive
MBUI_FIXTURE=home MBUI_WIN=320x560 MBUI_FILM_SCALE=1 \
  bash scripts/media.sh picture out/home.png out/home.drive
MBUI_FIXTURE=home MBUI_WIN=320x560 MBUI_FILM_SCALE=1 \
  bash scripts/media.sh film out/home.mp4 out/home.drive
```

The optional fourth argument is a drive file run first to prepare the scene, before the recorded actions. Use
`image_ready SRC` to require a named image, including one decoded during preparation. A failed preparation or action
leaves any existing output in place. The film also produces `out/home.mp4.last.png`, the lossless final frame, and
`out/home.mp4.textrec`. A film runs the app and the encoder at the same rate (`MBUI_FILM_FPS`, 60 by default).

For a picture, `MBUI_PICTURE_FRAME=K` captures frame K of the action, starting with 0 before its first step, at the
film's frame rate. `MBUI_PICTURE_AT=MS` instead captures exactly that many milliseconds after the action; the two
settings cannot be combined. `MBUI_PICTURE_TRANSPARENT=1` gives a transparent ground. Other scene settings are shared
by both commands: `MBUI_WIN`, `MBUI_FILM_SCALE`, `MBUI_FILM_PLATFORM`, `MBUI_NATIVE_INPUT`, `MBUI_POINTING`,
`MBUI_KEYBOARD`, `MBUI_DARK`, `MBUI_LOCALE`, `MBUI_FONT_SCALE`, and the application's fixture settings. The full set
of film arguments is listed at the top of `mbui/src/film/film.mbt`.

Beside each result is `OUTPUT.scene.json`, containing the actual copied scripts, scene settings, output and executable
SHA-256 hashes, the source revision and dirty state when Git is available, and the host's OS and architecture. It can
contain the scripts' words, so treat it as the scene's data when sharing it. A local station description is recorded
only by hash. Custom apps can set `MBUI_MEDIA_APP` to their own program that calls `@film.run`, and may explicitly
add extra input details as JSON in `MBUI_MEDIA_RECORD`; arbitrary environment variables and credentials are not collected.
External assets and a dirty or unavailable source revision still need to be kept separately for reproduction. If
publication is interrupted, compare the result's SHA-256 to the record before treating them as a pair.

Rendering uses the Mac offscreen host. System keyboards, dialogs and native web or video views are not drawn by mbui;
use a real system capture for a scene that needs them. Films fail when a frame needs an image that cannot be decoded or
a native view is visible, instead of silently omitting it. A failed image no longer in the frame does not stop export.
When deliberately filming only the parts mbui draws, set
`MBUI_FILM_ALLOW_INCOMPLETE=1`; this choice is recorded in the scene metadata. Images that are still loading can be
filmed as loading; use the preparation script and `image_ready SRC` if they must be ready before filming begins.
`docs/figures.md` describes building reusable graphics.

## Assemble a timeline

Put the scene films, stills, transparent mbui title or caption pictures, and sound on a frame-addressed timeline. A
scene is held for its `frames`; a picture scene is held still, and a film starts at `start_frame` after conversion to
the timeline's rate (zero by default).
Overlays are visible from `at` through the frame before `until`. Audio begins at `at`, and its optional `gain` defaults
to 1. All frame numbers are at the timeline's `fps`. Paths in the JSON are relative to the JSON file.

```json
{
  "width": 1920, "height": 1080, "fps": 60, "background": "#111111",
  "scenes": [
    {"kind": "film", "path": "opening.mp4", "frames": 180},
    {"kind": "picture", "path": "ending.png", "frames": 120}
  ],
  "overlays": [{"path": "caption.png", "at": 30, "until": 150, "x": 0, "y": 0}],
  "audio": [{"path": "music.wav", "at": 0, "gain": 0.5}]
}
```

```sh
# Review representative frames before making the film.
node scripts/media-compose.mjs still out/timeline.json 60 out/frame-60.png
node scripts/media-compose.mjs still out/timeline.json 210 out/frame-210.png
node scripts/media-compose.mjs film out/timeline.json out/finished.mp4
```

The segments are cut together in order, scaled to fit without distortion and letterboxed on the background. Overlays
are unscaled PNGs: use `@film.picture(transparent=true)` to render titles and captions with mbui. Audio tracks are
mixed and cut to the film; sound embedded in a source film is not mixed automatically. The output is H.264 at the
specified rate, with AAC when sound is present. It needs `node`, `ffmpeg`, and `ffprobe`, but no browser. Each result
has a `.timeline.json` record containing the timeline and SHA-256 hashes of the inputs and output. An invalid timeline,
missing input, a source film shorter than requested, or a failed encode leaves an existing result intact.

## Preview in a native window

`MBUI_FIXTURE=home MBUI_WIN=320x560 bash scripts/media.sh preview out/home.drive` opens the same scene and view tree
in a native window, replays the drive and leaves it open for interaction. An optional second path supplies preparation
steps, just as for a picture or film. Close the window to end the preview; run the command again to reset it.
`MBUI_FILM_PLATFORM`, `MBUI_POINTING`, `MBUI_DARK` and the scene's fixture settings apply to both paths.

The preview uses the real window's display clock, screen scale, system bars and native controls. The offscreen host's
simulated native input, keyboard, font scale, local station, window inset, window corner and native navigation bars
are not supplied by a native window; the command rejects their explicit overrides rather than ignoring them. Drive
steps only supported under a Tester, such as `system` and `ime`, cannot be replayed in this window. Use the exported
PNG or film to inspect those settings and frame-accurate timing.

## Prebuilt scene renderer

The macOS Apple Silicon offscreen application renderer is also available as the `mbui-film` native part. To prepare a
small remote job from a source checkout, without synchronizing the checkout or building it on the remote station:

```sh
bash scripts/media-job.sh film out/scene.drive /absolute/path/to/a-new-job [out/prepare.drive]
```

Use that directory as `station_task`'s `dir`. Run `MBUI_FIXTURE=home MBUI_WIN=320x560 bash run.sh` and return
`result.png` and `result.png.scene.json`; set `MBUI_MEDIA_KIND=film` to return `result.mp4`,
`result.mp4.last.png`, `result.mp4.textrec` and `result.mp4.scene.json`. The ordinary `MBUI_*` scene settings still
apply. The job obtains its exact prebuilt renderer by the source key, with the station's shared native-part cache;
it does not build one. If the component sources have changed and that version has not been published, it fails rather
than showing an old component. Build that changed checkout with `scripts/media.sh` instead.
