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
- The mbui app (apps/mbui) fetches the same `.ttf.gz` files, through the core, which keeps them for it in the host's
  storage (client/core-ts/src/font-files.ts): `fonts.fetch {id}` fetches a face's files not kept yet (how far it got
  on the `fonts` topic: `fetching` by face, 0 to 1, `failed`, why, and `kept`, the faces whose files are all here); `fonts.file {sha256}` gives one back beside
  the answer (`zipped`: as fetched); the app unzips it (mbui's `zip`), checks its sha256 and gives it back unzipped
  (`fonts.keep {sha256}`), and gives a face to the host once all its files are here. Where the host keeps each value
  as a file (the native apps' shell, `storage.path`), the prefs' `faces` say where each file of a place's face is kept
  (`path`): the app gives them to its host by where they are the frame the prefs come, so its first page is set in
  them, nothing asked of the core, carried through it or checked again (one the host cannot read there, kept as
  fetched: had through `fonts.file` as above). A face's files stay once fetched, chosen or not, so
  choosing it again fetches nothing (the page says no size for it). `fonts.preview {id}` gives a face's preview (below), fetched once and kept.
- `preview-<hash>.ttf` for the Android app too: the face's glyphs for the fonts page's own words alone (its catalog
  keys `web-pages.appearance.fonts.*`, the faces' names, ASCII; tens of KB), fetched as the page opens so each face
  is shown in itself before it is chosen. Changing those words: `scripts/fonts.py --put --previews` and copy the
  names it prints into `FACES`.

## The page

外观 › 字体: the places as a switch (界面 / 正文 / 代码), under it the faces of the place in view, each drawn in
itself, and a chat (a message in its bubble, an agent's with inline code and a block of it) as the faces set it. On
the wide screen the faces are tiles (`Aa 字` and the name) and one pointed at is tried in the preview before it is
chosen; installed families are a last tile opening a searchable list. On a phone (web and Android) they are rows, the
name and a line of the face.

A new face, or a new version of one: add it to `FACES` in fonts.py, run `python3 scripts/fonts.py --put` (fontTools
and brotli; wrangler logged in, from `cloud/`), and copy the files it prints into `FACES` in fonts.ts. Put files are
never changed: a new version is a new folder.

## The share card's face

The card to share (docs/ui-panels.md) is set in a face of its own whatever a device chose: 霞鹜文楷 for Chinese, EB
Garamond (grown 1.14 times, as tall as 文楷) for Latin and figures, made one font a weight (a host face has no fallback
of its own) with only the characters the card says, and carried in the app (`apps/mbui/src/sfbase/share_face.mbt`,
host face 14). `python3 scripts/fonts.py --share` makes it again; run it when the card's words change.
