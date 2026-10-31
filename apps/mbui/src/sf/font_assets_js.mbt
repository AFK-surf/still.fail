// In a browser the files the app carries come beside its script (tools/assets writes them for the web's build, the page
// fetches them before the app starts: still.fail's web/src/mbui/core.ts `globalThis.__mbassets`); none where the page
// gave none (the headless runs).

///|
/// A file the page fetched for the app, by its name in tools/assets (empty where it did not).
extern "js" fn carried(name : String) -> Bytes =
  #|(n) => { const a = globalThis.__mbassets; return (a && a[n]) || new Uint8Array(0) }

///|
/// apps/mbui/assets/fonts/jetbrains_mono.ttf, its bytes (font_assets.mbt on the native hosts).
// kept across runs: a file's bytes, never written
let code_face_ttf : Bytes = carried("jetbrains_mono.ttf")
