///|
/// What was printed and still waits in the process's buffers, written out before it stops: a test program's output is
/// a file, fully buffered on Linux, and an abort writes nothing of it (its words lost, and the test that halted said
/// as never begun: #5419). libc's own `fflush(NULL)`, every stream: no stub of its own, so whatever links this package
/// (the apps, the tests, station's reader) needs nothing more compiled. (moonc's prototype of it is <stdio.h> in mbc's
/// units: tools/mbc's csplit.mbt, `libc_declared`.)
extern "C" fn c_fflush(all : UInt64) -> Int = "fflush"

///|
fn flush_out() -> Unit {
  ignore(c_fflush(0UL))
}
