# monoid · official site (new)

A new version of the official site, beside the current one (`site/` and `web/src/site/`, which are unchanged). It is a
static page: HTML, one stylesheet (split by section) and one script, with no framework and no dependencies.

```
website/
  index.html     the page, in Chinese and English (both in the markup, one shown: .zh / .en)
  styles.css     a list of @imports, one file per section in css/ (00-base: tokens, type, motion; 05-components:
                 the shared parts and monoid's own app drawn in HTML/CSS; then 10-nav … 95-footer in page order)
  main.js        language, menu, tabs and swipers, reveal on scroll, the hero's field, the teams pictures,
                 the devices scene, FAQ, copy button, downloads for this device
  en/            /en/ → /?lang=en
  assets/        the mark, icons, the Android QR code (app.monoid.build), Suisse Intl (Latin subsets),
                 Inter (OFL: the product pictures' face, as in the app)
                 vendor/: GSAP and ScrollTrigger (loaded on demand)
  build.mjs      inlines and trims everything into dist/website for deploy
```

## Run and build

```sh
python3 -m http.server -d website 4173      # or any static server: the folder works unbuilt
node website/build.mjs                      # → dist/website: one HTML file + assets + _headers
```

The language is chosen by `?lang=en|zh`, then `#en|#zh`, then the visitor's earlier choice (`localStorage`
`monoid.site.lang`), then the browser's language.

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
Chinese takes more leading than Latin. Its three Latin subsets (about 21 KB each) are in `assets/fonts/`, under the
team's license; an installed copy is used first. Chinese is set in PingFang SC / Microsoft YaHei, so nothing is
downloaded for it. Mono tags use the system's monospace. A half-width space separates Chinese from Latin and figures.

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

Both languages say the same thing: concise, from first principles; each sentence says what monoid does or why it
matters, with real numbers (80% of a 5-hour limit, 5 minutes between quota reads, 64 stations per workspace); only
claims the product and its docs make. The hero has no label row: the headline, the lead and two calls to action.

## Performance

- One request before the first paint once built (CSS and JS inlined): about 323 KB, 73 KB gzipped, plus Suisse Intl's
  Medium and Regular (21 KB each), preloaded; Book follows as the sheet needs it; Inter (48 KB) only as product
  pictures need it. Chinese uses the system's fonts. No new external requests; no images on the page but small SVGs.
- Bands below the first screen use `content-visibility: auto`, and so do the overview's cards on a phone, so the first
  layout covers little more than the first screen.
- The script reads no layout while the page parses: first states are taken in the first frame or by `ResizeObserver`.
- Lighthouse 12.6.1, the built page. Served compressed, as a host does (gzip, `_headers` cache lifetimes): mobile
  (simulated slow 4G) Performance 100, Accessibility 100, Best practices 100, SEO 100; FCP 1.2 s, LCP 1.7 s, TBT
  0–60 ms, CLS 0–0.001. Desktop 100 / 100 / 100 / 100. On a plain `python3 -m http.server` (no compression) mobile
  Performance is 92 (FCP 2.4 s: 323 KB uncompressed); compression comes from the host.

## Numbers that go stale

The release cards (`#changelog`: 0.1.7394, 0.1.7190, 0.1.7075) are written by hand from `docs/releases/`. Update
them with each stable release, or have `build.mjs` read the latest release note as `web/vite.demo.config.ts` does.
