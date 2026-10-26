// The native side: Metal offscreen (src/host/apple_render.m) and the system's few needs (render_stub.c).

///|
extern "C" fn ffi_init_offscreen(w : Double, h : Double, scale : Double) -> Unit = "mb_render_init_offscreen"

///|
#borrow(inst, out)
extern "C" fn ffi_draw_timed(
  inst : FixedArray[Double],
  count : Int,
  r : Double,
  g : Double,
  b : Double,
  out : FixedArray[Double],
) -> Unit = "mb_render_draw_timed"

///|
#borrow(path)
extern "C" fn ffi_read_text(path : String) -> String = "mbr_read_text"

///|
#borrow(path)
extern "C" fn ffi_read_bytes(path : String) -> Bytes = "mbr_read_bytes"

///|
#borrow(s)
extern "C" fn ffi_say(s : String) -> Unit = "mbr_say"

///|
extern "C" fn ffi_spin(ms : Double) -> Unit = "mbr_spin"

///|
#borrow(path)
extern "C" fn ffi_snapshot(path : String) -> Int = "mbr_snapshot"

///|
#borrow(name)
extern "C" fn ffi_arg(name : String) -> String = "mbr_arg"

///|
let supported = true

///|
fn arg(name : String) -> String {
  ffi_arg(name)
}

///|
fn init_offscreen(w : Double, h : Double, scale : Double) -> Unit {
  ffi_init_offscreen(w, h, scale)
}

///|
fn draw(inst : FixedArray[Double], count : Int, r : Double, g : Double, b : Double) -> Unit {
  let out = FixedArray::make(2, 0.0)
  ffi_draw_timed(inst, count, r, g, b, out)
}

///|
fn read_text(path : String) -> String {
  ffi_read_text(path)
}

///|
fn read_bytes(path : String) -> Bytes {
  ffi_read_bytes(path)
}

///|
fn say(s : String) -> Unit {
  ffi_say(s)
}

///|
fn spin(ms : Double) -> Unit {
  ffi_spin(ms)
}

///|
fn snapshot(path : String) -> Bool {
  ffi_snapshot(path) != 0
}

///|
#borrow(path)
extern "C" fn ffi_snapshot_drawn(path : String) -> Int = "mbr_snapshot_drawn"

///|
/// The target as the frames drawn into it left it, as a PNG at `path` (not the last frame drawn again).
fn snapshot_drawn(path : String) -> Bool {
  ffi_snapshot_drawn(path) != 0
}

///|
/// A frame drawn and its GPU's time (ms; -1 where not measured).
fn draw_gpu(inst : FixedArray[Double], count : Int, r : Double, g : Double, b : Double) -> Double {
  let out = FixedArray::make(2, 0.0)
  ffi_draw_timed(inst, count, r, g, b, out)
  out[1]
}
