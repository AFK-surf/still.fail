// device.mbt's calls on a native host (android_device.h, apple_device.h, win_device.h).

///|
extern "C" fn cl_read() -> Int = "mb_host_clip_read"

///|
extern "C" fn cl_state(id : Int) -> Int = "mb_host_clip_state"

///|
extern "C" fn cl_picture(id : Int) -> Int = "mb_host_clip_picture"

///|
extern "C" fn cl_text(id : Int) -> String = "mb_host_clip_text"

///|
extern "C" fn cl_png(id : Int) -> Bytes = "mb_host_clip_png"

///|
extern "C" fn cl_end(id : Int) -> Unit = "mb_host_clip_end"

///|
#borrow(text, png, label)
extern "C" fn cl_set(text : String, png : Bytes, label : String) -> Unit = "mb_host_clip_set"

///|
extern "C" fn dv_copy_shown() -> Int = "mb_host_copy_shown"

///|
extern "C" fn dv_key_catch(on : Int) -> Unit = "mb_host_key_catch"

///|
extern "C" fn dv_ime_inset() -> Double = "mb_host_ime_inset"

///|
extern "C" fn dv_keep_awake(on : Int) -> Unit = "mb_host_keep_awake"

///|
extern "C" fn dv_haptic(kind : Int) -> Unit = "mb_host_haptic"
