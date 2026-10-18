///|
let dir = "/System/Library/Desktop Pictures/"

///|
/// HEIC: five 25 MB ones (6016 × 6016), small thumbnails, and one that
/// isn't there.
let pictures : Array[String] = [
  "iMac Blue.heic", "iMac Purple.heic", "iMac Pink.heic", "iMac Orange.heic", "iMac Green.heic",
  ".thumbnails/Valley Light.heic", ".thumbnails/Iridescence Light.heic", ".thumbnails/Tree.heic",
  ".thumbnails/The Beach.heic", ".thumbnails/Iridescence.heic", ".thumbnails/Catalina Sunset.heic",
  ".thumbnails/Catalina Coast.heic", ".thumbnails/The Cliffs.heic", ".thumbnails/The Desert.heic",
  ".thumbnails/Dome Light.heic", ".thumbnails/Grid Green.heic", ".thumbnails/Motion Blue Dark.heic",
  "no such picture.heic",
]

///|
fn picture(i : Int) -> String {
  dir + pictures[i % pictures.length()]
}
