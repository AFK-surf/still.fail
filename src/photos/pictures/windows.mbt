///|
/// On Windows (scripts/win.sh swaps this in for pictures_native.mbt):
/// test/images, read from where the app is started (the checkout; CI adds a
/// big.jpg there), one over https, and one that isn't there.
let pictures : Array[String] = [
  "test/images/exif1.jpg", "test/images/exif3.jpg", "test/images/exif6.jpg",
  "test/images/exif8.jpg", "test/images/exif5.jpg", "test/images/exif7.jpg", "test/images/big.jpg",
  "test/images/photo0.jpg", "test/images/photo1.jpg", "https://github.com/zzj3720.png?size=400",
  "test/images/no such picture.jpg",
]

///|
fn picture(i : Int) -> String {
  pictures[i % pictures.length()]
}
