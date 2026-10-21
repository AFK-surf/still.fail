///|
/// On Android (scripts/android.sh swaps this in for pictures_native.mbt):
/// what it copies into the app's files (test/images, and the made-up pictures
/// of scripts/test_images.swift --gallery: twelve JPEGs and a 6016 × 6016 HEIC
/// and JPEG), one it serves over
/// http from the host machine (10.0.2.2 in the emulator), and one that isn't
/// there.
let dir = "/data/data/dev.mbui.demo/files/photos/"

///|
let pictures : Array[String] = [
  dir + "exif1.jpg", dir + "exif3.jpg", dir + "exif6.jpg", dir + "exif8.jpg", dir + "exif5.jpg",
  dir + "exif7.jpg", dir + "big.heic", dir + "big.jpg", dir + "scene0.jpg", dir + "scene1.jpg",
  "http://10.0.2.2:5590/scene1.jpg", dir + "0.jpg", dir + "1.jpg", dir + "2.jpg", dir + "3.jpg",
  dir + "4.jpg", dir + "5.jpg", dir + "6.jpg", dir + "7.jpg", dir + "8.jpg", dir + "9.jpg",
  dir + "10.jpg", dir + "11.jpg", dir + "no such picture.jpg",
]

///|
fn picture(i : Int) -> String {
  pictures[i % pictures.length()]
}
