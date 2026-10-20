// mbui-render in a browser (web/render.html, driven by scripts/render_web.mjs): the drawing is web/host.js's WebGL2
// renderer (__mbhost.renderInit, present, renderPixels); the list, the arguments and where the picture goes are the
// page's globalThis.__mbrender, which the driver gives it. Without one (node: the tests) there is nothing to run.

///|
extern "js" fn js_supported() -> Bool =
  #|() => typeof globalThis.__mbrender !== "undefined" && typeof globalThis.__mbhost !== "undefined"

///|
let supported : Bool = js_supported()

///|
extern "js" fn js_arg(name : String) -> String =
  #|(n) => globalThis.__mbrender.arg(n)

///|
fn arg(name : String) -> String {
  js_arg(name)
}

///|
extern "js" fn js_init_offscreen(w : Double, h : Double, scale : Double) -> Unit =
  #|(w, h, s) => globalThis.__mbhost.renderInit(w, h, s)

///|
fn init_offscreen(w : Double, h : Double, scale : Double) -> Unit {
  js_init_offscreen(w, h, scale)
}

///|
extern "js" fn js_draw(inst : FixedArray[Double], count : Int, r : Double, g : Double, b : Double) -> Unit =
  #|(buf, n, r, g, b) => globalThis.__mbhost.present(buf, n, r, g, b)

///|
fn draw(inst : FixedArray[Double], count : Int, r : Double, g : Double, b : Double) -> Unit {
  js_draw(inst, count, r, g, b)
}

///|
extern "js" fn js_read_text(path : String) -> String =
  #|(p) => globalThis.__mbrender.readText(p)

///|
fn read_text(path : String) -> String {
  js_read_text(path)
}

///|
/// (an image's bytes beside the list: not given to a page; a list carries its own, `bytes N …`)
fn read_bytes(_path : String) -> Bytes {
  b""
}

///|
extern "js" fn js_say(s : String) -> Unit =
  #|(s) => globalThis.__mbrender.say(s)

///|
fn say(s : String) -> Unit {
  js_say(s)
}

///|
/// Nothing comes while the page's one thread is here: an image the browser decodes is told after main ends.
fn spin(_ms : Double) -> Unit {
  ()
}

///|
extern "js" fn js_snapshot(path : String) -> Bool =
  #|(p) => globalThis.__mbrender.snapshot(p)

///|
fn snapshot(path : String) -> Bool {
  js_snapshot(path)
}
