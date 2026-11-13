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

///|
extern "js" fn st_feeds() -> Int =
  #|() => (globalThis.__mbhost && globalThis.__mbhost.streamFeeds) ? globalThis.__mbhost.streamFeeds() : 0

///|
extern "js" fn st_codec(id : Int, cmd : String, data : Bytes) -> Unit =
  #|(i, c, d) => { if (globalThis.__mbhost && globalThis.__mbhost.streamCodec) globalThis.__mbhost.streamCodec(i, c, d) }

///|
fn st_audio_here() -> Int { 0 }

///|
fn st_h265_here() -> Int { 0 }

///|
fn st_hevc(_id : Int, _hvcc : Bytes, _w : Int, _h : Int) -> Unit { () }

///|
fn st_audio(_id : Int, _data : Bytes) -> Unit { () }

///|
fn st_layers() -> Int { 0 }

///|
fn st_pointer(_id : Int, _png : Bytes, _w : Double, _h : Double, _hx : Double, _hy : Double) -> Unit { () }

///|
fn st_pointer_at(_id : Int, _x : Double, _y : Double, _shown : Int) -> Unit { () }

///|
fn st_direct(_id : Int, _route : Double, _after : Double, _what : Int) -> Unit { () }

///|
/// (the browser's host has nothing for a frame decoded unseen: taken as any, below)
fn st_frame_shown(id : Int, data : Bytes, key : Int, ts : Double, show : Int) -> Int {
  // (no frame decoded unseen here: decoded and shown as any, its "f" taken as "d" by @ui.Stream)
  ignore(show)
  st_frame(id, data, key, ts)
  1
}

///|
fn st_flush(_id : Int, _drain : Int) -> Unit { () }

///|
fn st_audio_played(_id : Int) -> Double { 0.0 }

///|
fn st_audio_queued(_id : Int) -> Double { 0.0 }

///|
fn st_audio_volume(_id : Int, _v : Double) -> Unit { () }
