// In a browser the sources the page shows come beside its script (scripts/kit-web.sh's sources.txt, given by
// scripts/kit.html as `globalThis.__mbassets` before the app starts); none where the page gave none.

///|
extern "js" fn carried(name : String) -> Bytes =
  #|(n) => { const a = globalThis.__mbassets; return (a && a[n]) || new Uint8Array(0) }
