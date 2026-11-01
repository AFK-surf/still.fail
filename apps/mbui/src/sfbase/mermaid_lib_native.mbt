///|
// kept across runs: the same words once made
let mermaid_words : Ref[String?] = Ref(None)

///|
/// mermaid's script as the host takes it: carried in the code gzipped (mermaid_lib.mbt), unzipped once.
pub fn viz_mermaid_lib() -> String {
  match mermaid_words.val {
    Some(s) => s
    None => {
      let s = match @zip.gunzip(mermaid_gz) {
        Some(b) => @utf8.decode_lossy(b)
        None => ""
      }
      mermaid_words.val = Some(s)
      s
    }
  }
}

///|
/// mermaid as the core is given it (`mermaid.load`, viz_mermaid.mbt): its Hermes bytecode (mermaid_hbc.mbt), unzipped
/// (once a run: the core keeps it).
fn viz_mermaid_script() -> Bytes? {
  @zip.gunzip(mermaid_hbc_gz)
}
