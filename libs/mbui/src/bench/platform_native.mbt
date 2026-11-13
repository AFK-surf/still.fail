// The native side: Metal offscreen (src/host/apple_render.m) and the
// process's clocks (bench_stub.c).

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
extern "C" fn ffi_cpu_ms() -> Double = "mbb_cpu_ms"

///|
extern "C" fn ffi_unix_time() -> Double = "mbb_unix_time"

///|
#borrow(path, line)
extern "C" fn ffi_append(path : String, line : String) -> Int = "mbb_append"

///|
#borrow(s)
extern "C" fn ffi_print(s : String) -> Unit = "mbb_print"

///|
#borrow(path)
extern "C" fn ffi_snapshot(path : String) -> Int = "mbb_snapshot"

///|
let supported = true

///|
/// The last frame drawn, as a PNG.
fn snapshot(path : String) -> Unit {
  ffi_snapshot(path) |> ignore
}

///|
fn init_offscreen(w : Double, h : Double, scale : Double) -> Unit {
  ffi_init_offscreen(w, h, scale)
}

///|
fn draw_timed(inst : FixedArray[Double], count : Int, out : FixedArray[Double]) -> Unit {
  ffi_draw_timed(inst, count, 0.961, 0.961, 0.969, out)
}

///|
fn cpu_ms() -> Double {
  ffi_cpu_ms()
}

///|
fn unix_time() -> Double {
  ffi_unix_time()
}

///|
fn append_line(path : String, line : String) -> Bool {
  ffi_append(path, line) != 0
}

///|
fn status(s : String) -> Unit {
  ffi_print(s)
}
