# still.fail's brand

A face, and words with one orange dot (2026-10-29; the rules for where it goes are `docs/ui-panels.md` 品牌).

- **The mark**: a face on a rounded square, two round eyes and two cheeks (the app icon's before 2026-10-26, its eyes a
  little larger to hold at 16 px). The black face (`#1C1D20`, its eyes white) where things are light, the white face
  (`#F4F4F5`, its eyes `#1C1D20`) where they are dark, the cheeks `#F6BC9F` on both. It is a device's screen: the
  site's "One devices.", every station in the illustrations.
- **The wordmark**: still.fail (youdid.wtf on the test channel) in Inter Bold, tracked −0.02em, its period a round
  orange dot (`#E5704A`) drawn a little closer to the words it joins.
- **The app icons**: the face on its app's tile. still.fail the black face, `-dark` its white one (the Dock while the
  app runs on a dark system, iOS's dark icon, Android's values-night); youdid.wtf the same with an orange tape across
  the top right corner, BETA on it (between x − y = 42 and 62 of the tile's 100: inside a launcher's round mask, clear
  of the eyes); the debug build grey. `icon-<app>.svg` is the square a system rounds (iOS, a web app's icons),
  `icon-mac-<app>.svg` macOS's (an 824 tile at 100 of 1024, its corner 185, its shadow).
- **The illustrations** (web/public/illus-*.svg, made by `illus.py`): devices and the wires that join them, as the
  site draws its idea. One line weight; devices outlined in ink, what is on them in a lighter grey; orange only for a
  live wire (its running dots) and a station's light. Not joined: a dashed grey wire; not there yet: a dashed outline;
  cut off: a plug pulled out. A station is a machine with the face, its light in the corner (grey and its eyes shut
  asleep).

`make.py` makes all of it from Inter (the web app's, node_modules) and writes it where each app takes it:

| What | Where |
|---|---|
| mark, wordmarks, favicons, illustrations | `web/public/` (`mark*.svg`, `wordmark*.svg`, `favicon*.svg`, `illus-*.svg`) |
| app icons as drawn | `design/brand/icon-*.svg` |
| mbui's launcher (its colours per app, values-night's the white face; youdid.wtf's face its own, under the tape), marks and illustrations | `apps/mbui/android/app/src/*/res` |
| macOS, iOS, Windows and Linux icons | the face's shapes in `apps/mbui/scripts/mac-icon.swift` (it draws them; the .ico and the .png it made are kept in `apps/mbui/windows/` and `apps/mbui/linux/`) |
| with `png`: the web app's icons, the link previews' card, still.fail Helper's, the browser extension's | `web/public/*.png`, `station/native/helper/icon.png`, `apps/extension/icons/` |

    pip install fonttools brotli uharfbuzz
    python3 design/brand/make.py [png]      (png: CHROME a headless Chrome, e.g. Playwright's chrome-headless-shell)

After it: mbui's drawables (in apps/mbui, `scripts/drawables ../.. > src/sf/drawable_data.mbt`) and, when
mac-icon.swift changed, Windows' and Linux's icons (on a Mac, `swift apps/mbui/scripts/mac-icon.swift --ico
apps/mbui/windows/AppIcon-<its hash>.ico` and `--png apps/mbui/linux/AppIcon-<its hash>.png`, the ones before removed).
