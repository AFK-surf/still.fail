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
/// Fake shaping: one cluster per code point (a surrogate pair is one), Latin
/// half an em wide, everything else a full em.
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
        let len = if is_hi(c) && i + 1 < n { 2 } else { 1 }
        let adv = if c == 10 {
          0.0
        } else if c < 0x2E80 && len == 1 {
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
