// terminal.mbt's calls on a native host (term.h, which each host's C includes).

///|
extern "C" fn tm_open(cols : Int, rows : Int) -> Int = "mb_host_term_open"

///|
#borrow(data)
extern "C" fn tm_write(id : Int, data : Bytes) -> Unit = "mb_host_term_write"

///|
extern "C" fn tm_resize(id : Int, cols : Int, rows : Int) -> Unit = "mb_host_term_resize"

///|
extern "C" fn tm_lines(id : Int) -> String = "mb_host_term_lines"

///|
extern "C" fn tm_close(id : Int) -> Unit = "mb_host_term_close"
