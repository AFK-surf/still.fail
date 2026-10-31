// In a browser the files the app carries come beside its script (tools/assets; still.fail's web/src/mbui/core.ts
// `globalThis.__mbassets`); none where the page gave none.

///|
/// A file the page fetched for the app, by its name (empty where it did not).
extern "js" fn carried(name : String) -> Bytes =
  #|(n) => { const a = globalThis.__mbassets; return (a && a[n]) || new Uint8Array(0) }

///|
/// Inter's file as the page fetched it: the web's own (its pages' @fontsource-variable/inter, WOFF2, the Latin the
/// app's words are in, a twelfth of the whole face's bytes: what it has not, the page's faces draw); none where it
/// did not.
fn inter_face() -> Bytes? {
  let b = carried("inter.woff2")
  if b.length() > 0 {
    Some(b)
  } else {
    None
  }
}
