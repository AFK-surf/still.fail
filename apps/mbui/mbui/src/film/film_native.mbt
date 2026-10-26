// The film on a native host: the drawing is the host's offscreen path (src/host/apple_render.m), the writing and the
// process's few needs src/host/apple_film.m's, linked with the host by the film's program (its main imports
// mbui/host). Apple's systems only: the other hosts have no film.

///|
let supported = true

///|
extern "C" fn ffi_init_offscreen(w : Double, h : Double, scale : Double) -> Unit = "mb_render_init_offscreen"

///|
#borrow(path)
extern "C" fn ffi_open(path : String, w : Int, h : Int, fps : Int) -> Int = "mbf_open"

///|
#borrow(inst)
extern "C" fn ffi_draw(inst : FixedArray[Double], count : Int, r : Double, g : Double, b : Double) -> Int = "mbf_draw"

///|
extern "C" fn ffi_put(k : Int) -> Int = "mbf_put"

///|
extern "C" fn ffi_close(frames : Int) -> Int = "mbf_close"

///|
extern "C" fn ffi_spin(ms : Double) -> Unit = "mbf_spin"

///|
#borrow(name)
extern "C" fn ffi_arg(name : String) -> String = "mbf_arg"

///|
#borrow(s)
extern "C" fn ffi_say(s : String) -> Unit = "mbf_say"

///|
#borrow(path)
extern "C" fn ffi_read_text(path : String) -> String = "mbf_read_text"

///|
#borrow(path, text)
extern "C" fn ffi_write_text(path : String, text : String) -> Int = "mbf_write_text"

///|
extern "C" fn ffi_exit(code : Int) -> Unit = "mbf_exit"

///|
#borrow(path)
extern "C" fn ffi_snapshot(path : String) -> Int = "mbf_snapshot"

///|
fn init_offscreen(w : Double, h : Double, scale : Double) -> Unit {
  ffi_init_offscreen(w, h, scale)
}

///|
/// A film begun at `path`, `w` × `h` pixels, `fps` frames a second.
fn open(path : String, w : Int, h : Int, fps : Int) -> Bool {
  ffi_open(path, w, h, fps) != 0
}

///|
/// The instances drawn offscreen, read back as the film's picture from now on.
fn draw(inst : FixedArray[Double], count : Int, r : Double, g : Double, b : Double) -> Unit {
  ignore(ffi_draw(inst, count, r, g, b))
}

///|
/// The picture drawn last written as the film's frame `k`.
fn put_frame(k : Int) -> Bool {
  ffi_put(k) != 0
}

///|
/// The film ended after `frames` frames and written out whole.
fn close(frames : Int) -> Bool {
  ffi_close(frames) != 0
}

///|
/// The frame drawn last, as the renderer drew it, written to `path` (a PNG).
fn snapshot(path : String) -> Bool {
  ffi_snapshot(path) != 0
}

///|
fn spin(ms : Double) -> Unit {
  ffi_spin(ms)
}

///|
/// (for a film program too: a tool's output and its files)
pub fn say(s : String) -> Unit {
  ffi_say(s)
}

///|
/// (for a film program too: a tool's output and its files)
pub fn read_text(path : String) -> String {
  ffi_read_text(path)
}

///|
/// (for a film program too: a tool's output and its files)
pub fn write_text(path : String, text : String) -> Bool {
  ffi_write_text(path, text) != 0
}

///|
/// (for a film program too: a tool's output and its files)
pub fn exit(code : Int) -> Unit {
  ffi_exit(code)
}
