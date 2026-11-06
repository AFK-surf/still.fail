# monoid · official site (new)

A new version of the official site, beside the current one (`site/` and `web/src/site/`, which are unchanged). It is a
static page: HTML, one stylesheet and one script, with no framework and no dependencies.

```
website/
  index.html     the page: the template, in English, every translatable piece keyed (data-t, data-t-aria …)
  i18n/          locales.json (the list of languages) and one <locale>.json of translations each
  styles.css     the visual system (tokens on :root) and every section
  main.js        the language menu, tabs, reveal on scroll, the 168 Week canvas, downloads for this device
  en/            the old English address: /en/ → /
  assets/        icons, the Android QR code (app.monoid.build), Suisse Intl (Latin subsets), Inter (OFL, fallback)
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
(`:root:lang(zh-CN)` PingFang SC / Hiragino Sans GB / Noto Sans SC / Microsoft YaHei; `zh-TW` PingFang TC / Noto Sans TC
/ Microsoft JhengHei; `ja` Hiragino Sans / Hiragino Kaku Gothic ProN / Noto Sans JP / Yu Gothic; `ko` Apple SD Gothic
Neo / Noto Sans KR / Malgun Gothic). Language-specific rules key on `:lang()`: CJK is
`:root:is(:lang(zh), :lang(ja), :lang(ko))` (more leading, headline tracking −1%, the hero and closing headlines
narrower), Latin the rest; Chinese and Japanese headlines use half-width punctuation (`halt`), Chinese and Korean keep
words whole (`keep-all`), Japanese breaks between phrases (`auto-phrase`) where the browser can. A headline's text is
one `<span>` (its translation), which those rules select.

**The brand line stays English.** "One devices" (the hero's `<h1>`, the `<title>` and `og:title`, the share cards)
is the product's line, written in English on every page, as the bilingual page had it in Chinese too; it has no
`data-t` in the hero, and each language's `meta.monoid-one-devices.*` is the English on purpose. To translate the title,
change those entries; to translate the headline, give it a `data-t` and `--rekey`.

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
"how it works" (picture centred, notes around it) → feature grid with dotted rails → use-case folder tabs → a dark
"enterprise" band → get started → latest releases → download → FAQ → closing call to action → footer. The three things the page is about
each have their own section: **号池** (`#pool`), **协同** (`#teams`), **多端** (`#devices`: iPhone · iPhone Duo, Android,
desktop, web, Slack).

## Motion

- **Every device, as one scene played by scrolling** (`#devices`, on screens at least 1024 × 760 with motion allowed:
  `html.scrolly`, set in the head before the first paint). One conversation travels across the screens in six steps:
  the iPhone Duo folded, a notification landing on its cover screen; the Duo unfolding, its inner screen swinging open
  on the hinge; Android flying in, a line tying it to the same chat; the camera pulling back to the desktop window,
  the phones settling on its corners and its load bars filling; the window becoming the web app as an address bar
  slides in; Slack coming in, the band turning Ink, lines running from the thread to every screen, and each marked
  Done. The words, a `01 / 06` counter, a rail of the devices (each a link to its step) and a mono tag follow along.
  The stage is CSS `position: sticky` in a placeholder whose height is set from the first paint; the scene is built
  from a `<template>` only where it plays (phones never parse it), drawn at 900 × 720 and scaled to fit; devices move
  by transforms and opacity only. GSAP ScrollTrigger scrubs one timeline and snaps to each step without inertia, so no
  screen is skipped. Elsewhere, and if GSAP cannot load, the devices are plain tabs.
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
`assets/fonts/`, under the team's license; an installed copy is used first. Chinese, Japanese and Korean use the system's fonts (see Languages), so nothing is downloaded for them. Inter
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

- One request before the first paint once built (CSS and JS inlined): about 64 KB gzipped per language, plus Suisse Intl's Medium and
  Regular (21 KB each), preloaded; Book follows as the sheet needs it. Chinese uses the system's fonts.
- No images on the page but small SVGs; the product pictures are HTML.
- Bands below the first screen use `content-visibility: auto`.
- The hero's 168 Week draws once at once, and starts turning only after `load` and an idle moment, at most 30 frames a
  second, only while it is on screen and the tab is visible; still under `prefers-reduced-motion`.
- Lighthouse, the built page on a local server. Mobile (simulated slow 4G): Performance 97, Accessibility 100, Best
  practices 100, SEO 100; LCP 2.3 s, TBT 0–10 ms, CLS 0. Desktop: 100 / 100 / 100 / 100. Compression and cache
  lifetimes come from the host (`_headers`).

## Numbers that go stale

The release cards (`#changelog`: 0.1.7394, 0.1.7190, 0.1.7075) are written by hand from `docs/releases/`. Update it with each stable release, or have `build.mjs` read the latest release note as
`web/vite.demo.config.ts` does.
