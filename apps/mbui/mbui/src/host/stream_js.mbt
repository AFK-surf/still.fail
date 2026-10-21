// Streams (stream.mbt) in the browser: web/host.js's stream*. Without a host (the tests, run in node) none opens.

///|
extern "js" fn st_open() -> Int =
  #|() => (globalThis.__mbhost && globalThis.__mbhost.streamOpen) ? globalThis.__mbhost.streamOpen() : 0

///|
extern "js" fn st_h264(id : Int, avcc : Bytes, w : Int, h : Int) -> Unit =
  #|(i, a, w, h) => globalThis.__mbhost.streamH264(i, a, w, h)

///|
extern "js" fn st_frame(id : Int, data : Bytes, key : Int, ts : Double) -> Unit =
  #|(i, d, k, t) => globalThis.__mbhost.streamFrame(i, d, k, t)

///|
extern "js" fn st_jpeg(id : Int, data : Bytes, ts : Double) -> Unit =
  #|(i, d, t) => globalThis.__mbhost.streamJpeg(i, d, t)

///|
extern "js" fn st_next(id : Int) -> String =
  #|(i) => globalThis.__mbhost.streamNext(i)

///|
extern "js" fn st_show(id : Int, ts : Double) -> Unit =
  #|(i, t) => globalThis.__mbhost.streamShow(i, t)

///|
extern "js" fn st_close(id : Int) -> Unit =
  #|(i) => globalThis.__mbhost.streamClose(i)

///|
extern "js" fn st_h264_here() -> Int =
  #|() => (globalThis.__mbhost && globalThis.__mbhost.h264Here) ? globalThis.__mbhost.h264Here() : 0
