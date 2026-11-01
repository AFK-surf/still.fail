# Share graphics drawn by mbui

`mbui/figure` and `mbui/film.picture` make a still image from a normal mbui view. Panels, capsules, clipping, text,
flex layout, and any real app component go through the same renderer as the app. There is no browser's rounded
rectangle and no video compression. The output is a PNG, drawn offscreen, without opening a window.

On macOS, from `apps/mbui`:

```sh
bash scripts/figure.sh wrap out/wrap.png
bash scripts/figure.sh align out/alignment.png
bash scripts/figure.sh wrap-normal out/wrap-normal.png
bash scripts/figure.sh wrap-reverse out/wrap-reverse.png
bash scripts/figure.sh align-edge out/align-edge.png
bash scripts/figure.sh align-text out/align-text.png
# Optional: use another font for the view's UI face.
bash scripts/figure.sh wrap out/wrap-inter.png /absolute/path/to/InterVariable.ttf
```

The `wrap` example is 960 × 540 logical points at 2.5×, producing 2400 × 1350 pixels. It draws the sign-in card's real
components three times, with the same content and the same size: once wide, then at the same narrow width with normal
and reverse wrapping. Only the normal example changes the foot's layout direction. The example shortens the button
labels for the graphic. `align` compares the button edge with its label on the same card. `wrap-normal`,
`wrap-reverse`, `align-edge`, and `align-text` each draw one of the same cards on a neutral canvas, without headings
or annotations. These single-card figures are 480 × 270 logical points at 5×, also 2400 × 1350 pixels. The input and output paths
are relative to `apps/mbui` unless absolute. A supplied font that cannot be read,
an undecodable or pending image, unsupported host, invalid dimensions, or an unwritable output makes the command fail.
The script writes a temporary file alongside the destination and replaces it only after a successful render.

## Make another graphic

Add a view function in `src/sfgraphic` and give it a name in `src/sffigure/main.mbt`. `@figure.canvas`,
`@figure.panel`, `@figure.auto_panel`, and `@figure.words` provide a canvas and relative placements; inside them, use ordinary
`@ui` views, shapes, lines, pictures, or the app's components. Pass that view and its logical size to
`@film.picture` and select its pixel scale there. Extend the command's name check for the new view. A graphic can
therefore use the actual component being explained instead of an independent approximation of it.

The exporter draws the view's first frame. The tester resets framework state before that frame, so initialize any
theme or font the view needs on its first call, as the example does. Use `mbui/film` for a later frame or animation.

`@film.picture` currently uses the Mac offscreen host, like `mbui/film`; it does not open a window. It rejects a frame
whose images or native views are still pending, whose images failed, or that contains a native web or video view,
rather than silently writing an incomplete graphic: those views are not drawn by the offscreen host. The theme's
corner rule and word overlap are checked by default. The `align` picture deliberately shows one misaligned corner;
its `corner_faults_ok` accepts exactly that fault, so another bad corner still fails the export. A drawing with an
entirely different, intentional rule can pass `corners_held=false` or `words_over_held=false`. The examples use the app's bundled Inter face by default; the optional font overrides it for
that invocation. Streamed video frames cannot be captured by this exporter. Graphic content and labels belong to the
view, not to the renderer.
