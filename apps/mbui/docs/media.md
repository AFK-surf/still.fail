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
use a real system capture for a scene that needs them. `docs/figures.md` describes building reusable graphics.
