# Media components

`mbui/media` supplies parts that can be composed in an mbui picture or a filmed view. A component's dimensions are
layout points. The output renderer's scale is pixels per point; changing it changes sharpness, not the page's layout.

## Frames

```moonbit
let look = @media.FrameStyle::{
  fill: 0xFFFFFFFFL,
  edge: 0xD9D9D9FFL,
  edge_width: 1.0,
  radius: 24.0,
  inset: 16.0,
}
@media.frame(c, 360.0, 240.0, look, fn() {
  // Any mbui content.
})
|> ignore
```

The content is clipped to the rounded frame. mbui draws its edge over the content, so a picture filling the frame
cannot cover the edge.

## Device screens

```moonbit
@media.device(c, @media.Device::IPhone11Pro, "out/phone.png", 320.0) |> ignore
```

The built-in front-on frames are `IPhone11Pro`, `IPadPro11` and `MacBookPro16`.
`Device::geometry()` describes each original artwork's screen rectangle, so a capture can be made at the correct
aspect ratio. The picture is contained at that ratio, with black around any remainder; it is never stretched or
cropped. The frame covers the rounded screen edge and the iPhone's notch. The picture itself supplies any status bar,
keyboard or window controls: these components do not fabricate system UI.

`Device::screen()` gives the logical screen size, the artwork's pixels per point, platform and example portrait
insets for an edge-to-edge scene. Tell the scene those bars before drawing it (a drive can use `system {"bars":…}`)
so the app's own layout keeps its controls clear of a notch. Safe areas change with orientation and system UI; use the
real host's values when available. The bars reserve room; use a real system capture when the system's contents must
be visible. The iPad model is the 11-inch Pro's first through fourth generations; the sizes follow
[Apple's screen specifications](https://developer.apple.com/design/human-interface-guidelines/layout).

For a live application, render each screen at its own logical window size and its own output scale first. Compose the
resulting pictures at the desired size; merely shrinking a large screen inside a phone frame does not produce the
small-screen arrangement. Images must be available and decoded for the frame being exported.

The device artwork and its SVG renderer are embedded, so it does not depend on an asset directory or on the app's
own SVG renderer at runtime. Source and licensing of the hardware art are recorded in
`src/media/devices/README.md`.

In the still.fail workspace, `bash scripts/media-sample.sh` renders the actual app at three screen sizes and draws a
catalogue at `out/media-sample/catalogue.png`.
