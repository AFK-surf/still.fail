// What logwait asks of the system on native: events.c.

///|
extern "C" fn ev_init() -> Int = "chk_ev_init"

///|
#borrow(path)
extern "C" fn ev_open(k : Int, path : Bytes) -> Int = "chk_ev_open"

///|
#borrow(path)
extern "C" fn ev_open_path(k : Int, path : Bytes) -> Int = "chk_ev_open_path"

///|
extern "C" fn ev_read(k : Int) -> Bytes = "chk_ev_read"

///|
extern "C" fn ev_file(k : Int) -> Int = "chk_ev_file"

///|
#borrow(path)
extern "C" fn ev_dir(path : Bytes) -> Int = "chk_ev_dir"

///|
extern "C" fn ev_pid(pid : Int) -> Int = "chk_ev_pid"

///|
extern "C" fn ev_wait(ms : Int) -> Int = "chk_ev_wait"

