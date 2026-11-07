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
