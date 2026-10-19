// Every call to the platform goes through here, so tests can swap in a fake
// host: no window, no GPU, deterministic text metrics and a clock the test
// advances.

///|
struct FakeHost {
  mut time : Double
  mut wants : Bool
  mut wake : Double
  mut instances : Int
  mut ime_active : Bool
  mut ime_text : String
  mut ime_sel : (Int, Int)
  mut ime_rect : (Double, Double, Double, Double)
  mut clipboard : String
  // whether the app takes back (a page to go back to), as last told
  mut back_on : Bool
  // the system it plays (as @host.platform: 0 macOS, 1 iOS, 2 Android)
  platform : Int
  // the system asks for less transparency (glass drawn solid)
  mut reduce_transparency : Bool
  logs : Array[String]
  // images: sources the test made up, with their size in pixels; loads
  // asked for (source, max_px); decodes, ready from the next frame on
  image_sizes : Map[String, (Int, Int)]
  image_loads : Array[(String, Int)]
  images : Map[Int, FakeImage]
  // what bold adds to a cluster's advance, in ems (0 by default: weight
  // changes nothing)
  mut bold : Double
}

///|
priv struct FakeImage {
  mut state : Int
  w : Double
  h : Double
  ow : Double
  oh : Double
}

///|
fn fake_image(f : FakeHost, ow : Int, oh : Int, max_px : Int) -> Int {
  let k = if ow > oh { max_px.to_double() / ow.to_double() } else { max_px.to_double() / oh.to_double() }
  let k = if k > 1.0 { 1.0 } else { k }
  let id = f.images.length() + 1
  // the decode will be done by the next frame, which it asks for
  f.wants = true
  f.images[id] = {
    state: if ow > 0 { 0 } else { -1 },
    w: (ow.to_double() * k).round(),
    h: (oh.to_double() * k).round(),
    ow: ow.to_double(),
    oh: oh.to_double(),
  }
  id
}

///|
let fake : Ref[FakeHost?] = { val: None }

///|
fn h_now() -> Double {
  match fake.val {
    Some(f) => f.time
    None => @host.now()
  }
}

///|
/// When the input event being handled happened (the host's, else now).
fn h_event_time() -> Double {
  match fake.val {
    Some(f) => f.time
    None => {
      let t = @host.event_time()
      if t >= 0.0 {
        t
      } else {
        @host.now()
      }
    }
  }
}

///|
fn h_platform() -> Int {
  match fake.val {
    Some(f) => f.platform
    None => {
      if host_platform.val < 0 {
        host_platform.val = @host.platform()
      }
      host_platform.val
    }
  }
}

///|
/// The host's system, asked once.
let host_platform : Ref[Int] = { val: -1 }

///|
fn h_request_frame() -> Unit {
  match fake.val {
    Some(f) => f.wants = true
    None => @host.request_frame()
  }
}

///|
fn h_wake_after(ms : Double) -> Unit {
  match fake.val {
    Some(f) =>
      if f.wake < 0.0 || f.time + ms < f.wake {
        f.wake = f.time + ms
      }
    None => @host.wake_after(ms)
  }
}

///|
fn h_font_metrics(
  size : Double,
  weight : Int,
  style : Int,
  out : FixedArray[Double],
) -> Unit {
  match fake.val {
    Some(_) => {
      out[0] = size * 0.8
      out[1] = size * 0.2
      out[2] = (size * 1.42).round()
    }
    None => @host.font_metrics(size, weight, style, out)
  }
}

///|
/// Fake shaping: one cluster per extended grapheme cluster, as real hosts
/// make them; Latin half an em wide (0.6 in the code face), everything else
/// a full em.
fn h_shape(
  text : String,
  size : Double,
  weight : Int,
  style : Int,
  out : FixedArray[Double],
) -> Int {
  match fake.val {
    Some(f) => {
      let n = text.length()
      let cap = out.length() / 4
      let mut i = 0
      let mut k = 0
      while i < n && k < cap {
        let c = text.at(i).to_int()
        let len = @text.next_grapheme(text, i) - i
        let adv = if c == 10 {
          0.0
        } else if c < 0x2E80 {
          if (style & @host.style_mono) != 0 {
            size * 0.6
          } else {
            size * 0.5
          }
        } else {
          size
        }
        let adv = if weight >= 600 && c != 10 { adv + size * f.bold } else { adv }
        out[k * 4] = i.to_double()
        out[k * 4 + 1] = len.to_double()
        out[k * 4 + 2] = adv
        // U+E000 plays a ligature's second letter: drawn as part of the cluster before it
        out[k * 4 + 3] = if c == 32 || c == 10 {
          -1.0
        } else if c == 0xE000 && k > 0 {
          -2.0
        } else {
          c.to_double()
        }
        i = i + len
        k = k + 1
      }
      k
    }
    None => @host.shape(text, size, weight, style, out)
  }
}

///|
/// The key of `text` drawn as one piece (a word of a joining script).
fn h_text_key(text : String, size : Double, weight : Int, style : Int) -> Int {
  match fake.val {
    Some(_) => text.at(0).to_int()
    None => @host.text_key(text, size, weight, style)
  }
}

///|
fn h_glyph(key : Int, out : FixedArray[Double]) -> Unit {
  match fake.val {
    Some(_) => {
      // a glyph box per cluster, so painting is exercised
      out[0] = 0.0
      out[1] = 0.0
      out[2] = 6.0
      out[3] = 10.0
      out[4] = 0.0
      out[5] = -10.0
      out[6] = if key >= 0x1F000 { 1.0 } else { 0.0 }
    }
    None => @host.glyph(key, out)
  }
}

///|
fn h_atlas_generation() -> Int {
  match fake.val {
    Some(_) => 0
    None => @host.atlas_generation()
  }
}

///|
fn h_present(buf : FixedArray[Double], count : Int) -> Unit {
  match fake.val {
    Some(f) => f.instances = count
    None => @host.present(buf, count, 0.961, 0.961, 0.969)
  }
}

///|
fn h_reduce_transparency() -> Bool {
  match fake.val {
    Some(f) => f.reduce_transparency
    None => @host.reduce_transparency() || @host.env("MBUI_GLASS") == "solid"
  }
}

///|
fn h_gpu_ms() -> Double {
  match fake.val {
    Some(_) => -1.0
    None => @host.gpu_ms()
  }
}

///|
fn h_set_ime(
  active : Bool,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  text : String,
  a : Int,
  b : Int,
) -> Unit {
  match fake.val {
    Some(f) => {
      f.ime_active = active
      f.ime_text = text
      f.ime_sel = (a, b)
      f.ime_rect = (x, y, w, h)
    }
    None => @host.set_ime(active, x, y, w, h, text, a, b)
  }
}

///|
fn h_clipboard_set(s : String) -> Unit {
  match fake.val {
    Some(f) => f.clipboard = s
    None => @host.clipboard_set(s)
  }
}

///|
fn h_back_enabled(on : Bool) -> Unit {
  match fake.val {
    Some(f) => f.back_on = on
    None => @host.back_enabled(on)
  }
}

///|
fn h_log(s : String) -> Unit {
  match fake.val {
    Some(f) => f.logs.push(s)
    None => @host.log(s)
  }
}

///|
fn h_image_load(src : String, max_px : Int) -> Int {
  match fake.val {
    Some(f) => {
      f.image_loads.push((src, max_px))
      let (w, h) = f.image_sizes.get(src).unwrap_or((0, 0))
      fake_image(f, w, h, max_px)
    }
    None => @host.image_load(src, max_px)
  }
}

///|
fn h_image_load_bytes(data : Bytes, max_px : Int) -> Int {
  match fake.val {
    Some(f) => {
      f.image_loads.push(("bytes:\{data.length()}", max_px))
      fake_image(f, 400, 300, max_px)
    }
    None => @host.image_load_bytes(data, max_px)
  }
}

///|
fn h_image_info(id : Int, out : FixedArray[Double]) -> Int {
  match fake.val {
    Some(f) =>
      match f.images.get(id) {
        Some(im) => {
          if im.state == 1 {
            out[0] = im.w
            out[1] = im.h
            out[2] = im.ow
            out[3] = im.oh
          }
          im.state
        }
        None => -1
      }
    None => @host.image_info(id, out)
  }
}

///|
fn h_image_free(id : Int) -> Unit {
  match fake.val {
    Some(f) => f.images.remove(id)
    None => @host.image_free(id)
  }
}
