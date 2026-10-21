// The platform's own text drawing (web/host.js: the canvas's fillText), as textref_native.mbt.

///|
extern "js" fn js_ref_begin(w : Double, h : Double, scale : Double, bg : Int) -> Unit =
  #|(w, h, s, bg) => globalThis.__mbhost.refBegin(w, h, s, bg)

///|
extern "js" fn js_ref_text(
  text : String,
  size : Double,
  weight : Int,
  style : Int,
  x : Double,
  base : Double,
  color : Int,
  out : FixedArray[Double],
) -> Unit =
  #|(t, s, w, st, x, b, c, o) => globalThis.__mbhost.refText(t, s, w, st, x, b, c, o)

///|
extern "js" fn js_ref_end(name : String) -> Bool =
  #|(n) => globalThis.__mbhost.refEnd(n)

///|
extern "js" fn js_ref_frame(name : String) -> Bool =
  #|(n) => globalThis.__mbhost.refFrame(n)

///|
pub fn ref_begin(w : Double, h : Double, scale : Double, bg : Int) -> Unit {
  js_ref_begin(w, h, scale, bg)
}

///|
pub fn ref_text(
  text : String,
  size : Double,
  weight : Int,
  style : Int,
  x : Double,
  base : Double,
  color : Int,
  out : FixedArray[Double],
) -> Unit {
  js_ref_text(text, size, weight, style, x, base, color, out)
}

///|
pub fn ref_end(name : String) -> Bool {
  js_ref_end(name)
}

///|
pub fn ref_frame(name : String) -> Bool {
  js_ref_frame(name)
}
