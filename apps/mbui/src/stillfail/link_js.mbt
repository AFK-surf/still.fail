///|
/// Whether the page gives the core (still.fail's web/src/mbui/core.ts: `globalThis.__mbcore`, mbui/core's js.mbt).
extern "js" fn core_linked() -> Int =
  #|() => (globalThis.__mbcore ? 1 : 0)

///|
/// Nothing takes it on the web.
fn host_tell(what : String, a : String, b : String, n : Int, m : Int) -> Int {
  ignore((what, a, b, n, m))
  0
}
