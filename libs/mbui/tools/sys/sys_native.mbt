// What sys.mbt asks of the system on native: sys.c.

///|
extern "C" fn c_ok() -> Int = "tsys_ok"

///|
#borrow(path)
extern "C" fn c_read(path : Bytes) -> Bytes = "tsys_read"

///|
#borrow(path, data)
extern "C" fn c_write(path : Bytes, data : Bytes) -> Int = "tsys_write"

///|
#borrow(path)
extern "C" fn c_kind(path : Bytes) -> Int = "tsys_kind"

///|
#borrow(path)
extern "C" fn c_mkdir(path : Bytes) -> Int = "tsys_mkdir"

///|
#borrow(path)
extern "C" fn c_remove(path : Bytes) -> Int = "tsys_remove"

///|
#borrow(path)
extern "C" fn c_list(path : Bytes) -> Bytes = "tsys_list"

///|
#borrow(name)
extern "C" fn c_getenv(name : Bytes) -> Bytes = "tsys_getenv"

///|
extern "C" fn c_getcwd() -> Bytes = "tsys_getcwd"

///|
#borrow(s)
extern "C" fn c_out(s : Bytes, err : Int) -> Unit = "tsys_out"

///|
extern "C" fn c_exit(code : Int) -> Unit = "tsys_exit"

///|
#borrow(path)
extern "C" fn c_is_link(path : Bytes) -> Int = "tsys_is_link"

///|
extern "C" fn c_read_stdin() -> Bytes = "tsys_read_stdin"

///|
#borrow(cmd)
extern "C" fn c_run_out(cmd : Bytes) -> Bytes = "tsys_run_out"

