// The engine's side on native hosts: core_native.c (its queue, and the engine an app links in, src/host/core_api.h).

#borrow(data_dir, cloud)
extern "C" fn ffi_start(data_dir : String, cloud : String, beta : Int) -> Int = "mbc_start"

#borrow(json)
extern "C" fn ffi_send(json : String) -> Unit = "mbc_send"

extern "C" fn ffi_stop() -> Unit = "mbc_stop"

extern "C" fn ffi_next() -> String = "mbc_next"

extern "C" fn ffi_set_wake(f : FuncRef[() -> Unit]) -> Unit = "mbc_set_wake"

#borrow(url, scheme)
extern "C" fn ffi_web_auth(token : Int, url : String, scheme : String) -> Int = "mbc_web_auth"

extern "C" fn ffi_now() -> Double = "mbc_now_ms"
