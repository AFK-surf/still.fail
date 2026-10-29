// mbui-render: a draw list (.dl, src/ui/drawlist.mbt) drawn by this host's renderer offscreen, into a PNG. No app, no
// window, no clock: the picture of a screen a Tester drew, as this host draws it.
//
//   MBUI_DL=<list.dl> MBUI_DL_PNG=<out.png> mbui-render
//   MBUI_DL_FROM=<before.dl> MBUI_DL=<list.dl> MBUI_DL_PNG=<out.png> mbui-render
//   MBUI_DL_BENCH=<n> MBUI_DL_FROM=<before.dl> MBUI_DL=<list.dl> MBUI_DL_PNG=<out.png> mbui-render
//
// With MBUI_DL_FROM, partial redraw (docs/partial-redraw.md): the list before drawn whole, then this one only where it
// differs from it (@damage, @hostapi.render_dirty), as a window's frames are drawn, then this one again (nothing of it
// differing); the picture is what the target holds then (<out.png>), and this list drawn whole again into it
// (<out>.whole.png): the two the same to the byte.
//
// With MBUI_DL_BENCH too, the two lists drawn one after the other n times each, whole and then only where they differ,
// and the GPU's time of a frame said (the median: where the host measures it, Metal's), nothing written.
//
// Each glyph is made again by what the list says it is (its words shaped in its font, the cluster it is), each image
// decoded again from its source (or, handed over as bytes, from <list.dl>.img<N> beside it), and their instances given
// this renderer's atlas place and image id; everything else is drawn as the list has it. What this host makes of a
// glyph at another size than the list's (the glyph boxes the text was laid out by) is said: then this host's text is
// not the one the list was made by (its kept text is another's).

///|
/// The numbers of an instance (src/ui/scene.mbt).
let inst_size = 56

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
  /// the format's version (the head's): this renderer draws mbui-dl 8 (and 7, nothing fading towards a cut; 6, no outer clip; 5, a box's corners one; 4, nothing turned;
  /// 3, its clips round)
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
      // i N0 … N55 (mbui-dl 7: N0 … N51, nothing fading; 6: N0 … N39, no outer clip; 5: N0 … N35, a box's corners one; 4: N0 … N31, nothing
      // turned; 3: N0 … N27, its clip's corners round)
      "i" if t.length() == inst_size + 1 ||
        t.length() == 53 ||
        t.length() == 41 ||
        t.length() == 37 ||
        t.length() == 33 ||
        t.length() == 29 =>
        dl.inst.push(t)
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
  if !drawable(dl, path) {
    return
  }
  let from_path = arg("MBUI_DL_FROM")
  let from = if from_path == "" { None } else { Some(parse(read_text(from_path))) }
  match from {
    Some(a) if !drawable(a, from_path) => return
    Some(a) if a.w != dl.w || a.h != dl.h || a.scale != dl.scale => {
      say("mbui-render: \{from_path}: another window than \{path}'s")
      return
    }
    _ => ()
  }
  init_offscreen(dl.w, dl.h, dl.scale)
  let atlas = @hostapi.Atlas::new(@hostapi.atlas_size(false))
  let colour_atlas = @hostapi.Atlas::new(@hostapi.atlas_size(true))
  let (r, gg, b) = dl.clear
  match from {
    None => {
      let (inst, n, made) = instances(dl, path, atlas, colour_atlas)
      draw(inst, n, r, gg, b)
      if !snapshot(out) {
        say("mbui-render: \{out}: not written")
        return
      }
      // (said once the picture is written: what a driver waits for before it takes it, render_android.sh)
      say("mbui-render: \{out}: \{made}")
    }
    Some(a) => {
      // as a window's frames: the one before whole, then this one where it differs
      let (ia, na, made_a) = instances(a, from_path, atlas, colour_atlas)
      let (inst, n, made) = instances(dl, path, atlas, colour_atlas)
      say("mbui-render: \{from_path}: \{made_a}")
      say("mbui-render: \{path}: \{made}")
      let damage = @damage.Damage::new()
      let (ar, ag, ab) = a.clear
      tell_parts(damage.next(ia, na, a.w, a.h, a.scale, ar, ag, ab))
      draw(ia, na, ar, ag, ab)
      let parts = damage.next(inst, n, dl.w, dl.h, dl.scale, r, gg, b)
      say("mbui-render: \{path}: drawn again where it differs from \{from_path}: \{parts}")
      let bench = arg("MBUI_DL_BENCH")
      if bench != "" {
        let times = num(bench).to_int()
        let time = fn(partial : Bool) -> Double {
          let d = @damage.Damage::new()
          let gpus = []
          for k in 0..<(2 * times) {
            let (fi, fn_) = if k % 2 == 0 { (ia, na) } else { (inst, n) }
            let ps = d.next(fi, fn_, dl.w, dl.h, dl.scale, r, gg, b)
            if partial {
              tell_parts(ps)
            } else {
              @hostapi.render_dirty(0.0, 0.0, -1.0, -1.0)
            }
            let ms = draw_gpu(fi, fn_, r, gg, b)
            if k >= 4 {
              gpus.push(ms)
            }
          }
          gpus.sort()
          gpus[gpus.length() / 2]
        }
        let whole_ms = time(false)
        let part_ms = time(true)
        say("BENCH \{path}: GPU a frame, median: whole \{whole_ms} ms, in parts \{part_ms} ms")
        return
      }
      tell_parts(parts)
      draw(inst, n, r, gg, b)
      // and again, nothing of it differing: what a frame that draws nothing new shows (its target's, as it was)
      tell_parts(damage.next(inst, n, dl.w, dl.h, dl.scale, r, gg, b))
      draw(inst, n, r, gg, b)
      let whole = (if out.has_suffix(".png") { out.view(end_offset=out.length() - 4).to_owned() } else { out }) +
        ".whole.png"
      if !snapshot_drawn(out) {
        say("mbui-render: \{out}: not written")
        return
      }
      @hostapi.render_dirty(0.0, 0.0, -1.0, -1.0)
      draw(inst, n, r, gg, b)
      if !snapshot_drawn(whole) {
        say("mbui-render: \{whole}: not written")
        return
      }
      say("mbui-render: \{out}: drawn in parts, and whole beside it")
    }
  }
}

///|
/// The glyphs placed, by their keys (instances).
let placed : Map[Int, (Double, Double, Double, Double)] = {}

///|
/// The parts of the next frame drawn again told to the renderer (as a host's frame tells them: src/ui/hostcall.mbt).
fn tell_parts(parts : Array[(Double, Double, Double, Double)]) -> Unit {
  for p in parts {
    let (x, y, w, h) = p
    @hostapi.render_dirty(x, y, w, h)
  }
  if parts.is_empty() {
    @hostapi.render_dirty(0.0, 0.0, 0.0, 0.0)
  }
}

///|
/// Whether a list can be drawn here, said where not.
fn drawable(dl : Dl, path : String) -> Bool {
  if dl.version < 3 || dl.version > 8 {
    say("mbui-render: \{path}: mbui-dl \{dl.version}, not 3 to 8 (scene.mbt's instances, \{inst_size} numbers each)")
    return false
  }
  if dl.w <= 0.0 || dl.inst.is_empty() {
    say("mbui-render: \{path}: no window or nothing drawn")
    return false
  }
  true
}

///|
/// The list's instances with this renderer's atlas places (in `atlas`, `colour_atlas`) and image ids, how many, and
/// what was made of it to say (what it found unknown).
fn instances(dl : Dl, path : String, atlas : @hostapi.Atlas, colour_atlas : @hostapi.Atlas) -> (FixedArray[Double], Int, String) {
  // each glyph made again: its atlas place here (placed as an app places it: @hostapi.Atlas), by the list's
  let shaped = FixedArray::make(4096, 0.0)
  let g = FixedArray::make(8, 0.0)
  let places : Map[Int, (Double, Double, Double, Double)] = {}
  let mut unknown = 0
  dl.glyphs.each(fn(no, gl) {
    let (size, weight, style, cluster, text) = gl
    // (a glyph of nothing: a list a Tester drew without the host's text, none to make; not asked of the host, which
    // may not take a size of 0: Windows' fell over)
    if size <= 0.0 || text == "" {
      unknown = unknown + 1
      return
    }
    let key = if cluster < 0 {
      @hostapi.text_key(text, size, weight, style)
    } else {
      let n = @hostapi.shape(text, size, weight, style, shaped)
      if cluster < n {
        shaped[cluster * 4 + 3].to_int()
      } else {
        -1
      }
    }
    if key < 0 {
      unknown = unknown + 1
    } else {
      @hostapi.glyph(key, g)
      let (gw, gh) = (g[2] * dl.scale, g[3] * dl.scale)
      // (in colour glyphs' own atlas where the host keeps one: text.mbt atlas_for; one frame's glyphs, none let go for
      // another)
      let (a, across) = if g[6] > 0.5 && colour_atlas.sized() {
        (colour_atlas, @hostapi.colour_atlas_u)
      } else {
        (atlas, 0)
      }
      // (one place for each glyph, whichever list draws it: MBUI_DL_FROM's two the same where they are)
      match placed.get(key) {
        Some(p) => places[no] = p
        None =>
          match a.place(key, gw.round().to_int(), gh.round().to_int(), fn(_) {  }) {
            Some((_, x, y)) => {
              @hostapi.glyph_put(key, x + across, y)
              places[no] = ((x + across).to_double(), y.to_double(), gw, gh)
              placed[key] = places[no]
            }
            None => if gw > 0.0 && gh > 0.0 { unknown = unknown + 1 }
          }
      }
    }
  })
  // each image decoded again
  let ids : Map[Int, Int] = {}
  let info = FixedArray::make(4, 0.0)
  dl.images.each(fn(no, im) {
    let (px, src, bytes) = im
    let mine = if bytes >= 0 {
      let data = match dl.carried.get(no) {
        Some(b64) => @codec.from_base64(b64)
        None => read_bytes(path + ".img\{no}")
      }
      @hostapi.image_load_bytes(data, px)
    } else {
      @hostapi.image_load(src, px)
    }
    let mut tries = 0
    while @hostapi.image_info(mine, info) == 0 && tries < 3000 {
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
    // (3's 28: how smooth its clip's corners are, 28-31, left 0: round; 4's 32: not turned, 32-35 left 0; 5's 36: a
    // box's corners all its radius, 4; 6's 40: no outer clip, 40-51 left 0; 7's 52: nothing fading, 52-55 left 0)
    for j in 0..<(t.length() - 1) {
      inst[k * inst_size + j] = num(t[j + 1])
    }
    if t.length() - 1 < 40 {
      for j in 36..<40 {
        inst[k * inst_size + j] = inst[k * inst_size + 4]
      }
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
  (
    inst,
    n,
    "\{n} instances, \{dl.glyphs.length()} glyphs (\{unknown} not known here, \{resized} another size here), \{dl.images.length()} images",
  )
}
