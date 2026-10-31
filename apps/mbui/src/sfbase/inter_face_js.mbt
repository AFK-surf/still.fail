// In a browser the files the app carries come beside its script (tools/assets; still.fail's web/src/mbui/core.ts
// `globalThis.__mbassets`); none where the page gave none.

///|
/// A file the page fetched for the app, by its name in tools/assets (empty where it did not).
extern "js" fn carried(name : String) -> Bytes =
  #|(n) => { const a = globalThis.__mbassets; return (a && a[n]) || new Uint8Array(0) }

///|
/// Inter's variable file, gzipped (inter_face.mbt on the native hosts).
// kept across runs: a file's bytes, never written
let inter_gz : Bytes = carried("inter.ttf.gz")
