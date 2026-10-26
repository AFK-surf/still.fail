# still.fail's brand

No character: words and one orange dot (2026-10-26; the rules for where it goes are `docs/ui-panels.md` 品牌).

- **The mark**, `s.`: Inter Bold's s and a round dot of its period's size, the dot `#E5704A`. The end of the site's
  headline, "One devices.", and still's s with still.fail's dot.
- **The wordmark**: still.fail (youdid.wtf on the test channel) in Inter Bold, tracked −0.02em, its period a round
  orange dot drawn a little closer to the words it joins.
- **The app icons**: the mark on its app's tile, the s 44% of the tile's side. still.fail on paper (`#FAFAF9`, the s
  `#18181B`), youdid.wtf on night (`#111114`, the s white), still.fail mbui on violet (`#5B4FD6`, the s white, the dot
  `#FFD66B`), the debug build on grey. `icon-<app>.svg` is the square a system rounds (iOS, a web app's icons),
  `icon-mac-<app>.svg` macOS's (an 824 tile at 100 of 1024, its corner 185, its shadow).
- **The illustrations'** stations (web/public/illus-*.svg, each group marked `data-station`): a machine, a rounded
  box with a light (orange; grey asleep) and a slot.

`make.py` makes all of it from Inter (the web app's, node_modules) and writes it where each app takes it:

| What | Where |
|---|---|
| mark, wordmarks, favicons, illustrations | `web/public/` (`mark*.svg`, `wordmark*.svg`, `favicon*.svg`, `illus-*.svg`) |
| app icons as drawn | `design/brand/icon-*.svg` |
| mbui's launcher (its colours per app), marks and illustrations | `apps/mbui/android/app/src/*/res` |
| macOS, iOS, Windows and Linux icons | the s and dot in `apps/mbui/scripts/mac-icon.swift` (it draws them; the .ico and the .png it made are kept in `apps/mbui/windows/` and `apps/mbui/linux/`) |
| with `png`: the web app's icons, the link previews' card, the Electron app's, the browser extension's | `web/public/*.png`, `apps/desktop/icon*.png`, `apps/extension/icons/` |

    pip install fonttools brotli uharfbuzz
    python3 design/brand/make.py [png]

After it: mbui's drawables (in apps/mbui, `scripts/drawables ../.. > src/sf/drawable_data.mbt`) and, when
mac-icon.swift changed, Windows' and Linux's icons (on a Mac, `swift apps/mbui/scripts/mac-icon.swift --ico
apps/mbui/windows/AppIcon-<its hash>.ico` and `--png apps/mbui/linux/AppIcon-<its hash>.png`, the ones before removed).
