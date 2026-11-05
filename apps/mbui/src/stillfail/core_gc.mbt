// The core's engine as mbui's native shell answers it on Wasm GC (src/core/native.mbt's calls, as the shell answers
// them on classic Wasm: src/core/native_wasm.mbt): given the core as the program starts (@core.wasm_engine).

///|
fn mbw_mbc_start(data_dir : Int, cloud : Int, beta : Int) -> Int = "mbhost" "mbc_start"

///|
fn mbw_mbc_send(json : Int) = "mbhost" "mbc_send"

///|
fn mbw_mbc_send_bytes(json : Int, bytes : Int) = "mbhost" "mbc_send_bytes"

///|
fn mbw_mbc_stop() = "mbhost" "mbc_stop"

///|
fn mbw_mbc_has_web_auth() -> Int = "mbhost" "mbc_has_web_auth"

///|
fn mbw_mbc_web_auth(token : Int, url : Int, scheme : Int) -> Int = "mbhost" "mbc_web_auth"

///|
fn mbw_mbc_now_ms() -> Double = "mbhost" "mbc_now_ms"

///|
fn mbw_mbc_wall_ms() -> Double = "mbhost" "mbc_wall_ms"

///|
fn mbw_mbc_screen_ack(call : Double, ts : Double) -> Int = "mbhost" "mbc_screen_ack"

///|
fn init {
  @core.wasm_engine.val = Some({
    start: fn(data_dir, cloud, beta) {
      let m = @wasmrt.mark()
      let r = mbw_mbc_start(@wasmrt.string_addr(data_dir), @wasmrt.string_addr(cloud), beta)
      @wasmrt.settle(m)
      r
    },
    send: fn(json) {
      let m = @wasmrt.mark()
      mbw_mbc_send(@wasmrt.string_addr(json))
      @wasmrt.settle(m)
    },
    send_bytes: fn(json, bytes) {
      let m = @wasmrt.mark()
      mbw_mbc_send_bytes(@wasmrt.string_addr(json), @wasmrt.bytes_addr(bytes))
      @wasmrt.settle(m)
    },
    stop: fn() { mbw_mbc_stop() },
    has_web_auth: fn() { mbw_mbc_has_web_auth() },
    web_auth: fn(token, url, scheme) {
      let m = @wasmrt.mark()
      let r = mbw_mbc_web_auth(token, @wasmrt.string_addr(url), @wasmrt.string_addr(scheme))
      @wasmrt.settle(m)
      r
    },
    now: fn() { mbw_mbc_now_ms() },
    wall_ms: fn() { mbw_mbc_wall_ms() },
    screen_ack: fn(call, ts) { mbw_mbc_screen_ack(call, ts) },
  })
}
