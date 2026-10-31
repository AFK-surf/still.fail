///|
// kept across runs: the same bytes once made
let inter_bytes : Ref[Bytes?] = Ref(None)

///|
/// Inter's file as the host takes it: carried in the code gzipped (inter_face.mbt), unzipped once.
fn inter_face() -> Bytes? {
  match inter_bytes.val {
    Some(b) => Some(b)
    None =>
      match @zip.gunzip(inter_gz) {
        Some(b) => {
          inter_bytes.val = Some(b)
          Some(b)
        }
        None => None
      }
  }
}
