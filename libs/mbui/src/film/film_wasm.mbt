// The film on Wasm (classic, the Wasm scene's: still.fail's src/sfwasmfilm): the drawing and the writing the Mac host's
// own (src/host/apple_render.m, apple_film.m), through the scene's Node host (still.fail's tools/wasm-film); the
// process's few needs (its arguments, a line said, a file read or written, its end) the Node host's. Strings go out as
// `wasm_text` (the host reads it through the program's exports: wasm_text_length, wasm_text_unit) and come back a
// unit at a time (got_length, got_unit); a frame's instances out as `wasm_inst` (wasm_item).

///|
let supported = true

///|
/// What the host is to read next: a path, a name, a line, a file's text.
pub let wasm_text : Ref[String] = Ref("")

///|
/// The instances of the frame the host is to draw.
pub let wasm_inst : Ref[FixedArray[Double]] = Ref(FixedArray::make(0, 0.0))

///|
pub fn wasm_text_length() -> Int {
  wasm_text.val.length()
}

///|
pub fn wasm_text_unit(i : Int) -> Int {
  wasm_text.val.code_unit_at(i).to_int()
}

///|
pub fn wasm_item(i : Int) -> Double {
  wasm_inst.val[i]
}

///|
fn h_got_length() -> Int = "film" "gotLength"

///|
fn h_got_unit(i : Int) -> Int = "film" "gotUnit"

///|
fn h_hold() -> Unit = "film" "hold"

///|
fn h_arg() -> Unit = "film" "arg"

///|
fn h_say() -> Unit = "film" "say"

///|
fn h_read() -> Unit = "film" "read"

///|
fn h_write() -> Int = "film" "write"

///|
fn h_exit(code : Int) -> Unit = "film" "exit"

///|
fn h_init(w : Double, h : Double, scale : Double) -> Unit = "film" "init"

///|
fn h_view(w : Double, h : Double, scale : Double) -> Unit = "film" "view"

///|
fn h_open(w : Int, h : Int, fps : Int) -> Int = "film" "open"

///|
fn h_draw(count : Int, r : Double, g : Double, b : Double) -> Int = "film" "draw"

///|
fn h_put(k : Int) -> Int = "film" "put"

///|
fn h_close(frames : Int) -> Int = "film" "close"

///|
fn h_finish(publish : Int) -> Int = "film" "finish"

///|
fn h_snapshot(transparent : Int) -> Int = "film" "snapshot"

///|
fn h_spin(ms : Double) -> Unit = "film" "spin"

///|
fn h_now() -> Double = "film" "now"

///|
fn h_mark(frame : Int, end : Int) -> Unit = "film" "mark"

///|
/// A measured frame drawn begins (`end` false) or ends: told to the host, which counts what a profiled program runs
/// between the two (mbui's wasm_shell.c with MBUI_PROFILE_FILE; scripts/wasmgas).
fn mark(frame : Int, end : Bool) -> Unit {
  h_mark(frame, if end { 1 } else { 0 })
}

///|
/// What the host answered last.
fn got() -> String {
  let out = StringBuilder()
  for i in 0..<h_got_length() {
    out.write_char(h_got_unit(i).unsafe_to_char())
  }
  out.to_string()
}

///|
/// The bench's timed draw: not on Wasm (its times are the native host's), nothing timed.
fn draw_timed(
  inst : FixedArray[Double],
  count : Int,
  r : Double,
  g : Double,
  b : Double,
  parts : Array[(Double, Double, Double, Double)],
  out : FixedArray[Double],
) -> Unit {
  ignore((inst, count, r, g, b, parts))
  out[0] = 0.0
  out[1] = 0.0
}

///|
fn now_ms() -> Double {
  h_now()
}

///|
fn init_offscreen(w : Double, h : Double, scale : Double) -> Unit {
  h_init(w, h, scale)
}

///|
fn set_offscreen_view(w : Double, h : Double, scale : Double) -> Unit {
  h_view(w, h, scale)
}

///|
fn open(path : String, w : Int, h : Int, fps : Int) -> Bool {
  wasm_text.val = path
  h_open(w, h, fps) != 0
}

///|
fn draw(inst : FixedArray[Double], count : Int, r : Double, g : Double, b : Double) -> Bool {
  wasm_inst.val = inst
  h_draw(count, r, g, b) != 0
}

///|
fn put_frame(k : Int) -> Bool {
  h_put(k) != 0
}

///|
fn close(frames : Int) -> Bool {
  h_close(frames) != 0
}

///|
fn finish(publish : Bool) -> Bool {
  h_finish(if publish { 1 } else { 0 }) != 0
}

///|
fn snapshot(path : String) -> Bool {
  wasm_text.val = path
  h_snapshot(0) != 0
}

///|
fn snapshot_transparent(path : String) -> Bool {
  wasm_text.val = path
  h_snapshot(1) != 0
}

///|
fn spin(ms : Double) -> Unit {
  h_spin(ms)
}

///|
/// (for a film program too: a tool's output and its files)
pub fn say(s : String) -> Unit {
  wasm_text.val = s
  h_say()
}

///|
/// (for a film program too: a tool's output and its files)
pub fn read_text(path : String) -> String {
  wasm_text.val = path
  h_read()
  got()
}

///|
/// (for a film program too: a tool's output and its files)
pub fn write_text(path : String, text : String) -> Bool {
  wasm_text.val = path
  h_hold()
  wasm_text.val = text
  h_write() != 0
}

///|
/// (for a film program too: a tool's output and its files)
pub fn exit(code : Int) -> Unit {
  h_exit(code)
}

///|
fn ffi_arg(name : String) -> String {
  wasm_text.val = name
  h_arg()
  got()
}
