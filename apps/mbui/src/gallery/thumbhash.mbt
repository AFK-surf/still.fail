// ThumbHash pictures (mbui's @pixels.thumbhash: a photo's look in some 25 bytes) made once each and kept as images,
// shown while the photo itself comes.

///|
let hashed : Map[String, Bool] = {}

///|
/// Every Tester starts as the app does (mbui's on_reset): the pictures made here gone with its images, none open.
fn init {
  @ui.on_reset(fn() {
    hashed.clear()
    state.open = None
    state.bars = true
  })
}

///|
/// The image key of a hash's picture (base64), made the first time.
pub fn thumbhash_image(hash : String) -> String? {
  if hash == "" {
    return None
  }
  let key = "mem:thumbhash/" + hash
  let ok = match hashed.get(key) {
    Some(ok) => ok
    None => {
      let ok = match @pixels.thumbhash(@codec.from_base64(hash)) {
        Some((w, h, rgba)) => {
          @ui.add_image(key, @pixels.png(w, h, rgba))
          true
        }
        None => false
      }
      hashed[key] = ok
      ok
    }
  }
  if ok {
    Some(key)
  } else {
    None
  }
}
