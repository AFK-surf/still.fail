///|
struct Db { handle : Int }

///|
fn allocate(n : Int) -> Int = "mbui_svg" "mbsvg_buffer_new"
///|
fn write(p : Int, i : Int, b : Int) -> Unit = "mbui_svg" "mbsvg_buffer_write"
///|
fn read(p : Int, i : Int) -> Int = "mbui_svg" "mbsvg_buffer_read"
///|
fn release(p : Int, n : Int) -> Unit = "mbui_svg" "mbsvg_buffer_free"
///|
fn fonts_new() -> Int = "mbui_svg" "mbsvg_fonts_new"
///|
fn fonts_add(db : Int, p : Int, n : Int) -> Unit = "mbui_svg" "mbsvg_fonts_add"
///|
fn fonts_free(db : Int) -> Unit = "mbui_svg" "mbsvg_fonts_free"
///|
fn draw(db : Int, p : Int, n : Int, side : Int) -> Int = "mbui_svg" "mbsvg_rasterize_app"
///|
fn size(p : Int) -> Int = "mbui_svg" "mbsvg_raster_length"

///|
fn upload(b : Bytes) -> Int {
  let p = allocate(b.length())
  for i in 0..<b.length() { write(p, i, b[i].to_int()) }
  p
}
///|
fn db_new() -> Db { { handle: fonts_new() } }
///|
fn db_free(db : Db) -> Unit { fonts_free(db.handle) }
///|
fn db_add(db : Db, data : Bytes) -> Unit {
  let p = upload(data)
  fonts_add(db.handle, p, data.length())
  release(p, data.length())
}
///|
fn db_draw(db : Db, data : Bytes, side : Int) -> Bytes {
  let p = upload(data)
  let out = draw(db.handle, p, data.length(), side)
  release(p, data.length())
  if out == 0 { return b"" }
  let n = size(out)
  let bytes = FixedArray::make(n, b'\x00')
  for i in 0..<n { bytes[i] = read(out, i).to_byte() }
  release(out, n)
  Bytes::from_fixedarray(bytes)
}

///|
struct PngDb { handle : Int }
///|
fn png_create(w : Int, h : Int) -> Int = "mbui_svg" "mbpng_new"
///|
fn png_write(p : Int, data : Int, len : Int, count : Int) -> Bool = "mbui_svg" "mbpng_add"
///|
fn png_finish(p : Int) -> Int = "mbui_svg" "mbpng_end"
///|
fn png_drop(p : Int) -> Unit = "mbui_svg" "mbpng_free"
///|
fn png_output_ptr(p : Int) -> Int = "mbui_svg" "mbpng_output_ptr"
///|
fn png_output_len(p : Int) -> Int = "mbui_svg" "mbpng_output_len"
///|
fn png_output_free(p : Int) -> Unit = "mbui_svg" "mbpng_output_free"
///|
fn png_new(w : Int, h : Int) -> PngDb { { handle: png_create(w, h) } }
///|
fn png_valid(p : PngDb) -> Bool { p.handle != 0 }
///|
fn png_add(p : PngDb, data : Bytes, n : Int) -> Bool {
  let bytes = upload(data)
  let ok = png_write(p.handle, bytes, data.length(), n)
  release(bytes, data.length())
  ok
}
///|
fn png_end(p : PngDb) -> Bytes {
  let output = png_finish(p.handle)
  if output == 0 { return b"" }
  let n = png_output_len(output)
  let ptr = png_output_ptr(output)
  let bytes = FixedArray::make(n, b'\x00')
  for i in 0..<n { bytes[i] = read(ptr, i).to_byte() }
  png_output_free(output)
  Bytes::from_fixedarray(bytes)
}
///|
fn png_free(p : PngDb) -> Unit { png_drop(p.handle) }
