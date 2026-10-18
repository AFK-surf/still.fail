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
  logs : Array[String]
  // images: sources the test made up, with their size in pixels; loads
  // asked for (source, max_px); decodes, ready from the next frame on
  image_sizes : Map[String, (Int, Int)]
  image_loads : Array[(String, Int)]
  images : Map[Int, FakeImage]
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
fn h_font_metrics(size : Double, weight : Int, out : FixedArray[Double]) -> Unit {
  match fake.val {
    Some(_) => {
      out[0] = size * 0.8
      out[1] = size * 0.2
      out[2] = (size * 1.42).round()
    }
    None => @host.font_metrics(size, weight, out)
  }
}

///|
/// Fake shaping: one cluster per extended grapheme cluster, as real hosts
/// make them; Latin half an em wide, everything else a full em.
fn h_shape(
  text : String,
  size : Double,
  weight : Int,
  out : FixedArray[Double],
) -> Int {
  match fake.val {
    Some(_) => {
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
          size * 0.5
        } else {
          size
        }
        out[k * 4] = i.to_double()
        out[k * 4 + 1] = len.to_double()
        out[k * 4 + 2] = adv
        out[k * 4 + 3] = if c == 32 || c == 10 { -1.0 } else { c.to_double() }
        i = i + len
        k = k + 1
      }
      k
    }
    None => @host.shape(text, size, weight, out)
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
