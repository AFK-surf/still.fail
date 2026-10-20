// mbui-render: a draw list (.dl, src/ui/drawlist.mbt) drawn by this host's renderer offscreen, into a PNG. No app, no
// window, no clock: the picture of a screen a Tester drew, as this host draws it.
//
//   MBUI_DL=<list.dl> MBUI_DL_PNG=<out.png> mbui-render
//
// Each glyph is made again by what the list says it is (its words shaped in its font, the cluster it is), each image
// decoded again from its source (or, handed over as bytes, from <list.dl>.img<N> beside it), and their instances given
// this renderer's atlas place and image id; everything else is drawn as the list has it. What this host makes of a
// glyph at another size than the list's (the glyph boxes the text was laid out by) is said: then this host's text is
// not the one the list was made by (its kept text is another's).

///|
/// The numbers of an instance (src/ui/scene.mbt).
let inst_size = 32

///|
priv struct Dl {
  mut w : Double
  mut h : Double
  mut scale : Double
  mut clear : (Double, Double, Double)
  /// glyphs, by their number: what they are (font, cluster, words)
  glyphs : Map[Int, (Double, Int, Int, Int, String)]
  /// images, by their number: px, source, bytes (-1: none); the bytes the list carries, by their number
  images : Map[Int, (Int, String, Int)]
  carried : Map[Int, String]
  inst : Array[Array[String]]
  /// the format's version (the head's): this renderer draws mbui-dl 4 (and 3, its clips round)
  mut version : Int
}

///|
fn num(s : String) -> Double {
  let j = @json.parse(s) catch { _ => return 0.0 }
  match j {
    Number(d, ..) => d
    _ => 0.0
  }
}

///|
/// The quoted words at the end of `line` (after the first `"`).
fn quoted(line : String) -> String {
  match line.find("\"") {
    Some(k) => {
      let j = @json.parse(line.view(start_offset=k).to_owned()) catch { _ => return "" }
      match j {
        String(s) => s
        _ => ""
      }
    }
    None => ""
  }
}

///|
/// Bytes from base64 (standard, padded).
fn from_base64(s : String) -> Bytes {
  let out : Array[Byte] = []
  let mut acc = 0
  let mut bits = 0
  for ch in s {
    let c = ch.to_int()
    let v = if c >= 65 && c <= 90 {
      c - 65
    } else if c >= 97 && c <= 122 {
      c - 97 + 26
    } else if c >= 48 && c <= 57 {
      c - 48 + 52
    } else if c == 43 {
      62
    } else if c == 47 {
      63
    } else {
      -1
    }
    if v < 0 {
      continue
    }
    acc = ((acc << 6) | v) & 0xFFFFFF
    bits = bits + 6
    if bits >= 8 {
      bits = bits - 8
      out.push(((acc >> bits) & 0xFF).to_byte())
    }
  }
  Bytes::from_array(out)
}

///|
fn parse(text : String) -> Dl {
  let dl = {
    w: 0.0,
    h: 0.0,
    scale: 1.0,
    clear: (1.0, 1.0, 1.0),
    glyphs: Map([]),
    images: Map([]),
    carried: Map([]),
    inst: [],
    version: 0,
  }
  for v in text.split("\n") {
    let line = v.to_owned()
    let t = line.split(" ").map(fn(x) { x.to_owned() }).to_array()
    if t.length() == 0 {
      continue
    }
    match t[0] {
      "window" if t.length() >= 4 => {
        dl.w = num(t[1])
        dl.h = num(t[2])
        dl.scale = num(t[3])
      }
      "clear" if t.length() >= 4 => dl.clear = (num(t[1]), num(t[2]), num(t[3]))
      "glyph" if t.length() >= 7 =>
        // glyph N SIZE WEIGHT STYLE CLUSTER "TEXT"
        dl.glyphs[num(t[1]).to_int()] = (
          num(t[2]),
          num(t[3]).to_int(),
          num(t[4]).to_int(),
          num(t[5]).to_int(),
          quoted(line),
        )
      "image" if t.length() >= 4 => {
        // image N PX "SOURCE" [BYTES]
        let last = t[t.length() - 1]
        let bytes = if last.has_suffix("\"") { -1 } else { num(last).to_int() }
        let src = match (line.find("\""), line.rev_find("\"")) {
          (Some(k), Some(e)) if e > k => quoted(line.view(start_offset=0, end_offset=e + 1).to_owned())
          _ => ""
        }
        dl.images[num(t[1]).to_int()] = (num(t[2]).to_int(), src, bytes)
      }
      "bytes" if t.length() >= 3 => dl.carried[num(t[1]).to_int()] = t[2]
      "mbui-dl" if t.length() >= 2 => dl.version = num(t[1]).to_int()
      // i N0 … N31 (mbui-dl 3: N0 … N27, its clip's corners round)
      "i" if t.length() == inst_size + 1 || t.length() == inst_size - 3 => dl.inst.push(t)
      _ => ()
    }
  }
  dl
}

///|
fn main {
  if !supported {
    return
  }
  // (a tool's arguments, from the process: not an app's reads of where it runs)
  let path = arg("MBUI_DL")
  let out = arg("MBUI_DL_PNG")
  if path == "" || out == "" {
    say("mbui-render: MBUI_DL=<list.dl> MBUI_DL_PNG=<out.png>")
    return
  }
  let dl = parse(read_text(path))
  if dl.version != 3 && dl.version != 4 {
    say("mbui-render: \{path}: mbui-dl \{dl.version}, not 3 or 4 (scene.mbt's instances, \{inst_size} numbers each)")
    return
  }
  if dl.w <= 0.0 || dl.inst.is_empty() {
    say("mbui-render: \{path}: no window or nothing drawn")
    return
  }
  init_offscreen(dl.w, dl.h, dl.scale)
  // each glyph made again: its atlas place here, by the list's
  let shaped = FixedArray::make(4096, 0.0)
  let g = FixedArray::make(8, 0.0)
  let places : Map[Int, (Double, Double, Double, Double)] = {}
  let mut unknown = 0
  dl.glyphs.each(fn(no, gl) {
    let (size, weight, style, cluster, text) = gl
    let key = if cluster < 0 {
      @host.text_key(text, size, weight, style)
    } else {
      let n = @host.shape(text, size, weight, style, shaped)
      if cluster < n {
        shaped[cluster * 4 + 3].to_int()
      } else {
        -1
      }
    }
    if key < 0 {
      unknown = unknown + 1
    } else {
      @host.glyph(key, g)
      places[no] = (g[0], g[1], g[2] * dl.scale, g[3] * dl.scale)
    }
  })
  // each image decoded again
  let ids : Map[Int, Int] = {}
  let info = FixedArray::make(4, 0.0)
  dl.images.each(fn(no, im) {
    let (px, src, bytes) = im
    let mine = if bytes >= 0 {
      let data = match dl.carried.get(no) {
        Some(b64) => from_base64(b64)
        None => read_bytes(path + ".img\{no}")
      }
      @host.image_load_bytes(data, px)
    } else {
      @host.image_load(src, px)
    }
    let mut tries = 0
    while @host.image_info(mine, info) == 0 && tries < 3000 {
      spin(1.0)
      tries = tries + 1
    }
    ids[no] = mine
  })
  // the instances, with this renderer's places and ids
  let n = dl.inst.length()
  let inst = FixedArray::make(n * inst_size, 0.0)
  let mut resized = 0
  for k, t in dl.inst {
    // (3's 28: how smooth its clip's corners are, 28-31, left 0: round)
    for j in 0..<(t.length() - 1) {
      inst[k * inst_size + j] = num(t[j + 1])
    }
    let kind = inst[k * inst_size + 5]
    if kind == 1.0 || kind == 3.0 || kind == 7.0 {
      match places.get(inst[k * inst_size + 12].to_int()) {
        Some((u, v, gw, gh)) => {
          if gw != inst[k * inst_size + 14] || gh != inst[k * inst_size + 15] {
            resized = resized + 1
          }
          inst[k * inst_size + 12] = u
          inst[k * inst_size + 13] = v
          inst[k * inst_size + 14] = gw
          inst[k * inst_size + 15] = gh
        }
        None => unknown = unknown + 1
      }
    } else if kind == 4.0 {
      match ids.get(inst[k * inst_size + 20].to_int()) {
        Some(mine) => inst[k * inst_size + 20] = mine.to_double()
        None => ()
      }
    }
  }
  let (r, gg, b) = dl.clear
  draw(inst, n, r, gg, b)
  if !snapshot(out) {
    say("mbui-render: \{out}: not written")
    return
  }
  say(
    "mbui-render: \{out}: \{n} instances, \{dl.glyphs.length()} glyphs (\{unknown} not known here, \{resized} another size here), \{dl.images.length()} images",
  )
}
