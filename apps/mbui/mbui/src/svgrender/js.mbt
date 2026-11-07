///|
#external
type Db
///|
extern "js" fn db_new() -> Db =
  #| () => globalThis.mbuiSvg.create()
///|
extern "js" fn db_free(db : Db) -> Unit =
  #| db => globalThis.mbuiSvg.free(db)
///|
extern "js" fn db_add(db : Db, data : Bytes) -> Unit =
  #| (db, data) => globalThis.mbuiSvg.add(db, data)
///|
extern "js" fn db_draw(db : Db, data : Bytes, side : Int) -> Bytes =
  #| (db, data, side) => globalThis.mbuiSvg.draw(db, data, side)
