// What the tests of mbui/skia share: where tiny-skia's reference images are.

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
