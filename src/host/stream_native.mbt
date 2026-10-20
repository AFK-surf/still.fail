// Streams (stream.mbt) on a native host: android_host.c with Streams.java, apple_stream.m, win_stream.cpp.

///|
extern "C" fn st_open() -> Int = "mb_host_stream_open"

///|
#borrow(avcc)
extern "C" fn st_h264(id : Int, avcc : Bytes, w : Int, h : Int) -> Unit = "mb_host_stream_h264"

///|
#borrow(data)
extern "C" fn st_frame(id : Int, data : Bytes, key : Int, ts : Double) -> Unit = "mb_host_stream_frame"

///|
#borrow(data)
extern "C" fn st_jpeg(id : Int, data : Bytes, ts : Double) -> Unit = "mb_host_stream_jpeg"

///|
extern "C" fn st_next(id : Int) -> String = "mb_host_stream_next"

///|
extern "C" fn st_show(id : Int, ts : Double) -> Unit = "mb_host_stream_show"

///|
extern "C" fn st_close(id : Int) -> Unit = "mb_host_stream_close"

///|
extern "C" fn st_h264_here() -> Int = "mb_host_h264_here"
