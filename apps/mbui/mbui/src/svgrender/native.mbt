///|
#external
type Db

///|
extern "C" fn db_new() -> Db = "mbsvg_fonts_new"

///|
extern "C" fn db_free(db : Db) -> Unit = "mbsvg_fonts_free"

///|
#borrow(data)
extern "C" fn db_add(db : Db, data : Bytes) -> Unit = "mbsvg_moon_font"

///|
#borrow(data)
extern "C" fn db_draw(db : Db, data : Bytes, side : Int) -> Bytes = "mbsvg_moon_draw"

///|
#external
type PngDb
///|
extern "C" fn png_new(w : Int, h : Int) -> PngDb = "mbpng_new"
///|
extern "C" fn png_valid(p : PngDb) -> Bool = "mbpng_moon_valid"
///|
#borrow(data)
extern "C" fn png_add(p : PngDb, data : Bytes, n : Int) -> Bool = "mbpng_moon_add"
///|
extern "C" fn png_end(p : PngDb) -> Bytes = "mbpng_moon_end"
///|
extern "C" fn png_free(p : PngDb) -> Unit = "mbpng_free"
