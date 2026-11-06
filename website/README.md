# monoid · official site (new)

A new version of the official site, beside the current one (`site/` and `web/src/site/`, which are unchanged). It is a
static page: HTML, one stylesheet (split by section) and one script, with no framework and no dependencies.

```
website/
  index.html     the page: the template, in English, every translatable piece keyed (data-t, data-t-aria …)
  i18n/          locales.json (the list of languages) and one <locale>.json of translations each
  styles.css     a list of @imports, one file per section in css/ (00-base: tokens, type, motion; 05-components:
                 the shared parts and monoid's own app drawn in HTML/CSS; then 10-nav … 95-footer in page order)
  main.js        the language menu, the nav menu, tabs and swipers, reveal on scroll, the hero's field, the teams
                 pictures, the devices scene, FAQ, copy button, downloads for this device
  en/            the old English address: /en/ → /
  assets/        the mark, icons, the Android QR code (app.monoid.build), Suisse Intl (Latin subsets),
                 Inter (OFL: the product pictures' face, as in the app)
                 vendor/: GSAP and ScrollTrigger (loaded on demand)
                 og/: the share card per language (screenshots of the built hero at 1200 × 630, the bar and buttons
                 hidden, the wordmark top left; take them again when the hero changes)
  build.mjs      one page per language into dist/website, everything inlined and trimmed; checks the translations
```

## Run and build

```sh
python3 -m http.server -d website 4173      # or any static server: the folder works unbuilt, in English
node website/build.mjs                      # → dist/website: a page per language + assets + sitemap.xml, robots.txt, _headers
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
count as a choice (stored, then dropped from the address), and its stored `monoid.site.lang` becomes
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
`:root:is(:lang(zh), :lang(ja), :lang(ko))` (more leading, headline tracking −1%, the hero and closing headlines
narrower), Latin the rest; Chinese and Japanese headlines use half-width punctuation (`halt`), Chinese and Korean keep
words whole (`keep-all`), Japanese breaks between phrases (`auto-phrase`) where the browser can. A headline's text is
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

Section order follows Reducto's site (on Mobbin): hero → logo strip → product overview (list left, picture right) →
"how it works" (picture centred, notes around it) → feature grid with dotted rails → the devices → a dark security band
→ get started → latest releases → download → FAQ → closing call to action → footer. The three things the page is about
each have their own section: **号池** (`#pool`), **协同** (`#teams`), **多端** (`#devices`: iPhone · iPhone Duo, Android,
desktop, web, Slack).

## Visual system

monoid's own: the brand colour Base `#EF6334` and its roles, Suisse Intl, the 24-unit grid, and a motif taken from the
mark. Reducto's site (on Mobbin) gives the section structure, the details and the illustration ideas. There is no comma
language: headlines end as sentences do, and no comma appears as a motif, glyph, pattern or swatch. (A Chinese
two-line headline keeps its comma for screen readers only, `.vh`, where the line breaks.)

| Token | Value | Use |
| --- | --- | --- |
| `--brand` (Base) | `#EF6334` | Large fields: the hero, the closing band, product stages. Text on it is Ink (5.3:1); white only at display sizes (3.2:1) |
| `--brand-deep` | `#C24A22` | Small text and links on Paper (4.9:1); focus ring on light bands |
| `--brand-ink` | `#4A1606` | Secondary text on Base (4.6:1) |
| `--brand-haze` / `--brand-tint` | `#F68B64` / `#FFB599` | a lighter Base for marks at rest on Base / accent on Ink |
| Ink / Graphite / Silver / Line / Mist | `#1A1B1E` `#4A4C50` `#A4A5A9` `#E3E3E4` `#F1F1F2` | text, hairlines, the Mist band |
| Success / Warning / Error | `#079455` `#F79009` `#D92D20` | status only |

One colour leads each band (Paper, Mist, Base, Ink, set by `data-tone`, which also sets the band's text, hairline,
link and focus colours); the nav bar takes the tone of the band behind it.

**The mark's motif.** The hero's lower part and the closing band's bottom edge are a field taken from the mark
(`assets/mark.svg`: a dark rounded square, two round white eyes, two peach pill cheeks), abstract and never a face:
one cell per grid unit (1U; 1.5U on a tablet, 2U on a phone), each a white dot (an eye) or a peach pill (a cheek). One
Ink dot, a sixth of the way in on the second row, is "you"; every few seconds a ripple runs out from it, and each cell
it reaches turns to the other part. Drawn on a canvas; a pause button sits on a cleared cell.

**Type.** Suisse Intl: Regular (400) for running text, Book (500) for UI and labels, Medium (600) for headlines. Size,
leading and tracking move as a set (`--t-*`, `--lh-*`, `--tr-*` in 00-base.css): the larger the size, the tighter both;
Chinese, Japanese and Korean take more leading than Latin. Its three Latin subsets (about 21 KB each) are in
`assets/fonts/`, under the team's license; an installed copy is used first. Chinese, Japanese and Korean are set in the
system's fonts (see Languages), so nothing is downloaded for them. Mono tags use the system's monospace. A half-width space separates Chinese from Latin and figures.

**Product pictures.** Every picture of monoid's own app (the desktop client, the web app, iPhone, iPhone Duo, Android,
the Slack thread) is HTML/CSS drawn to the product's own values at 1:1 (`.mk*` in 05-components.css: its colours, its
Inter + PingFang type, its radii, its demo data: lin@acme.dev, Willow, Mini, the same chats); a whole picture is
scaled with `zoom`, never by shrinking its type, and the product's own oranges are used, not the brand's. Pictures are
`aria-hidden`, unselectable and take no pointer events.

**Marks:** the agents' and places' logos in the strip under the hero are the app's own (`web/ui/src/brands.tsx`), in
their makers' shapes and colours.

**From Reducto:** eyebrow labels with an icon; the overview list beside a large stage; the "how it works" picture with
notes around it (here an isometric stack: new chats → account pool → stations); the feature grid with dotted rails and
pictures on a dot grid; small mono tags with a square glyph and a leader line; the dark band whose line drawing sits in
a ring of squares with a few lit pixels and dashed construction circles; the "latest articles" grid, here the nightly
releases with pixel-mosaic covers and pixel bar charts; the closing call to action on a fine grid.

**Craft.** Hover only behind `(hover: hover) and (pointer: fine)`; `:active` press feedback on every control; a
visible `:focus-visible` ring in each band's tone.

## Phones

Designed for 375–430 px, not shrunk: the overview, the teams grid and the devices are native horizontal swipers
(`scroll-snap`, the next card peeking in, dots and a `01 / 05` count that follow the scroll and jump on tap; the
browser owns the gesture and its momentum). The first screen uses `svh`; safe-area insets pad the gutters
(`viewport-fit=cover`); controls are at least 44 px, with `touch-action: manipulation`, no tap highlight and
`user-select: none` (content stays selectable). The menu is a sheet from under the bar (Escape or the dimmed page
closes it, focus stays inside). In landscape the overview stacks and the devices' cards recompose for the short
screen; checked with WebKit on an iPhone SE, 15 Pro and 15 Pro Max, both ways round.

## Motion

Tokens in 00-base.css: `--ease-out`, `--ease-in-out`, `--ease-drawer`, `--dur-press` (140 ms), `--dur-ui` (200 ms),
`--dur-reveal` (520 ms), `--stagger` (60 ms). UI answers in under 300 ms; only explanations take longer. Only
transform and opacity move.

- **Reveal.** Everything is visible at the first paint; only what starts below the fold waits and comes in as it
  reaches the screen, groups one child after another.
- **Every device, as one scene played by scrolling** (`#devices`, on screens at least 1024 × 760 with motion allowed:
  `html.scrolly`, set in the head before the first paint). One conversation travels across the screens in six steps:
  the iPhone Duo folded, a notification landing on its cover screen; the Duo unfolding on its hinge; Android flying in,
  a line tying it to the same chat; the camera pulling back to the desktop window with the phones on its corners; the
  window becoming the web app; Slack coming in, the band turning Ink, lines running from the thread to every screen.
  The words, a `01 / 06` counter, a rail of the devices (each a link to its step) and a mono tag follow along. The
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

- One request before the first paint once built (CSS and JS inlined): about 295–303 KB, 65–68 KB gzipped, per language, plus Suisse Intl's
  Medium and Regular (21 KB each), preloaded; Book follows as the sheet needs it; Inter (48 KB) only as product
  pictures need it. Chinese, Japanese and Korean use the system's fonts. No new external requests; no images on the page but small SVGs.
- Bands below the first screen use `content-visibility: auto`, and so do the overview's cards on a phone, so the first
  layout covers little more than the first screen.
- The script reads no layout while the page parses: first states are taken in the first frame or by `ResizeObserver`.
- The devices scene's tweens read their start values once, at an idle moment while the reader is still above it, not
  in the frames of the first scroll through it.
- Lighthouse 12.6.1, the built page. Served compressed, as a host does (gzip, `_headers` cache lifetimes): mobile
  (simulated slow 4G) Performance 100, Accessibility 100, Best practices 100, SEO 100; FCP 1.2 s, LCP 1.7 s, TBT
  0–60 ms, CLS 0–0.001. Desktop 100 / 100 / 100 / 100. On a plain `python3 -m http.server` (no compression) mobile
  Performance is 92 (FCP 2.4 s: the page uncompressed); compression comes from the host.

## Numbers that go stale

The release cards (`#changelog`: 0.1.7394, 0.1.7190, 0.1.7075) are written by hand from `docs/releases/`. Update
them with each stable release, or have `build.mjs` read the latest release note as `web/vite.demo.config.ts` does.
