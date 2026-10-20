///|
/// Made-up pictures (scripts/test_images.swift --gallery, which scripts/mac.sh
/// runs for APP=photos), read from where the app is started (the checkout).
let dir = "out/pictures/"

///|
/// HEIC: five big ones (6016 × 6016), twelve of 800 px at most, the JPEGs and
/// one that isn't there.
let pictures : Array[String] = [
  "big0.heic", "big1.heic", "big2.heic", "big3.heic", "big4.heic", "0.heic", "1.heic", "2.heic", "3.heic",
  "4.heic", "5.heic", "6.heic", "7.heic", "8.heic", "9.heic", "10.heic", "11.heic", "0.jpg", "5.jpg",
  "no such picture.heic",
]

///|
fn picture(i : Int) -> String {
  dir + pictures[i % pictures.length()]
}
