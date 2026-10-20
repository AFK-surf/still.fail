// device.mbt's calls in a browser (web/host.js's "device" part); a page without them (a test's) answers none.

///|
extern "js" fn cl_read() -> Int =
  #|() => (globalThis.__mbhost && globalThis.__mbhost.clipRead ? globalThis.__mbhost.clipRead() : 0)

///|
extern "js" fn cl_state(id : Int) -> Int =
  #|(id) => globalThis.__mbhost.clipState(id)

///|
extern "js" fn cl_picture(id : Int) -> Int =
  #|(id) => globalThis.__mbhost.clipPicture(id)

///|
extern "js" fn cl_text(id : Int) -> String =
  #|(id) => globalThis.__mbhost.clipText(id)

///|
extern "js" fn cl_png(id : Int) -> Bytes =
  #|(id) => globalThis.__mbhost.clipPng(id)

///|
extern "js" fn cl_end(id : Int) -> Unit =
  #|(id) => globalThis.__mbhost.clipEnd(id)

///|
extern "js" fn cl_set(text : String, png : Bytes, label : String) -> Unit =
  #|(t, p, l) => globalThis.__mbhost && globalThis.__mbhost.clipSet && globalThis.__mbhost.clipSet(t, p, l)

///|
extern "js" fn js_copy_shown() -> Bool =
  #|() => false

///|
fn dv_copy_shown() -> Int {
  if js_copy_shown() {
    1
  } else {
    0
  }
}

///|
extern "js" fn dv_key_catch(on : Int) -> Unit =
  #|(on) => globalThis.__mbhost && globalThis.__mbhost.keyCatch && globalThis.__mbhost.keyCatch(on)

///|
extern "js" fn dv_ime_inset() -> Double =
  #|() => (globalThis.__mbhost && globalThis.__mbhost.imeInset ? globalThis.__mbhost.imeInset() : 0)

///|
extern "js" fn dv_keep_awake(on : Int) -> Unit =
  #|(on) => globalThis.__mbhost && globalThis.__mbhost.keepAwake && globalThis.__mbhost.keepAwake(on)

///|
extern "js" fn dv_haptic(kind : Int) -> Unit =
  #|(k) => globalThis.__mbhost && globalThis.__mbhost.haptic && globalThis.__mbhost.haptic(k)
