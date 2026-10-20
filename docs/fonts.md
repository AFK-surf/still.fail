# Fonts

Each device chooses the faces its pages are set in (外观 › 字体), for three places:

| Place | What | Web variable | Android |
|---|---|---|---|
| `ui` | the app's own words | `--font-body` | MaterialTheme's type (`UiFont` where a style is made whole) |
| `text` | what people and agents wrote: messages, the composer | `--font-text` (`conversation.css.ts` `markdown`, the composers) | `TextFont`: `Markdown`, `SendTextFaced` |
| `code` | code | `--font-mono` | `CodeFont` |

None chosen is the app's own face (text: as ui). The choice is the core's, per device (prefs `fonts`, `prefs.set {fonts:
{ui: "noto-sans-sc"}}`; null puts a place back); the core sends it resolved as `faces` (`FontsView`: each place's
`FontFace`, and `list`, the faces there are), so the clients only draw (client/core-ts/src/fonts.ts).

## The faces

Besides the app's own, the faces still.fail keeps (`FACES` in fonts.ts), all under the SIL Open Font License: Inter,
思源黑体 (Noto Sans SC), 思源宋体 (Noto Serif SC), 霞鹜文楷 (LXGW WenKai), and for code JetBrains Mono, Fira Code,
Maple Mono (CN). On a computer whose browser lists what is installed (Chromium's Local Font Access: the desktop app,
Chrome, Edge) any installed family can be chosen too, kept as `local:<family>`.

`scripts/fonts.py` makes them from where each is published (google/fonts at a fixed commit, the projects' releases)
into `fonts/<id>/<version>/` of the releases bucket, served by the cloud at `/releases/fonts/…` (immutable, any
origin):

- `font.css` and woff2 files for pages: a Chinese face cut by unicode-range into the slices Google Fonts cuts Noto
  Sans SC into, so a page fetches only the slices of the characters it shows; a Latin one whole.
- `<weight>.ttf.gz` (`var` for a variable face) for the Android app, which fetches a face's files whole when it is
  chosen, checks each one's sha256, keeps them in `files/fonts/<sha256>.ttf` and uses the face once all are there
  (until then the app's own stands in). A face no longer chosen has its files removed.

A new face, or a new version of one: add it to `FACES` in fonts.py, run `python3 scripts/fonts.py --put` (fontTools
and brotli; wrangler logged in, from `cloud/`), and copy the files it prints into `FACES` in fonts.ts. Put files are
never changed: a new version is a new folder.
