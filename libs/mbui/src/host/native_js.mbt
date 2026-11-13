// native.mbt's calls in a browser: web/host.js takes none (0).

///|
extern "js" fn ncall_call(name : String, params : String) -> Int =
  #|(n, p) => (globalThis.__mbhost && globalThis.__mbhost.nativeCall ? globalThis.__mbhost.nativeCall(n, p) : 0)

///|
extern "js" fn ncall_state(id : Int) -> Int =
  #|(id) => globalThis.__mbhost.nativeState(id)

///|
extern "js" fn ncall_result(id : Int) -> String =
  #|(id) => globalThis.__mbhost.nativeResult(id)

///|
extern "js" fn ncall_end(id : Int) -> Unit =
  #|(id) => globalThis.__mbhost.nativeEnd(id)
