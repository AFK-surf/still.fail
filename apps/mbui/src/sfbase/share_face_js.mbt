///|
/// The share card's face, each weight's file gzipped and its weight (share_face.mbt on the native hosts), as the page
/// fetched them after the app started (inter_face_js.mbt): empty until they came.
fn share_files() -> Array[(Bytes, Int)] {
  [(carried("share_400.gz"), 400), (carried("share_600.gz"), 600)]
}
