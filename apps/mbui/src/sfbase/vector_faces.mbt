// The text of SVG pictures (mbui/svg draws them, the app's main gives @ui its drawing): set in the faces the app
// carries (Inter, its code face) and Chinese and Japanese in 思源黑体 (Noto Sans SC), a face still.fail keeps, had from
// the core as a place's face is (faces.mbt) the first time a picture has such text, the pictures drawn again once it is
// here.

///|
/// Where the face for Chinese and Japanese in pictures is.
priv enum VectorCjk {
  CjkUnwanted
  CjkWanted
  CjkComing
  CjkHere(Array[Bytes])
  CjkNotHad
}

///|
/// (a signal: the frame that reads it, `faces`, comes again as a picture wants the face)
let vector_cjk : @signals.Signal[VectorCjk] = @signals.signal(CjkUnwanted)

///|
/// The face Chinese and Japanese in pictures are set in.
let vector_cjk_face : String = "noto-sans-sc"

///|
/// The faces the text of SVG picture `data` is set in: the app's own words' (Inter) first, its code face, and 思源黑体
/// once here (asked for the first time a picture has Chinese or Japanese).
pub fn vector_faces(data : Bytes) -> Array[Bytes] {
  let faces = []
  match inter_face() {
    Some(b) => faces.push(b)
    None => ()
  }
  let code = @sf.code_face()
  if code.length() > 0 {
    faces.push(code)
  }
  match @signals.untracked(fn() { vector_cjk.get() }) {
    CjkHere(b) => faces.append(b)
    CjkUnwanted => if has_cjk(data) { vector_cjk.set(CjkWanted) }
    _ => ()
  }
  faces
}

///|
/// 思源黑体 had from the core where a picture wants it (call each frame, with the prefs: its files are the list's), the
/// pictures drawn again once it is here.
fn vector_cjk_had(src : Source, prefs : Json?) -> Unit {
  guard vector_cjk.get() is CjkWanted else { return }
  let list = items(field(prefs, "faces"), "list")
  guard list.search_by(fn(f) { text(Some(f), "id") == vector_cjk_face }) is Some(i) else {
    vector_cjk.set(CjkNotHad)
    return
  }
  vector_cjk.set(CjkComing)
  face_files(src, vector_cjk_face, items(Some(list[i]), "files"), 0, [], false, fn(h) {
    match h {
      Whole(got) => {
        let bytes = []
        for f in got {
          if f.0 is Held(b) {
            bytes.push(b)
          }
        }
        vector_cjk.set(CjkHere(bytes))
        @ui.redraw_vector_pictures()
      }
      NotHad(_) => vector_cjk.set(CjkNotHad)
      _ => ()
    }
  })
}

///|
/// Whether UTF-8 `data` has a character of Chinese or Japanese writing (CJK's symbols and punctuation, kana, the
/// ideographs and their compatibility forms, the full-width forms).
fn has_cjk(data : Bytes) -> Bool {
  let n = data.length()
  let mut i = 0
  while i < n {
    let b = data[i].to_int()
    if b < 0xE0 {
      i += 1
      continue
    }
    let c = if b < 0xF0 && i + 2 < n {
      ((b & 0x0F) << 12) | ((data[i + 1].to_int() & 0x3F) << 6) | (data[i + 2].to_int() & 0x3F)
    } else if b < 0xF8 && i + 3 < n {
      ((b & 0x07) << 18) |
      ((data[i + 1].to_int() & 0x3F) << 12) |
      ((data[i + 2].to_int() & 0x3F) << 6) |
      (data[i + 3].to_int() & 0x3F)
    } else {
      0
    }
    if (c >= 0x2E80 && c <= 0x9FFF) ||
      (c >= 0xF900 && c <= 0xFAFF) ||
      (c >= 0xFE30 && c <= 0xFE4F) ||
      (c >= 0xFF00 && c <= 0xFFEF) ||
      (c >= 0x20000 && c <= 0x3FFFF) {
      return true
    }
    i += if b < 0xF0 { 3 } else { 4 }
  }
  false
}
