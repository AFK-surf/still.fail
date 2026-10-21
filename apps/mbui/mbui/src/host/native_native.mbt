// native.mbt's calls on a native host (android_device.h: dev.mbui.Natives; apple_device.h, win_device.h: none).

///|
#borrow(name, params)
extern "C" fn ncall_call(name : String, params : String) -> Int = "mb_host_native_call"

///|
extern "C" fn ncall_state(id : Int) -> Int = "mb_host_native_state"

///|
extern "C" fn ncall_result(id : Int) -> String = "mb_host_native_result"

///|
extern "C" fn ncall_end(id : Int) -> Unit = "mb_host_native_end"
