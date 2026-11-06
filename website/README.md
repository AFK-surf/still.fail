# monoid · official site (new)

A new version of the official site, beside the current one (`site/` and `web/src/site/`, which are unchanged). It is a
static page: HTML, one stylesheet and one script, with no framework and no dependencies.

```
website/
  index.html     the page, in Chinese and English (both in the markup, one shown: .zh / .en)
  styles.css     the visual system (tokens on :root) and every section
  main.js        language, tabs, reveal on scroll, the 168 Week canvas, downloads for this device
  en/            /en/ → /?lang=en
  assets/        icons, the Android QR code (app.monoid.build), Suisse Intl (Latin subsets), Inter (OFL, fallback)
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
"how it works" (picture centred, notes around it) → feature grid with dotted rails → use-case folder tabs → a dark
"enterprise" band → get started → latest releases → download → FAQ → closing call to action → footer. The three things the page is about
each have their own section: **号池** (`#pool`), **协同** (`#teams`), **多端** (`#devices`: iPhone · iPhone Duo, Android,
desktop, web, Slack).

## Motion

- **Every device, played by scrolling** (`#devices`, on screens at least 1024 × 760 with motion allowed: `html.scrolly`,
  set in the head before the first paint). The tabs stay on screen with CSS `position: sticky` inside a tall track that
  is sized from the start, so nothing shifts when the script arrives. GSAP ScrollTrigger scrubs one timeline through it:
  the iPhone Duo is folded, then unfolds (the inner screen turns in on its hinge), then Android rises with its
  notification, then the desktop window with its load bars, then the web app, then Slack on Ink. The tabs, the
  `01 / 05` counter and a progress line follow the scroll. The scroll snaps to each device, without inertia, so none is
  skipped unseen, and a tab click scrolls to its device. Elsewhere, and if GSAP cannot load, they are plain tabs.
- GSAP 3.13 (`assets/vendor/`, about 45 KB gzipped, under GreenSock's standard no-charge license; its notice is kept
  in the files) is fetched only as `#devices` comes within 1600 px, or 2.5 s after `load`.
- The teams grid's pictures loop in CSS: a Slack skeleton whose thread plays out (mention, typing, the reply with its
  Done label), members joining, work packets travelling from Mini to Server, accounts lent, a cursor on a shared
  screen, a phone's run. They run only while on screen (`.cell.play`), and only transforms and opacity move.
- The hero's 168 Week turns at 15° a second (30 fps at most, after `load`, only while visible).
- Everything is still under `prefers-reduced-motion`.

## Visual system

Comma Visual Identity v1.0 (2026-11) for type, colour roles, grid and voice, with monoid's brand colour as its Base;
Reducto's site (on Mobbin) for the section structure, the details and the illustration ideas.

| Token | Value | Use |
| --- | --- | --- |
| `--brand` (Base) | `#EF6334` | Large fields: the hero, the closing band, product stages. Text on it is Ink (5.3:1); white only at display sizes (3.2:1) |
| `--brand-deep` | `#C24A22` | Small text and links on Paper (4.9:1); on-screen user bubbles with white text |
| `--brand-ink` | `#4A1606` | Secondary text on Base (4.6:1) |
| `--brand-haze` | `#F68B64` | The 168 Week's unlit commas on Base |
| `--brand-tint` | `#FFB599` | Accent on Ink |
| Ink / Graphite / Silver / Line / Mist | `#1A1B1E` `#4A4C50` `#A4A5A9` `#E3E3E4` `#F1F1F2` | as in the VI |
| Success / Warning / Error | `#079455` `#F79009` `#D92D20` | status only |

**Type.** Suisse Intl, as in the VI: Regular (400) for running text, Book (500) for UI and labels, Medium (600) for
headlines; −3% tracking on display sizes. Its three Latin subsets (about 21 KB each) are in
`assets/fonts/`, under the team's license; an installed copy is used first. Chinese is set in PingFang SC / Microsoft YaHei, so nothing is downloaded for it. Inter
(OFL) is declared only as a fallback for glyphs outside Suisse's subset. Mono tags use the system's monospace.

**From the VI:** one colour leads each band (Paper, Mist, Base, Ink); the 24-unit grid (1U = width / 24, 1U margins);
**open sentences** (a brand headline ends on a comma, the only punctuation that may take a colour, once per band); the
**168 Week** on the hero's and the closing band's bottom edge (45 lit cells, Mon–Fri 9–18; each comma turns 15° an
hour); **product as graphic** (bubbles, Task chips and the four status labels in the client's shapes, windows with a
Mist frame and three grey lights, grey bars for unwritten content); charts with grey bars and one in colour;
Central-style icons (24 px grid, 2 px round stroke); the voice (result first, real numbers); text left-aligned except
the closing band, the "back cover".

**Marks:** the agents' and places' logos in the strip under the hero are the app's own (`web/ui/src/brands.tsx`),
in their makers' shapes and colours.

**From Reducto:** eyebrow labels with an icon; the overview list beside a large stage; the "how it works" picture with
notes around it (here an isometric stack: new chats → account pool → stations); the feature grid with dotted rails and
pictures on a dot grid; folder tabs for the use cases, their pictures on a halftone ground; small mono tags with a
square glyph and a leader line (on the Week, the plates, the grid and the device pictures); the dark band whose
line drawing sits in a ring of squares with a few lit pixels and dashed construction circles; the "latest articles"
grid, here the nightly releases with pixel-mosaic covers; the closing call to action on a fine grid, round a tile with
scattered pixels.

## Performance

- One request before the first paint once built (CSS and JS inlined): about 37 KB gzipped, plus Suisse Intl's Medium and
  Regular (21 KB each), preloaded; Book follows as the sheet needs it. Chinese uses the system's fonts.
- No images on the page but small SVGs; the product pictures are HTML.
- Bands below the first screen use `content-visibility: auto`.
- The hero's 168 Week draws once at once, and starts turning only after `load` and an idle moment, at most 30 frames a
  second, only while it is on screen and the tab is visible; still under `prefers-reduced-motion`.
- Lighthouse, the built page on a local server. Mobile (simulated slow 4G): Performance 96–98, Accessibility 100, Best
  practices 100, SEO 100; LCP 2.2 s, TBT 0–180 ms, CLS 0.001. Desktop: 100 / 100 / 100 / 100. Compression and cache
  lifetimes come from the host (`_headers`).

## Numbers that go stale

The release cards (`#changelog`: 0.1.7394, 0.1.7190, 0.1.7075) are written by hand from `docs/releases/`. Update it with each stable release, or have `build.mjs` read the latest release note as
`web/vite.demo.config.ts` does.
