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

///|
#external
type PngDb
///|
extern "js" fn png_new(w : Int, h : Int) -> PngDb =
  #| (w,h) => { try { return globalThis.mbuiSvg.createPng(w,h); } catch { return null; } }
///|
extern "js" fn png_valid(p : PngDb) -> Bool =
  #| p => p !== null
///|
extern "js" fn png_add(p : PngDb, data : Bytes, n : Int) -> Bool =
  #| (p,data,n) => { try { p.add(data,n); return true; } catch { return false; } }
///|
extern "js" fn png_end(p : PngDb) -> Bytes =
  #| p => { try { return p.end(); } catch { return new Uint8Array(); } }
///|
extern "js" fn png_free(p : PngDb) -> Unit =
  #| p => p.close()
