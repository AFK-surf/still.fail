// The engine's side on native hosts: core_native.c (what it says posted to mbui's queue, and the engine an app links in,
// src/host/core_api.h).

#borrow(data_dir, cloud)
extern "C" fn ffi_start(data_dir : String, cloud : String, beta : Int) -> Int = "mbc_start"

#borrow(json)
extern "C" fn ffi_send(json : String) -> Unit = "mbc_send"

#borrow(json, bytes)
extern "C" fn ffi_send_bytes(json : String, bytes : Bytes) -> Unit = "mbc_send_bytes"

///|
extern "C" fn ffi_stop() -> Unit = "mbc_stop"

extern "C" fn ffi_has_web_auth() -> Int = "mbc_has_web_auth"

#borrow(url, scheme)
extern "C" fn ffi_web_auth(token : Int, url : String, scheme : String) -> Int = "mbc_web_auth"

extern "C" fn ffi_now() -> Double = "mbc_now_ms"

extern "C" fn ffi_wall_ms() -> Double = "mbc_wall_ms"

extern "C" fn ffi_screen_ack(call : Double, ts : Double) -> Int = "mbc_screen_ack"

///|
/// Where the cloud sends a sign-in back to: the app's own scheme, which the system's browser session hands back.
fn auth_redirect() -> String {
  "stillfail://auth/callback"
}

///|
fn auth_return_to() -> String {
  "/"
}
