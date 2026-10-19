///|
/// On Windows (scripts/win.sh swaps this in for pictures_native.mbt):
/// test/images, read from where the app is started (the checkout; CI adds a
/// big.jpg there), one over http (windows.yml serves test/images on 5590), and
/// one that isn't there.
let pictures : Array[String] = [
  "test/images/exif1.jpg", "test/images/exif3.jpg", "test/images/exif6.jpg",
  "test/images/exif8.jpg", "test/images/exif5.jpg", "test/images/exif7.jpg", "test/images/big.jpg",
  "test/images/scene0.jpg", "test/images/scene1.jpg", "http://127.0.0.1:5590/scene1.jpg",
  "test/images/no such picture.jpg",
]

///|
fn picture(i : Int) -> String {
  pictures[i % pictures.length()]
}
