///|
/// What was printed and still waits in the process's buffers, written out before it stops: a test program's output is
/// a file, fully buffered on Linux, and an abort writes nothing of it (its words lost, and the test that halted said
/// as never begun: #5419). `fflush(NULL)`, every stream, by halt_flush.c (why a stub there says).
extern "C" fn c_flush() -> Int = "mbui_halt_flush"

///|
fn flush_out() -> Unit {
  ignore(c_flush())
}
