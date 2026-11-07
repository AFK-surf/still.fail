# The official site

The official site of still.fail and of monoid, each with its test channel's: still.fail, youdid.wtf, monoid.build,
monoid.zone (`build.mjs` SITES; `cloud/deploy.py` deploys `site` and `site-beta` from it). It is a static page: HTML,
one stylesheet (split by section) and one script, with no framework and no dependencies. The template is monoid.build's;
each other site is the same page with its name (monoid.zone's is monoid too), its web app and its cloud's downloads
(the beta apps on a test channel's), its share cards and Android code (`assets/og/<site>/`,
`assets/android-qr-<site>.svg`), and the beta apps' icon on a test channel's. The site before it (`site/`, `web/src/site/`) is no longer deployed.

```
website/
  index.html     the page: the template, in English, every translatable piece keyed (data-t, data-t-aria …)
  i18n/          locales.json (the list of languages) and one <locale>.json of translations each
  styles.css     a list of @imports, one file per section in css/ (00-base: tokens, type, motion; 05-components:
                 the shared parts and monoid's own app drawn in HTML/CSS; then 10-nav … 95-footer in page order)
  main.js        the language menu, the nav menu, tabs and swipers, reveal on scroll, the hero's field, the teams
                 pictures, the devices scene, FAQ, copy button, downloads for this device
  en/            the old English address: /en/ → /
  assets/        the mark, icons, Suisse Intl (Latin subsets),
                 Inter (OFL: the product pictures' face, as in the app)
                 vendor/: GSAP and ScrollTrigger (loaded on demand)
                 android-qr.svg, android-qr-<site>.svg: the Android download's QR code (its cloud's
                 /releases/latest/android, -beta on a test channel's site)
                 og/: the share card per language, another site's in og/<site>/ (screenshots of the built hero at
                 1200 × 630, the bar and buttons hidden, the wordmark top left: og.mjs; take them again when the hero
                 changes)
  build.mjs      one page per language into dist/website (--site, --out: another site, elsewhere), everything inlined
                 and trimmed, with the legal pages of web/public; checks the translations
```

## Run and build

```sh
python3 -m http.server -d website 4173      # or any static server: the folder works unbuilt, in English
node website/build.mjs                      # → dist/website: a page per language + assets + sitemap.xml, robots.txt, _headers
node website/build.mjs --site still.fail --out dist/site   # still.fail's (pnpm build:site; youdid.wtf: build:site-beta)
node website/og.mjs [site…]                 # the share cards again (Chrome, playwright-core)
node website/build.mjs --check              # translations: missing, extra, stale, markup, glyphs (exit 1 on any)
```

## Languages

One static page per language, the way comma.surf does it: English at `/`, then `/zh/` (简体中文), `/zh-tw/`
(繁體中文), `/ja/` (日本語), `/ko/` (한국어). Each has its `<html lang>`, its canonical URL, every `hreflang` alternate
(and `x-default` → `/`), `og:url`, `og:locale` and its alternates, its share card (`assets/og/<code>.png`, 1200 × 630,
the page's own hero; the English one where a language has none) and its own descriptions; `sitemap.xml`
lists all five with their alternates. The list lives in one place, `i18n/locales.json` (code, prefix, label, ogLocale,
htmlLang, and `legal`: Chinese pages link still.fail's `/terms`, `/privacy`, `/trademark`, the others `/en/…`, both
served from `web/public`); the build, the head script and the language menu are written from it.

**Who goes where.** Nobody is moved on a first visit (no browser-language guess, so crawlers and shared links get
the page they asked for). The language menu in the footer stores the choice (`localStorage` `monoid.site.locale`) and
opens that page at the same place (hash kept); from then on the head script, before the first paint, sends the reader
from any other language's page to the same path under their language. The old site's `?lang=zh|en` and `#zh|#en`
count as a choice (stored, then dropped from the address), and its stored `stillfail.site.lang` becomes
`monoid.site.locale`. `/en/` redirects to `/`. Unbuilt, the folder is English only and never redirects.

**The menu** (`.footer-prefs` in the footer's bottom row): a pill button (globe, the language's own name, chevron)
with `popovertarget`, and a `popover` `role=menu` of `menuitemradio` links, each label in its own `lang`, the current one
checked. It sits above the button by CSS anchor positioning (flipping below or to the other side when there is no
room); where that is missing, main.js places it beside the button and keeps it there on scroll. Arrow keys, Home and
End move between the languages, Enter or Space picks one; Escape closes it and returns to the button, Tab closes it
and moves on, a click elsewhere closes it. A click with a modifier or the middle button opens that language in a new
tab (the choice is still remembered). On a screen too short to fit it above or below the button, it is pinned to the
top and scrolls inside.
It fades and scales in from the button's corner and leaves faster; still under reduced motion.

**Type.** Suisse Intl draws the Latin on every page; the rest comes from the system's fonts, per page
(`:root:lang(zh-CN)` PingFang SC / Hiragino Sans GB / Noto Sans SC / Noto Sans CJK SC / Source Han Sans SC / Microsoft
YaHei; `zh-TW` PingFang TC / Noto Sans TC / Noto Sans CJK TC / Source Han Sans TC / Microsoft JhengHei; `ja` Hiragino
Sans / Hiragino Kaku Gothic ProN / Noto Sans JP / Noto Sans CJK JP / Source Han Sans JP / Yu Gothic; `ko` Apple SD Gothic
Neo / Noto Sans KR / Noto Sans CJK KR / Source Han Sans KR / Malgun Gothic: Apple's, then Noto as Android and Linux name
it, then Windows'). Language-specific rules key on `:lang()`: CJK is
`:root:is(:lang(zh), :lang(ja), :lang(ko))` (more leading; no tracking on headlines, sub-heads or labels, since Latin
tracking is not for square glyphs; the hero and closing headlines held to 12 em, so each breaks only at its `<br>`;
short paragraphs balanced from 641 px, so none ends on a few glyphs), Latin the rest; Chinese and Japanese headlines use
half-width punctuation (`halt`), Chinese and Korean headlines, card titles and FAQ questions keep words whole
(`keep-all`), Japanese breaks between phrases (`auto-phrase`) where the browser can, its short paragraphs too. A headline's text is
one `<span>` (its translation), which those rules select.

**The brand line is translated.** "One devices" (the hero's `<h1>`, `hero.one-devices.*`, and the `<title>` /
`og:title`, `meta.monoid-one-devices.*`) is said in each language: 所有设备，合而为一 / 所有裝置，合而為一 /
すべてのデバイスを、ひとつに (the headline, shorter: 全デバイスを、ひとつに) / 모든 기기를 하나로. In the headline the comma breaks the line (a visually hidden comma and a
`<br>`, so it still reads as one sentence); the share cards in `assets/og/` show each language's line.

### Changing the copy

`index.html` holds the English. Each piece someone translates is one element whose content is the piece:
`<span data-t="teams.one-person-asks-the.baa8">One person asks, the whole team carries on</span>` (in SVG a
`<tspan data-t>`; in the head `<title data-t>`), and attributes take `data-t-<attribute>`: `data-t-aria` for
`aria-label`, `data-t-content` for a `<meta>`'s `content`, `data-t-aria-roledescription`. main.js's own words (the copy
button's status line, the "This device" tag) are spans in `<template id="i18n-js">`, read by their `data-js`.

A key is `<section>.<first four English words>.<4 hex of the English's SHA-1>`; the section is the nearest
`<section id>` or `============ Name ============` comment above it, or a `data-i18n-section` around it (the devices
scene's template is `devices-stage`; a mockup that repeats some English with different Chinese got its own,
`product-2`).

- **Edit English:** change the text, then `node website/build.mjs --rekey`. The key's hash changes, so the old
  translations stop applying (the page shows English there) and `--check` lists the piece as missing in every
  language, until it is translated again. That is the staleness check: a translation can never silently describe
  English that changed. (Until you run `--rekey`, the build warns and uses English for that piece.)
- **Add a piece:** wrap it as above with `data-t=""` (or `data-t-aria=""`), then `--rekey`.
- **Markup inside a piece** (`<b>`, `<a href>`, `<code>`) must come through translation: the build fails if a
  translation's tags (and every link's `href`) are not the English's. `<br>`, `<wbr>`, `<span class="nb">` (keep
  together) and `<span class="vh">` (visually hidden) are free: each language uses its own.
- `node website/build.mjs --extract [file]` writes `{ key: English }` for translators (default
  `dist/i18n/en-source.json`).

### Adding a language

Add it to `i18n/locales.json`, add `i18n/<code>.json` (start from `{}`; the page falls back to English, with a warning,
and `--strict` fails instead), give it a font stack in `css/00-base.css` if its script needs one, and fill it from
`--extract`. `--check <code>` reports missing and extra keys, markup that differs from the English, and characters
outside Suisse Intl's `unicode-range` that are not CJK, kana, Hangul or full-width (which the system's fonts draw).

### How it got here

Until November 2026 the page held Chinese and English side by side (`<span class="zh">…</span><span class="en">…</span>`,
`aria-label` + `data-aria-en`, a 中/EN toggle in the bar). A one-time script turned it into the English template and
`i18n/zh-CN.json`; it can be run again on a newer copy of the bilingual page and merges into the existing translations
(keeps those whose keys still exist, lists the new ones). The built `/` and `/zh/` matched the old page in English and
Chinese pixel for pixel (1440 × 900 and 390 × 844, full page, with motion reduced).

## Structure

Section order (first taken from Reducto's site on Mobbin): hero → logo strip → pool (list left, picture right) →
teams grid → the devices → security → get started → latest release → download → FAQ → closing call to action →
footer. The three things the page is about each have their own section: **号池** (`#pool`), **协同** (`#teams`),
**多端** (`#devices`: iPhone · iPhone Duo, Android, desktop, web, Slack).

## Visual system

monoid's identity (Suisse Intl, the mark and wordmark, the field motif, the faithful product pictures, the brand
orange as its one accent) set with the restraint of Runner's site (on Mobbin): paper and ink, a book serif for
headlines, mono for utility, dashed guide lines, dot-grid panels, generous whitespace, one dark band. There is no comma
language: headlines end as sentences do, and no comma appears as a motif, glyph, pattern or swatch. (A Chinese
two-line headline keeps its comma for screen readers only, `.vh`, where the line breaks.)

| Token | Value | Use |
| --- | --- | --- |
| `--paper` | `#FAFAF8` | the page, every band but one |
| `--card` / `--panel` | `#FFFFFF` / `#F4F3F0` | cards and app windows / panels behind product pictures (with `--dots`) |
| `--line` / `--guide` / `--dot` | `#E6E4DF` / `#DEDCD7` / `#C9C7C1` | solid card borders / dashed guides and rules / dot textures |
| `--graphite` / `--silver` | `#6E6C68` / `#A3A19B` | secondary text (5.0:1 on paper, 4.7:1 on panel) / quiet marks |
| `--ink` | `#1C1B1A` | text, primary buttons, the terminal |
| `--night` | `#1F1E1D` | the dark band (closing call + footer): text `#F4F3F0`, secondary `#A3A19B` (6.4:1) |
| `--brand` / `--brand-deep` | `#EF6334` / `#C24A22` | the mark only / small accents on paper (4.7:1): the current step or card number, step 02, a link's hover underline, the menu's current marker, the focus ring |
| Success / Warning / Error | `#079455` `#F79009` `#D92D20` | status only |

Two tones (`data-tone`: `paper`, `ink`), which set the band's text, hairline, guide, link and focus colours; the nav bar
turns dark over the dark band. The orange is never a fill behind text, a card or a band.

**Guides and rules.** Every band draws two dashed lines (4 on, 4 off, `--guide`) on the container's edges, behind its
content (`.band::before`, z-index −1 in the band's own stacking context, so a card or panel covers them), and a dashed
rule across the page where it meets the band above (`::after`); the bar draws the same lines and a dashed rule under
it, so they run the whole page. The container is `--cw` (1200 px) at most, with 1U margins below that. Grids are split
by dashed rules (teams cells, download cells, callouts, notes, steps), the FAQ rows by dotted ones.

**Panels.** Product pictures sit on a warm-grey panel with a faint 14 px dot grid (`--dots` on `--panel`): the pool's
picture, the teams frames, the devices scene's picture side and the swiper cards. App windows on them are white with a
hairline and a soft, low, neutral shadow.

**The mark's motif.** Under the hero and at the closing band's foot, a low band of a field taken from the mark
(`assets/mark.svg`: a dark rounded square, two round eyes, two pill cheeks), abstract and never a face: one cell per
grid unit (1U; 1.5U on a tablet, 2U on a phone), each a dot (an eye) or a pill (a cheek), five rows in the hero (four on
a phone), three at the end. Its colours are the band's (`--f-eye`, `--f-cheek`, `--f-you` on the field's wrap, as
"r g b"): greys on paper with one Ink dot, dark greys on the dark band with one light dot. That dot, a sixth of the way
in on the second row, is "you"; every few seconds a ripple runs out from it, and each cell it reaches turns to the
other part. Drawn on a canvas; a pause button sits on a cleared cell.

**Type.** Headlines (`h1`, `h2`, the closing headline, the devices' step and card titles, the FAQ questions) are
Newsreader Regular (400), a book serif (`--serif`); Chinese, Japanese and Korean headlines use the system's serif
(zh-CN Songti SC / STSong / Noto Serif SC / Noto Serif CJK SC / Source Han Serif SC, then PingFang SC / Microsoft
YaHei; zh-TW Songti TC / Noto Serif TC …; ja Hiragino Mincho ProN / Yu Mincho / Noto Serif JP …, then Hiragino Sans /
Yu Gothic; ko AppleMyungjo / Noto Serif KR …, then Apple SD Gothic Neo / Malgun Gothic; never SimSun) at 500, which
takes a face's Medium where it has one and its Regular otherwise. Suisse Intl sets everything else: Regular (400) for
running text (15–16 px, Graphite), Book (500) for UI and labels, Medium (600) for sub-heads and the wordmark. The nav,
small captions, tags, overlines (uppercase, tracked) and numerals use the system's monospace (`--mono`); on Chinese,
Japanese and Korean pages the nav's labels are in the sans, and `--mono` names the script's sans before the generic
`monospace` (CJK has no mono; the generic would fall to a SimSun-family face on Windows). Size, leading and tracking move as a set (`--t-*`, `--lh-*`,
`--tr-*` in 00-base.css): section titles 32 px, the hero 36–52 px, the closing headline 30–40 px. Newsreader's Latin
subset (22 KB, 400 only, preloaded) is `assets/fonts/newsreader-400.woff2`, under the SIL Open Font License
(`Newsreader-OFL.txt`, Production Type); Suisse Intl's three Latin subsets (about 21 KB each) are under the team's
license; an installed copy of either is used first. Chinese, Japanese and Korean are set in the system's fonts (see
Languages), so nothing is downloaded for them. A half-width space separates Chinese from Latin and figures.

**Buttons.** Small-radius rectangles (6 px, 42–44 px tall, Suisse 15 px): Ink fill, or a 1 px outline at 20% Ink; on
the dark band a light fill and a light outline. Pressed: scale .96 at once (150 ms, still under reduced motion).

**Product pictures.** Every picture of monoid's own app (the desktop client, the web app, iPhone Duo, Android, the
Slack thread) is HTML/CSS drawn to the product's own values at 1:1 (`.mk*` in 05-components.css: its colours, its
Inter + PingFang type, its radii, its demo data: lin@acme.dev, Willow, Mini, the same chats); a whole picture is
scaled with `zoom` (or, in the scroll scene, a transform), never by shrinking its type, and the product's own oranges
are used, not the brand's. Pictures are `aria-hidden`, unselectable and take no pointer events. The phones follow the
app (`apps/mbui`): the phone chat's top bar has no line under it (docs/mobile-parity.md); the iPhone Duo open is its
inner screen (890 × 626 points) with the sidebar ending on the fold, the panes as cards and no rail, the places, the
chat's actions, the bell and the new chat in iOS 27.1's own column down the trailing edge (`sf/native_bars.mbt`,
`host/ios_nav.h`); Android shows the debug share's ongoing notification as `AdbShare.java` builds it, in the pulled-down
shade (it is low importance: it never pops up), its small icon in the status bar. The teams grid's pictures are 4:3,
each drawn 400 × 300 and zoomed in steps to its frame.

**Marks:** the agents' and places' logos in the strip under the hero are the app's own (`web/ui/src/brands.tsx`), in
their makers' shapes and colours.

**Kept from Reducto:** the pool's isometric stack (new chats → account pool → stations) with quiet mono captions on
leaders; the security network's ring of squares with a few dark pixels and dashed construction circles; the release's
pixel-mosaic cover and pixel bar charts.

**Craft.** Hover only behind `(hover: hover) and (pointer: fine)`; `:active` press feedback on every control; a
visible `:focus-visible` ring in each band's tone.

## Phones

Designed for 375–430 px, not shrunk: the overview, the teams grid and the devices are native horizontal swipers
(`scroll-snap`, the next card peeking in, dots and a `01 / 04` count that follow the scroll and jump on tap; the
browser owns the gesture and its momentum). The first screen uses `svh`; safe-area insets pad the gutters
(`viewport-fit=cover`); controls are at least 44 px, with `touch-action: manipulation`, no tap highlight and
`user-select: none` (content stays selectable). The menu is a sheet from under the bar (Escape or the dimmed page
closes it, focus stays inside). In landscape the overview stacks and the devices' cards recompose for the short
screen; checked with WebKit on an iPhone SE, 15 Pro and 15 Pro Max, both ways round.

## Motion

Tokens in 00-base.css: `--ease-out`, `--ease-in-out`, `--ease-drawer`, `--dur-press` (150 ms), `--dur-ui` (200 ms),
`--dur-reveal` (520 ms), `--stagger` (60 ms). UI answers in under 300 ms; only explanations take longer. Only
transform and opacity move.

- **Reveal.** Everything is visible at the first paint; only what starts below the fold waits and comes in as it
  reaches the screen, groups one child after another.
- **Every device, as one scene played by scrolling** (`#devices`, on screens at least 1024 × 760 with motion allowed:
  `html.scrolly`, set in the head before the first paint). Four steps, one device each, upright and whole in the
  middle of the stage's dotted panel at the size that fills it (main.js `fit`, read as the trigger refreshes): the
  iPhone Duo open on two panels, Android, the desktop app, the web app. Between steps the words and the device
  cross-fade (opacity and at most 12 px up), scrubbed by the scroll. The words (on the paper beside the panel), a
  `01 / 04` counter and a rail of the devices (each a link to its step) follow along. The
  stage is CSS `position: sticky` in a placeholder sized from the first paint; the scene is built from a `<template>`
  only where it plays (phones never parse it). GSAP ScrollTrigger scrubs one timeline and snaps to each step. Elsewhere,
  and if GSAP cannot load, the devices are the swiper.
- GSAP 3.13 (`assets/vendor/`, about 45 KB gzipped, under GreenSock's standard no-charge license; its notice is kept
  in the files) is fetched only as `#devices` comes within 1600 px, or 2.5 s after `load`.
- **Loops only while on screen**: the hero's field (canvas, at most 30 fps, only during a ripple, only while visible and
  the tab is shown, after `load`); the overview's pictures and its auto-advance (wide screens); the pool's three-layer
  round (`.pool-fig.play`); the teams pictures (`.cell.play`, stepped by timers); the devices swiper's active card; the
  security network (`.sec-net.off` holds it). Off screen everything holds where it is.
- `prefers-reduced-motion`: nothing moves; reveals are short fades; every picture stands at its outcome.

## Copy

Every language says the same thing: concise, from first principles; each sentence says what monoid does or why it
matters, with real numbers (80% of a 5-hour limit, 5 minutes between quota reads, 64 stations per workspace); only
claims the product and its docs make. The hero has no label row: the headline, the lead and two calls to action.

## Performance

- One request before the first paint once built (CSS and JS inlined): about 239–246 KB, 55–58 KB gzipped, per language, plus
  Newsreader (22 KB) and Suisse Intl's Regular and Book (21 KB each: the first screen's text, buttons and the lead's bold
  phrases), preloaded; Medium (the wordmark and sub-heads) follows as the sheet needs it; Inter (48 KB) only as product
  pictures need it. Chinese, Japanese and Korean use the system's fonts. No new external requests; no images on the page but small SVGs.
- Bands below the first screen use `content-visibility: auto`, and so do the overview's cards on a phone, so the first
  layout covers little more than the first screen.
- The script reads no layout while the page parses: first states are taken in the first frame or by `ResizeObserver`.
- The devices scene is cloned from its template only as it comes near (or 2.5 s after `load`), not in the frames after
  the first paint. A swiper card's picture is laid out only when it is the card in view or next to it (`[data-near]`,
  set by main.js), so the four pictures never land in one frame.
- The devices scene's tweens read their start values once, at an idle moment while the reader is still above it, not
  in the frames of the first scroll through it.
- Lighthouse 12.6.1, the built page. Served compressed, as a host does (gzip, `_headers` cache lifetimes): mobile
  (simulated slow 4G, en and ja, three runs each) Performance 98; FCP 1.5 s, LCP 2.3 s (the hero's lead), TBT
  0–80 ms, CLS 0. Desktop: Performance, Accessibility, Best practices and SEO 100; FCP 0.4 s, LCP 0.5 s. On a plain `python3 -m http.server` (no compression) mobile
  Performance is 92 (FCP 2.4 s: the page uncompressed); compression comes from the host.

## Numbers that go stale

The release cards (`#changelog`: 0.1.7394, 0.1.7190, 0.1.7075) are written by hand from `docs/releases/`. Update
them with each stable release, or have `build.mjs` read the latest release note as `web/vite.demo.config.ts` does.
