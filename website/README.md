# The official site

## Run and build

```sh
python3 -m http.server -d website 4173      # or any static server: the folder works unbuilt, in English
node website/build.mjs                      # → dist/website: a page per language + assets + sitemap.xml, robots.txt, _headers
node website/build.mjs --site still.fail --out dist/site   # still.fail's (pnpm build:site; youdid.wtf: build:site-beta)
node website/og.mjs [site…]                 # the share cards again (Chrome, playwright-core)
node website/build.mjs --check              # translations: missing, extra, stale, markup, glyphs (exit 1 on any)
```

## Changing the copy

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

## Adding a language

Add it to `i18n/locales.json`, add `i18n/<code>.json` (start from `{}`; the page falls back to English, with a warning,
and `--strict` fails instead), give it a font stack in `css/00-base.css` if its script needs one, and fill it from
`--extract`. `--check <code>` reports missing and extra keys, markup that differs from the English, and characters
outside Suisse Intl's `unicode-range` that are not CJK, kana, Hangul or full-width (which the system's fonts draw).

## The changelog

The Changelog section names the newest stable release: the build puts its version, date and counts (and, on the
Chinese page, its first three lines) from `docs/releases/0.1.<n>.md` over the template's (`latestRelease`,
`withRelease` in build.mjs), reading origin/main's notes too, since a release's notes land on main after its commit.
Only a stable release deploys monoid.build, so it changes with each one.
