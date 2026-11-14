// The faces in the made-up prefs (fixture.mbt), as the core sends them (client/core-ts/src/fonts.ts `shown`): each
// place's as chosen, and every face there is, by the names, sizes and kinds still.fail keeps; and the core's keeping
// of their files (font-files.ts) made up: a face's files are here once it is fetched, each the same small file
// gzipped (what the fonts page's tests unzip and check), a preview any face's. "settings-fonts-coming": 思源黑体
// chosen for the interface and its fetch under way, never done.

///|
/// A face still.fail keeps: its id, its name, whether it is for code, its files' weights (0: one variable file), how
/// big they are gzipped.
// kept across runs: a table, never written
pub let fixture_face_list : Array[(String, String, Bool, Array[Int], Double)] = [
  ("inter", "Inter", false, [0], 457818.0),
  ("noto-sans-sc", "思源黑体", false, [0], 11276563.0),
  ("noto-serif-sc", "思源宋体", false, [0], 15454579.0),
  ("lxgw-wenkai", "霞鹜文楷", false, [400, 500], 26176912.0),
  ("jetbrains-mono", "JetBrains Mono", true, [0], 90579.0),
  ("fira-code", "Fira Code", true, [0], 137151.0),
  ("maple-mono", "Maple Mono", true, [400, 600], 16790677.0),
]

///|
/// Every made-up face's file, gzipped (made by Python's gzip), and the hash of it unzipped.
// kept across runs: a value (never written)
pub let fixture_face_gz : String = "H4sIAAAAAAAC/0tUyE1MSdUtLVBIS0xOVUjLL1IoyQDReSXFCgWJ6anqxQolqcUlxQBVWnvtKQAAAA=="

///|
// kept across runs: a value (never written)
pub let fixture_face_sha : String = "ff6ddd18ae9eed8077488ece160705ef9845a5817a79a7fc85a5ffde0927fc3a"

///|
pub fn fixture_face(e : (String, String, Bool, Array[Int], Double)) -> Json {
  let (id, name, mono, weights, bytes) = e
  let base = "https://app.still.fail/releases/fonts/" + id + "/1"
  // (a whole number of bytes, as the core says a file's size)
  let each = (bytes / weights.length().to_double()).floor()
  {
    "id": ToJson::to_json(id),
    "name": ToJson::to_json(name),
    "mono": ToJson::to_json(mono),
    "family": ToJson::to_json("SF " + name),
    "preview": ToJson::to_json(base + "/preview.ttf"),
    "files": Json::array(
      weights.map(fn(w) {
        {
          "weight": ToJson::to_json(w),
          "url": ToJson::to_json(base + "/" + (if w == 0 { "var" } else { w.to_string() }) + ".ttf.gz"),
          "bytes": ToJson::to_json(each),
          "sha256": ToJson::to_json(fixture_face_sha),
        }
      }),
    ),
    "bytes": ToJson::to_json(bytes),
  }
}

///|
/// The faces as they go out (`faces`): each place's as `fonts` chose it, text as ui's where none is chosen for it.
pub fn fixture_faces(fonts : Map[String, String]) -> Json {
  let of = fn(place : String) -> Json {
    let mut found = None
    for e in fixture_face_list {
      if Some(e.0) == fonts.get(place) {
        found = Some(e)
      }
    }
    match found {
      Some(e) => fixture_face(e)
      None =>
        {
          "id": "",
          "name": "",
          "mono": ToJson::to_json(place == "code"),
          "family": "",
          "files": [],
          "bytes": 0,
        }
    }
  }
  let ui = of("ui")
  {
    "ui": ui,
    "text": if fonts.contains("text") { of("text") } else { ui },
    "code": of("code"),
    "list": Json::array(fixture_face_list.map(fixture_face)),
  }
}

///|
/// The chosen faces as kept (`fonts`).
pub fn fixture_fonts(fonts : Map[String, String]) -> Json {
  let m : Map[String, Json] = Map([])
  for k, v in fonts {
    m[k] = ToJson::to_json(v)
  }
  Json::object(m)
}

///|
/// The core's `fonts`: what is being fetched, how far; what failed; the faces whose files are kept.
pub fn fixture_fonts_topic(f : Fixture) -> Json {
  let fetching : Map[String, Json] = Map([])
  if f.mode == "settings-fonts-coming" {
    fetching["noto-sans-sc"] = ToJson::to_json(0.42)
  }
  let kept : Array[Json] = f.fonts_fetched.keys().map(fn(id) { ToJson::to_json(id) }).collect()
  // (share-card-senren-adv-coming: its picture and face partly here, its tiles' not begun)
  let share : Map[String, Json] = Map([])
  if f.mode == "share-card-senren-adv-coming" {
    share["1/a1-murasame-adv.webp"] = { "got": 82000, "bytes": 196076 }
    share["1/face-400.gz"] = { "got": 90000, "bytes": 203995 }
    share["1/face-600.gz"] = { "got": 60000, "bytes": 203267 }
  }
  { "fetching": Json::object(fetching), "failed": {}, "kept": Json::array(kept), "share": Json::object(share) }
}

///|
/// A call of the faces' files, made up, its answer to `done`: a face fetched at once (in settings-fonts-coming never:
/// under way), its unzipped file kept. False: not one of theirs.
pub fn fixture_fonts_call(f : Fixture, name : String, params : Json, done : (Result[Json, Json]) -> Unit) -> Bool {
  match name {
    "fonts.fetch" => {
      if f.mode != "settings-fonts-coming" {
        f.fonts_fetched[text(Some(params), "id")] = true
        f.changed()
        done(Ok(Json::null()))
      }
      true
    }
    "fonts.keep" => {
      done(Ok(Json::null()))
      true
    }
    _ => false
  }
}

///|
/// A face's file (gzipped once a face was fetched; not here before), or its preview.
pub fn fixture_fonts_read(f : Fixture, name : String, params? : Json = Json::null()) -> Result[(Json, Bytes), Json]? {
  let file = @codec.from_base64_exact(fixture_face_gz).unwrap()
  match name {
    "fonts.file" =>
      Some(
        if f.fonts_fetched.length() > 0 {
          Ok(({ "zipped": true }, file))
        } else {
          Err({ "code": "not_found", "message": "没有这个文件" })
        },
      )
    "fonts.preview" => Some(Ok(({}, file)))
    // a file of the looks (@sfbase.looks_file) as the made-up site has it: a look's picture a plain one of its own
    // colour, their face the one the app carries (the card's words in it as they were)
    "fonts.share" => Some(Ok(({}, fixture_looks_file(text(Some(params), "file")))))
    _ => None
  }
}

///|
/// A file of the share card's looks as the made-up site has it (fixture_fonts_read): their face's the one the app
/// carries; a picture 4 by 4 of one colour, worked out from its name.
fn fixture_looks_file(file : String) -> Bytes {
  for f in @sfbase.share_face_carried() {
    if file.has_suffix("/face-\{f.1}.gz") {
      return f.0
    }
  }
  let h = @ui.stable_hash(file).to_int()
  let px = FixedArray::make(4 * 4 * 4, b'\xFF')
  for i in 0..<16 {
    px[i * 4] = (0x40 + (h & 0x3F)).to_byte()
    px[i * 4 + 1] = (0x40 + ((h >> 6) & 0x3F)).to_byte()
    px[i * 4 + 2] = (0x40 + ((h >> 12) & 0x3F)).to_byte()
  }
  @pixels.png(4, 4, px)
}

///|
/// Where a test holds the share card's looks' files asked of the made-up core (`fonts.share`): each asked, by its name,
/// and what is told its answer, which the test gives when it will (fixture_looks_file's file, or an error); None, each
/// answered as it is asked.
// kept across runs: set by a test for what it runs, put back by it
pub let fixture_looks_held : Ref[Array[(String, (Result[(Json, Bytes), Json]) -> Unit)]?] = Ref(None)

///|
/// The file of the looks `file` as the made-up site has it (fixture_looks_file), as a held one is answered.
pub fn fixture_looks_answer(file : String) -> Result[(Json, Bytes), Json] {
  Ok(({}, fixture_looks_file(file)))
}
