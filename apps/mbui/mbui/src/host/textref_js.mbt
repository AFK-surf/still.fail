// The platform's own text drawing (web/host.js: the canvas's fillText), as textref_native.mbt.

///|
extern "js" fn ref_begin(w : Double, h : Double, scale : Double, bg : Int) -> Unit =
  #|(w, h, s, bg) => globalThis.__mbhost.refBegin(w, h, s, bg)

///|
extern "js" fn ref_text(
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
extern "js" fn ref_end(name : String) -> Bool =
  #|(n) => globalThis.__mbhost.refEnd(n)

///|
extern "js" fn ref_frame(name : String) -> Bool =
  #|(n) => globalThis.__mbhost.refFrame(n)
