// What the tests of mbui/skia share: its names, and where tiny-skia's reference images are.

using @skia {
  type Paint,
  type PathBuilder,
  type Path,
  type Pixmap,
  type Rect,
  type IntRect,
  type NonZeroRect,
  type Transform,
  type FillRule,
  type Stroke,
  type LineCap,
  type LineJoin,
  type StrokeDash,
  type Color,
  type ColorU8,
  type PremultipliedColorU8,
  type Point,
  type Mask,
  type MaskType,
  type BlendMode,
  type Shader,
  type LinearGradient,
  type RadialGradient,
  type SweepGradient,
  type GradientStop,
  type SpreadMode,
  type Pattern,
  type FilterQuality,
  type ColorSpace,
  type PixmapPaint,
}

///|
/// A reference image's path, relative to where the tests run (the module, or this package).
pub fn img(name : String) -> String {
  for prefix in ["src/skiatest/images/", "images/", "mbui/src/skiatest/images/"] {
    if read_file(prefix + name).length() > 0 {
      return prefix + name
    }
  }
  "src/skiatest/images/" + name
}
