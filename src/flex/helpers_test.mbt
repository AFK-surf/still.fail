///|
/// Compares a node's rounded layout with Yoga's expectation.
fn check(
  name : String,
  n : @flex.Node,
  left : Double,
  top : Double,
  width : Double,
  height : Double,
) -> Unit raise {
  if n.left != left || n.top != top || n.width != width || n.height != height {
    fail(
      "\{name}: got \{n.left},\{n.top} \{n.width}x\{n.height}, want \{left},\{top} \{width}x\{height}",
    )
  }
}

///|
/// Yoga's intrinsicSizeMeasureFunc (javascript/tests/tools/utils.ts): text
/// whose characters are 10 × 10, wrapping at spaces.
fn text_measure(text : String, row~ : Bool) -> @flex.MeasureFn {
  fn(width, wm, height, hm) {
    let len = text.length().to_double()
    let words = text.split(" ").map(fn(w) { w.length().to_double() }).collect()
    let measured_w = match wm {
      Exactly => width
      AtMost => if width < len * 10.0 { width } else { len * 10.0 }
      Undefined => len * 10.0
    }
    let calc_height = fn() {
      if len * 10.0 <= measured_w {
        return 10.0
      }
      let mut longest = 0.0
      for w in words {
        if w > longest {
          longest = w
        }
      }
      let max_line = if !row {
        measured_w
      } else if longest * 10.0 > measured_w {
        longest * 10.0
      } else {
        measured_w
      }
      let mut lines = 1
      let mut cur = 0.0
      for w in words {
        let ww = w * 10.0
        if ww > max_line {
          if cur > 0.0 {
            lines = lines + 1
          }
          lines = lines + 1
          cur = 0.0
        } else if cur + ww <= max_line {
          cur = cur + 10.0 + ww
        } else {
          lines = lines + 1
          cur = 10.0 + ww
        }
      }
      (if cur == 0.0 { lines - 1 } else { lines }).to_double() * 10.0
    }
    let measured_h = match hm {
      Exactly => height
      AtMost => {
        let c = calc_height()
        if height < c {
          height
        } else {
          c
        }
      }
      Undefined => calc_height()
    }
    (measured_w, measured_h)
  }
}
